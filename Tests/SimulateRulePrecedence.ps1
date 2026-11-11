# Script de Simulação e Verificação de Sobreposição / Precedência de Regras
# Espelha o comportamento exato de RideRuleEngine.swift (com remoção de acentos e case insensitive)

$ErrorActionPreference = "Stop"

function Normalize-Text {
    param([string]$text)
    if ([string]::IsNullOrEmpty($text)) { return "" }
    $formD = $text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($char in $formD.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return $sb.ToString().ToLower()
}

function Match-Keyword {
    param(
        [string]$text,
        [string[]]$keywords
    )
    $normText = Normalize-Text -text $text
    foreach ($k in $keywords) {
        $normK = Normalize-Text -text $k
        if (-not [string]::IsNullOrWhiteSpace($normK) -and $normText.Contains($normK)) {
            return $k
        }
    }
    return $null
}

function Evaluate-RideRule {
    param(
        [string]$Scenario,
        [double]$ValorTotal,
        [double]$TempoBuscaMin,
        [double]$KmBusca,
        [string]$EnderecoBusca,
        [double]$TempoViagemMin,
        [double]$KmViagem,
        [string]$EnderecoDestino,
        [bool]$TemParada = $false,
        [double]$NotaPassageiro = 4.95,
        [int]$ViagensPassageiro = 150,
        [bool]$Dinheiro = $false,
        [bool]$IsGoingHomeMode = $false,
        [bool]$IsTrafficMode = $false,
        [double]$AppleMapsMinutes = 0.0,
        [double]$CurrentDailyNetProfit = 0.0
    )

    # Configurações padrão de Maringá, Sarandi e Marialva
    $dangerZoneKeywords = @("santa felicidade", "guedner", "parigot", "proibida", "vila candida")
    $blacklistedKeywords = @("marialva", "iguatemi", "floriano")
    $marketPickupKeywords = @("atacadao", "assai", "muffato", "condor", "supermercado", "mercado")
    $favoriteHomeKeywords = @("maringa", "centro", "zona 01", "casa")

    $custoPorKm = 0.95
    $goldGanhoHora = 50.0
    $goldGanhoKm = 2.00
    $maxTempoBuscaMin = 5.0
    $maxKmBusca = 2.2
    $minGanhoKmNormal = 1.65
    $minGanhoHoraNormal = 40.0
    $minGanhoKmListaNegra = 2.00
    $minGanhoKmRumoACasa = 1.40
    $minViagensPassageiro = 10
    $minNotaPassageiro = 4.75
    $minValorCorrida = 7.50
    $metaDiariaLiquida = 250.0

    $kmTotal = $KmBusca + $KmViagem
    $tempoTotal = $TempoBuscaMin + $TempoViagemMin
    $ganhoKm = if ($kmTotal -gt 0) { $ValorTotal / $kmTotal } else { 0 }

    # Destino Marialva / Iguatemi / Floriano (Cobra volta vazia se o embarque não for lá)
    $destinationDeadheadMatch = Match-Keyword -text $EnderecoDestino -keywords $blacklistedKeywords
    $pickupDeadheadMatch = Match-Keyword -text $EnderecoBusca -keywords $blacklistedKeywords

    $isGoingToDeadheadDestination = ($destinationDeadheadMatch -ne $null) -and ($pickupDeadheadMatch -eq $null)
    $isReturningFromOutskirts = ($pickupDeadheadMatch -ne $null -or (Match-Keyword -text $EnderecoBusca -keywords @("sarandi", "marialva")) -ne $null) -and ((Match-Keyword -text $EnderecoDestino -keywords $favoriteHomeKeywords) -ne $null)

    $extraReturnKm = if ($isGoingToDeadheadDestination) { $KmViagem * 0.60 } else { 0.0 }
    $extraReturnMinutes = if ($isGoingToDeadheadDestination) { $TempoViagemMin * 0.55 } else { 0.0 }

    $baseRideMinutes = if ($AppleMapsMinutes -gt 0) { $AppleMapsMinutes } else { $tempoTotal }
    $effectiveGanhoHora = if ($baseRideMinutes -gt 0) { $ValorTotal / ($baseRideMinutes / 60.0) } else { 0 }
    $effectiveVelMedia = if ($baseRideMinutes -gt 0) { $kmTotal / ($baseRideMinutes / 60.0) } else { 0 }

    $lucroLiq = $ValorTotal - (($kmTotal + $extraReturnKm) * $custoPorKm)
    $ganhoHoraLiqComVolta = if (($tempoTotal + $extraReturnMinutes) -gt 0) { $lucroLiq / (($tempoTotal + $extraReturnMinutes) / 60.0) } else { 0 }

    # ============================================================
    # EXECUÇÃO SEQUENCIAL TOP-DOWN DAS REGRAS (RideRuleEngine.swift)
    # ============================================================

    # PRIORIDADE 1: Zona de Risco Manual (Segurança Máxima)
    $matchedDanger = Match-Keyword -text "$EnderecoBusca $EnderecoDestino" -keywords $dangerZoneKeywords
    if ($matchedDanger -ne $null) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "REJECTED (VERMELHO)"
            RegraVencedora = "PRIORIDADE 1: PERIGO ($($matchedDanger.ToUpper()))"
            Explicacao = "Segurança em primeiro lugar. Sobrepõe qualquer valor monetário, mesmo que pague R$ 10/km."
        }
    }

    # PRIORIDADE 2: Pagamento em Dinheiro (Modo Noturno / Anti-Calote)
    if ($Dinheiro) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "REJECTED (VERMELHO)"
            RegraVencedora = "PRIORIDADE 2: CILADA (PAGAMENTO EM DINHEIRO)"
            Explicacao = "Modo anti-dinheiro ativo bloqueia a corrida para evitar risco de troco ou calote."
        }
    }

    # PRIORIDADE 3: Múltiplas Paradas
    if ($TemParada) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "REJECTED (VERMELHO)"
            RegraVencedora = "PRIORIDADE 3: CILADA (TEM PARADA)"
            Explicacao = "Paradas intermediárias desperdiçam tempo sem remuneração compatível."
        }
    }

    # PRIORIDADE 4: Nota Baixa Crítica
    if ($NotaPassageiro -lt $minNotaPassageiro) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "REJECTED (VERMELHO)"
            RegraVencedora = "PRIORIDADE 4: CILADA (NOTA BAIXA $NotaPassageiro)"
            Explicacao = "Nota do passageiro abaixo do corte de segurança (< 4.75)."
        }
    }

    # PRIORIDADE 5: Volta Vazia Intermunicipal (Marialva/Iguatemi/Floriano)
    if ($isGoingToDeadheadDestination) {
        if ($ganhoKm -lt $minGanhoKmListaNegra -and $ganhoHoraLiqComVolta -lt 30.0) {
            return [PSCustomObject]@{
                Cenario = $Scenario
                Status = "REJECTED (VERMELHO)"
                RegraVencedora = "PRIORIDADE 5: CILADA (VOLTA VAZIA $($destinationDeadheadMatch.ToUpper()))"
                Explicacao = "Destino cobra volta vazia e o valor oferecido não compensa o retorno sem passageiro."
            }
        }
    }

    # PRIORIDADE 6.1: Embarque em Supermercado / Atacadão (Antes de qualquer aprovação!)
    $matchedMarket = Match-Keyword -text $EnderecoBusca -keywords $marketPickupKeywords
    if ($matchedMarket -ne $null) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "WARNING (AMARELO)"
            RegraVencedora = "PRIORIDADE 6.1: EMBARQUE EM MERCADO ($($matchedMarket.ToUpper()))"
            Explicacao = "Alerta amarelo sobrepõe a Exceção de Ouro para alertar sobre carrinho/compras/sacolas."
        }
    }

    # PRIORIDADE 6.2: Conta Nova / Poucas Viagens (Antes de qualquer aprovação!)
    if ($ViagensPassageiro -lt $minViagensPassageiro) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "WARNING (AMARELO)"
            RegraVencedora = "PRIORIDADE 6.2: CONTA NOVA ($ViagensPassageiro VIAGENS)"
            Explicacao = "Passageiro sem histórico confiável na plataforma. Amarelo preventivo."
        }
    }

    # PRIORIDADE 6.5: Retorno a Maringá / Modo Rumo a Casa
    $matchedHome = Match-Keyword -text $EnderecoDestino -keywords $favoriteHomeKeywords
    if (($IsGoingHomeMode -or $isReturningFromOutskirts) -and $matchedHome -ne $null -and $ganhoKm -ge $minGanhoKmRumoACasa -and $TempoBuscaMin -le $maxTempoBuscaMin) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "GOING_HOME (AZUL)"
            RegraVencedora = "PRIORIDADE 6.5: RETORNO P/ $($matchedHome.ToUpper()) (R$ $([math]::Round($ganhoKm, 2))/km)"
            Explicacao = "Corrida que paga o retorno para o polo central, aceita com piso reduzido (R$ 1,40/km)."
        }
    }

    # PRIORIDADE 7: Exceção de Ouro / Corrida Top / Bate os 250
    $willHitDailyGoal = ($CurrentDailyNetProfit -gt 0.0) -and ($CurrentDailyNetProfit -lt $metaDiariaLiquida) -and (($CurrentDailyNetProfit + $lucroLiq) -ge $metaDiariaLiquida)
    if ($effectiveGanhoHora -ge $goldGanhoHora -and $ganhoKm -ge $goldGanhoKm -and $ValorTotal -ge $minValorCorrida) {
        $msg = if ($willHitDailyGoal) { "BATE OS 250" } elseif ($destinationDeadheadMatch) { "$($destinationDeadheadMatch.ToUpper()) TOP" } else { "CORRIDA TOP" }
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "APPROVED (VERDE)"
            RegraVencedora = "PRIORIDADE 7: EXCEÇÃO DE OURO / $msg"
            Explicacao = "Lucro excepcional: R$ $([math]::Round($ganhoKm, 2))/km e R$ $([math]::Round($effectiveGanhoHora, 0))/h."
        }
    }

    # PRIORIDADE 8: Busca Longa
    if ($TempoBuscaMin -gt $maxTempoBuscaMin -or $KmBusca -gt $maxKmBusca) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "REJECTED (VERMELHO)"
            RegraVencedora = "PRIORIDADE 8: CILADA (BUSCA LONGA)"
            Explicacao = "Busca excessiva (> $maxTempoBuscaMin min ou > $maxKmBusca km), desgasta carro antes de embarcar."
        }
    }

    # PRIORIDADE 9: Valor Muito Baixo (Mixuruca)
    if ($ValorTotal -lt $minValorCorrida) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "WARNING (AMARELO)"
            RegraVencedora = "PRIORIDADE 9: VALOR BAIXO (SÓ R$ $ValorTotal)"
            Explicacao = "Corrida mixuruca abaixo de R$ 7,50."
        }
    }

    # PRIORIDADE 10: Trânsito Lento / Chuva
    if ($IsTrafficMode -or $effectiveVelMedia -lt 25.0) {
        if ($effectiveGanhoHora -lt 40.0) {
            return [PSCustomObject]@{
                Cenario = $Scenario
                Status = "REJECTED (VERMELHO)"
                RegraVencedora = "PRIORIDADE 10: TRÂNSITO PESADO (SÓ R$ $([math]::Round($effectiveGanhoHora, 0))/h)"
                Explicacao = "Trânsito lento derrubou o ganho por hora abaixo do custo de oportunidade."
            }
        } else {
            return [PSCustomObject]@{
                Cenario = $Scenario
                Status = "APPROVED (VERDE)"
                RegraVencedora = "PRIORIDADE 10: APROVADA NO TRÂNSITO (R$ $([math]::Round($effectiveGanhoHora, 0))/h)"
                Explicacao = "Mesmo no trânsito, a tarifa dinâmica compensa o tempo parado."
            }
        }
    }

    # PRIORIDADE 11: Corrida Mediana
    if ($ganhoKm -lt $minGanhoKmNormal -or $effectiveGanhoHora -lt $minGanhoHoraNormal) {
        return [PSCustomObject]@{
            Cenario = $Scenario
            Status = "WARNING (AMARELO)"
            RegraVencedora = "PRIORIDADE 11: MEDIANA (R$ $([math]::Round($ganhoKm, 2))/km)"
            Explicacao = "Paga razoável mas abaixo da meta de alta eficiência."
        }
    }

    # PRIORIDADE 12: Aprovada Comum
    return [PSCustomObject]@{
        Cenario = $Scenario
        Status = "APPROVED (VERDE)"
        RegraVencedora = "PRIORIDADE 12: CORRIDA APROVADA (FILÉ)"
        Explicacao = "Passou limpa por todos os filtros e atinge as metas de km e hora."
    }
}

# Execução da bateria de 10 simulações de sobreposição
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   SIMULAÇÃO DE PRECEDÊNCIA E SOBREPOSIÇÃO DE REGRAS NO COPILOTO" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$testes = @(
    @{
        Scenario = "Cenário 1: Super Valor (R$ 5,00/km) VS Bairro Perigoso (Rua Guedner)"
        ValorTotal = 30.0; TempoBuscaMin = 3; KmBusca = 1.0; EnderecoBusca = "Centro, Maringá"
        TempoViagemMin = 10; KmViagem = 5.0; EnderecoDestino = "Rua Guedner, Santa Felicidade"
    },
    @{
        Scenario = "Cenário 2: Super Valor (R$ 4,00/km) VS Múltiplas Paradas no Trajeto"
        ValorTotal = 24.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Centro, Maringá"
        TempoViagemMin = 12; KmViagem = 5.2; EnderecoDestino = "Zona 07, Maringá"
        TemParada = $true
    },
    @{
        Scenario = "Cenário 3: Super Valor (R$ 3,50/km) VS Embarque em Mercado (Atacadão)"
        ValorTotal = 20.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Atacadão Colombo, Maringá"
        TempoViagemMin = 10; KmViagem = 5.0; EnderecoDestino = "Zona 03, Maringá"
    },
    @{
        Scenario = "Cenário 4: Super Valor (R$ 3,00/km) VS Passageiro Conta Nova (2 viagens)"
        ValorTotal = 18.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Zona 07, Maringá"
        TempoViagemMin = 10; KmViagem = 5.0; EnderecoDestino = "Centro, Maringá"
        ViagensPassageiro = 2
    },
    @{
        Scenario = "Cenário 5: Marialva Comum (R$ 26 / 18 km) que não paga a volta vazia"
        ValorTotal = 26.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Zona 07, Maringá"
        TempoViagemMin = 25; KmViagem = 18.0; EnderecoDestino = "Centro, Marialva"
    },
    @{
        Scenario = "Cenário 6: Marialva Super Paga (R$ 42 / 18 km) que PAGA a ida + a volta!"
        ValorTotal = 42.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Zona 07, Maringá"
        TempoViagemMin = 25; KmViagem = 18.0; EnderecoDestino = "Centro, Marialva"
    },
    @{
        Scenario = "Cenário 7: Retorno Sarandi -> Maringá (R$ 1,50/km - Rumo a Maringá)"
        ValorTotal = 16.5; TempoBuscaMin = 3; KmBusca = 1.2; EnderecoBusca = "Centro, Sarandi"
        TempoViagemMin = 18; KmViagem = 10.0; EnderecoDestino = "Centro, Maringá"
    },
    @{
        Scenario = "Cenário 8: Corrida que Fecha a Meta 250+ (Tem R$ 240 + Líquido R$ 11 = R$ 251!)"
        ValorTotal = 14.0; TempoBuscaMin = 2; KmBusca = 0.6; EnderecoBusca = "Zona 07, Maringá"
        TempoViagemMin = 8; KmViagem = 3.0; EnderecoDestino = "Centro, Maringá"
        CurrentDailyNetProfit = 240.0
    },
    @{
        Scenario = "Cenário 9: Uber estimou 15 min, mas Apple Maps detectou engarrafamento (38 min)"
        ValorTotal = 15.0; TempoBuscaMin = 2; KmBusca = 0.8; EnderecoBusca = "Zona 07, Maringá"
        TempoViagemMin = 13; KmViagem = 4.5; EnderecoDestino = "Zona 05, Maringá"
        AppleMapsMinutes = 38.0
    },
    @{
        Scenario = "Cenário 10: Busca Longa (3.0 km) VS Corrida Comum (R$ 1,80/km)"
        ValorTotal = 14.0; TempoBuscaMin = 6; KmBusca = 3.0; EnderecoBusca = "Parque do Japão, Maringá"
        TempoViagemMin = 10; KmViagem = 4.8; EnderecoDestino = "Centro, Maringá"
    }
)

$index = 1
foreach ($t in $testes) {
    $res = Evaluate-RideRule @t
    $color = switch ($res.Status) {
        { $_.Contains("VERDE") } { "Green" }
        { $_.Contains("AMARELO") } { "Yellow" }
        { $_.Contains("VERMELHO") } { "Red" }
        { $_.Contains("AZUL") } { "Cyan" }
        Default { "White" }
    }
    Write-Host "[$index] $($res.Cenario)" -ForegroundColor White
    Write-Host "    -> Status: $($res.Status)" -ForegroundColor $color
    Write-Host "    -> Regra: $($res.RegraVencedora)" -ForegroundColor Cyan
    Write-Host "    -> Por que venceu: $($res.Explicacao)" -ForegroundColor Gray
    Write-Host ""
    $index++
}
