# Suíte de Fuzzing / Teste de Estresse Massivo (2.000 Corridas)
# Avalia interações entre regras e caça Falsos Negativos (corridas boas que seriam perdidas)
# e Falsos Positivos (ciladas aprovadas).

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
    param([string]$text, [string[]]$keywords)
    $normText = Normalize-Text -text $text
    foreach ($k in $keywords) {
        $normK = Normalize-Text -text $k
        if (-not [string]::IsNullOrWhiteSpace($normK) -and $normText.Contains($normK)) {
            return $k
        }
    }
    return $null
}

function Evaluate-RideSimulator {
    param(
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
        [double]$AppleMapsExtraMinutes = 0.0,
        [double]$CurrentDailyNetProfit = 0.0
    )

    $dangerZoneKeywords = @("santa felicidade", "guedner", "parigot", "proibida", "vila candida")
    $blacklistedKeywords = @("marialva", "iguatemi", "floriano")
    $marketPickupKeywords = @("atacadao", "assai", "muffato", "condor", "supermercado", "mercado")
    $favoriteHomeKeywords = @("maringa", "centro", "zona 01", "zona 1", "zona 7", "zona 07", "casa")

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
    $minGanhoHoraTransito = 40.0
    $metaDiariaLiquida = 250.0

    $kmTotal = $KmBusca + $KmViagem
    $tempoTotal = $TempoBuscaMin + $TempoViagemMin
    $ganhoKm = if ($kmTotal -gt 0) { $ValorTotal / $kmTotal } else { 0 }

    $destinationDeadheadMatch = Match-Keyword -text $EnderecoDestino -keywords $blacklistedKeywords
    $pickupDeadheadMatch = Match-Keyword -text $EnderecoBusca -keywords $blacklistedKeywords

    $isGoingToDeadheadDestination = ($destinationDeadheadMatch -ne $null) -and ($pickupDeadheadMatch -eq $null)
    $isReturningFromOutskirts = ($pickupDeadheadMatch -ne $null -or (Match-Keyword -text $EnderecoBusca -keywords @("sarandi", "marialva")) -ne $null) -and ((Match-Keyword -text $EnderecoDestino -keywords $favoriteHomeKeywords) -ne $null)

    $extraReturnKm = if ($isGoingToDeadheadDestination) { $KmViagem * 0.60 } else { 0.0 }
    $extraReturnMinutes = if ($isGoingToDeadheadDestination) { $TempoViagemMin * 0.55 } else { 0.0 }

    # Apple Maps
    $baseRideMinutes = $tempoTotal + $AppleMapsExtraMinutes
    $effectiveGanhoHora = if ($baseRideMinutes -gt 0) { $ValorTotal / ($baseRideMinutes / 60.0) } else { 0 }
    $effectiveVelMedia = if ($baseRideMinutes -gt 0) { $kmTotal / ($baseRideMinutes / 60.0) } else { 0 }

    $lucroLiq = $ValorTotal - (($kmTotal + $extraReturnKm) * $custoPorKm)
    $ganhoHoraLiqComVolta = if (($tempoTotal + $extraReturnMinutes) -gt 0) { $lucroLiq / (($tempoTotal + $extraReturnMinutes) / 60.0) } else { 0 }

    # PRIORIDADE 1: Zona de Risco Manual
    $matchedDanger = Match-Keyword -text "$EnderecoBusca $EnderecoDestino" -keywords $dangerZoneKeywords
    if ($matchedDanger -ne $null) {
        return @{ Status = "REJECTED"; Reason = "DANGER_ZONE"; Rule = "P1: Zona de Risco ($matchedDanger)" }
    }

    # PRIORIDADE 2: Dinheiro
    if ($Dinheiro) {
        return @{ Status = "REJECTED"; Reason = "CASH"; Rule = "P2: Dinheiro Bloqueado" }
    }

    # PRIORIDADE 3: Paradas
    if ($TemParada) {
        return @{ Status = "REJECTED"; Reason = "STOPS"; Rule = "P3: Tem Parada" }
    }

    # PRIORIDADE 4: Nota Baixa
    if ($NotaPassageiro -lt $minNotaPassageiro) {
        return @{ Status = "REJECTED"; Reason = "LOW_RATING"; Rule = "P4: Nota Baixa ($NotaPassageiro)" }
    }

    # PRIORIDADE 5: Volta Vazia Intermunicipal
    if ($isGoingToDeadheadDestination) {
        if ($ganhoKm -lt $minGanhoKmListaNegra -and $ganhoHoraLiqComVolta -lt 30.0) {
            return @{ Status = "REJECTED"; Reason = "DEADHEAD"; Rule = "P5: Volta Vazia ($destinationDeadheadMatch)" }
        }
    }

    # PRIORIDADE 6.1: Mercado / Atacadão
    $matchedMarket = Match-Keyword -text $EnderecoBusca -keywords $marketPickupKeywords
    if ($matchedMarket -ne $null) {
        return @{ Status = "WARNING"; Reason = "MARKET"; Rule = "P6.1: Mercado ($matchedMarket)" }
    }

    # PRIORIDADE 6.2: Conta Nova
    if ($ViagensPassageiro -lt $minViagensPassageiro) {
        return @{ Status = "WARNING"; Reason = "NEW_ACCOUNT"; Rule = "P6.2: Conta Nova ($ViagensPassageiro viagens)" }
    }

    # PRIORIDADE 6.5: Retorno a Maringá
    $matchedHome = Match-Keyword -text $EnderecoDestino -keywords $favoriteHomeKeywords
    if (($IsGoingHomeMode -or $isReturningFromOutskirts) -and $matchedHome -ne $null -and $ganhoKm -ge $minGanhoKmRumoACasa -and $TempoBuscaMin -le $maxTempoBuscaMin) {
        return @{ Status = "GOING_HOME"; Reason = "RETURN_HOME"; Rule = "P6.5: Retorno p/ $matchedHome" }
    }

    # PRIORIDADE 6.8: Trânsito Pesado Apple Maps (Só bloqueia se o ganho real cair abaixo da meta!)
    $hasHiddenTrafficTrap = ($AppleMapsExtraMinutes -ge 4.0)
    $uberOverestimatedTime = ($AppleMapsExtraMinutes -le -4.0)
    if ($hasHiddenTrafficTrap -and $effectiveGanhoHora -lt $minGanhoHoraTransito) {
        return @{ Status = "REJECTED"; Reason = "MAPS_TRAFFIC_TRAP"; Rule = "P6.8: Maps Trânsito (+${AppleMapsExtraMinutes}m)" }
    }

    # PRIORIDADE 7: Exceção de Ouro (Aprovada se for lucrativa MESMO no trânsito!)
    $willHitDailyGoal = ($CurrentDailyNetProfit -gt 0.0) -and ($CurrentDailyNetProfit -lt $metaDiariaLiquida) -and (($CurrentDailyNetProfit + $lucroLiq) -ge $metaDiariaLiquida)
    if ($matchedMarket -eq $null -and $ViagensPassageiro -ge $minViagensPassageiro -and
        $effectiveGanhoHora -ge $goldGanhoHora -and $ganhoKm -ge $goldGanhoKm -and $ValorTotal -ge $minValorCorrida) {
        $msg = if ($willHitDailyGoal) { "BATE OS 250" } elseif ($uberOverestimatedTime) { "MAPS TOP" } else { "CORRIDA TOP" }
        return @{ Status = "APPROVED"; Reason = "GOLD"; Rule = "P7: Exceção de Ouro ($msg)" }
    }

    # PRIORIDADE 8: Busca Longa (Com tolerância inteligente para Corridas de Alto Valor)
    # Se a corrida paga R$ 35+ com lucro de R$ 25+ e > R$ 50/h, a busca de até 4.5 km é compensada!
    $isSuperCompensada = ($ValorTotal -ge 35.0) -and ($lucroLiq -ge 25.0) -and ($effectiveGanhoHora -ge 50.0) -and ($ganhoKm -ge 2.00)
    $effectiveMaxKmBusca = if ($isSuperCompensada) { [math]::Max($maxKmBusca, 4.5) } else { $maxKmBusca }
    $effectiveMaxTempoBusca = if ($isSuperCompensada) { [math]::Max($maxTempoBuscaMin, 12.0) } else { $maxTempoBuscaMin }

    if ($TempoBuscaMin -gt $effectiveMaxTempoBusca -or $KmBusca -gt $effectiveMaxKmBusca) {
        return @{ Status = "REJECTED"; Reason = "LONG_PICKUP"; Rule = "P8: Busca Longa (${KmBusca}km / ${TempoBuscaMin}m)" }
    }

    # PRIORIDADE 9: Valor Baixo (Mixuruca)
    if ($ValorTotal -lt $minValorCorrida) {
        return @{ Status = "WARNING"; Reason = "LOW_FARE"; Rule = "P9: Valor Baixo (R$ $ValorTotal)" }
    }

    # PRIORIDADE 10: Trânsito Lento
    if ($IsTrafficMode -or $effectiveVelMedia -lt 25.0 -or $hasHiddenTrafficTrap) {
        if ($effectiveGanhoHora -lt $minGanhoHoraTransito) {
            return @{ Status = "REJECTED"; Reason = "TRAFFIC_LOW_RATE"; Rule = "P10: Trânsito Lento ($([math]::Round($effectiveGanhoHora, 0))/h)" }
        } else {
            return @{ Status = "APPROVED"; Reason = "TRAFFIC_APPROVED"; Rule = "P10: Aprovada no Trânsito" }
        }
    }

    # PRIORIDADE 11: Mediana
    if ($ganhoKm -lt $minGanhoKmNormal -or $effectiveGanhoHora -lt $minGanhoHoraNormal) {
        return @{ Status = "WARNING"; Reason = "MEDIAN"; Rule = "P11: Mediana (R$ $([math]::Round($ganhoKm, 2))/km)" }
    }

    # PRIORIDADE 12: Aprovada Comum
    return @{ Status = "APPROVED"; Reason = "NORMAL_APPROVED"; Rule = "P12: Aprovada Normal" }
}

Write-Host "Iniciando Fuzzing de 2.000 cenários de corridas..." -ForegroundColor Cyan

$origens = @(
    "Av. Colombo, Zona 7, Maringá", "Av. Brasil, Centro, Maringá", "Av. Mandacaru, Maringá",
    "Av. Morangueira, Maringá", "Av. Cerro Azul, Zona 2, Maringá", "Av. Londrina, Sarandi",
    "Centro, Sarandi", "Centro, Marialva", "Atacadão Colombo, Maringá", "Assaí Atacadista, Maringá"
)

$destinos = @(
    "Av. Brasil, Centro, Maringá", "Av. Colombo, Zona 7, Maringá", "Av. Londrina, Sarandi",
    "Jardim Independência, Sarandi", "Centro, Marialva", "Distrito de Iguatemi",
    "Rua Guedner, Santa Felicidade", "Jardim Alvorada, Maringá", "Zona 5, Maringá", "Zona 8, Maringá"
)

$stats = @{
    Total = 0
    Approved = 0
    Rejected = 0
    Warning = 0
    GoingHome = 0
    FalseNegativesIdentified = 0
    FalsePositivesIdentified = 0
    Anomalies = @()
}

$rand = New-Object System.Random(42)

for ($i = 1; $i -le 2000; $i++) {
    $stats.Total++

    $origem = $origens[$rand.Next(0, $origens.Length)]
    $destino = $destinos[$rand.Next(0, $destinos.Length)]

    # Sorteio de parâmetros realistas
    $kmBusca = [math]::Round($rand.NextDouble() * 5.0 + 0.3, 1) # 0.3 a 5.3 km
    $tempoBuscaMin = [math]::Round($kmBusca * (2.0 + $rand.NextDouble() * 2.0), 0) # ~2 a 4 min/km
    if ($tempoBuscaMin -lt 1) { $tempoBuscaMin = 1 }

    $kmViagem = [math]::Round($rand.NextDouble() * 22.0 + 1.0, 1) # 1.0 a 23.0 km
    $tempoViagemMin = [math]::Round($kmViagem * (1.5 + $rand.NextDouble() * 2.0), 0)
    if ($tempoViagemMin -lt 3) { $tempoViagemMin = 3 }

    $kmTotal = $kmBusca + $kmViagem
    $tempoTotal = $tempoBuscaMin + $tempoViagemMin

    # Tarifa média da Uber entre R$ 1.30/km a R$ 3.80/km
    $taxaKm = 1.30 + ($rand.NextDouble() * 2.50)
    $valorTotal = [math]::Round($kmTotal * $taxaKm, 2)
    if ($valorTotal -lt 6.50) { $valorTotal = 6.50 }

    # Modificadores raros
    $temParada = ($rand.NextDouble() -lt 0.08) # 8% tem parada
    $dinheiro = ($rand.NextDouble() -lt 0.06)  # 6% dinheiro
    $nota = if ($rand.NextDouble() -lt 0.05) { [math]::Round(4.40 + ($rand.NextDouble() * 0.34), 2) } else { [math]::Round(4.75 + ($rand.NextDouble() * 0.25), 2) }
    $viagens = if ($rand.NextDouble() -lt 0.06) { $rand.Next(1, 8) } else { $rand.Next(15, 600) }

    # Maps: 85% normal (-2 a +2 min), 10% trânsito (+4 a +18 min), 5% livre (-4 a -8 min)
    $mapsRoll = $rand.NextDouble()
    $mapsDiff = 0.0
    if ($mapsRoll -lt 0.10) {
        $mapsDiff = [math]::Round(4.0 + ($rand.NextDouble() * 14.0), 0) # Trânsito
    } elseif ($mapsRoll -lt 0.15) {
        $mapsDiff = - [math]::Round(4.0 + ($rand.NextDouble() * 4.0), 0) # Rápido
    }

    $res = Evaluate-RideSimulator `
        -ValorTotal $valorTotal `
        -TempoBuscaMin $tempoBuscaMin `
        -KmBusca $kmBusca `
        -EnderecoBusca $origem `
        -TempoViagemMin $tempoViagemMin `
        -KmViagem $kmViagem `
        -EnderecoDestino $destino `
        -TemParada $temParada `
        -NotaPassageiro $nota `
        -ViagensPassageiro $viagens `
        -Dinheiro $dinheiro `
        -AppleMapsExtraMinutes $mapsDiff

    switch ($res.Status) {
        "APPROVED" { $stats.Approved++ }
        "REJECTED" { $stats.Rejected++ }
        "WARNING"  { $stats.Warning++ }
        "GOING_HOME" { $stats.GoingHome++ }
    }

    # ============================================================
    # INVESTIGAÇÃO DE DISCREPÂNCIAS (ONDE O SISTEMA PODE "FALHAR")
    # ============================================================
    $ganhoKm = $valorTotal / $kmTotal
    $ganhoHora = $valorTotal / (($tempoTotal + $mapsDiff) / 60.0)
    $isDanger = ($destino.Contains("Guedner") -or $destino.Contains("Santa Felicidade") -or $origem.Contains("Guedner"))
    $isMarket = ($origem.Contains("Atacadão") -or $origem.Contains("Assaí"))
    $isDeadhead = ($destino.Contains("Marialva") -or $destino.Contains("Iguatemi")) -and (-not $origem.Contains("Marialva"))
    
    # Pergunta 1: A corrida era EXCELENTE FINANCEIRAMENTE, sem risco nenhum, e foi rejeitada? (Falso Negativo)
    $eraFinanceiramenteExcelente = ($ganhoKm -ge 2.20) -and ($ganhoHora -ge 55.0) -and ($valorTotal -ge 12.0)
    $tinhaProblemaReal = $isDanger -or $temParada -or $dinheiro -or ($nota -lt 4.75) -or ($mapsDiff -ge 4.0 -and $ganhoHora -lt 40.0) -or $isDeadhead
    
    if ($eraFinanceiramenteExcelente -and -not $tinhaProblemaReal) {
        if ($res.Status -eq "REJECTED") {
            # Por que foi rejeitada? Se foi por Busca Longa, avaliar se a busca foi só um pouquinho acima!
            $stats.FalseNegativesIdentified++
            if ($stats.Anomalies.Count -lt 10) {
                $stats.Anomalies += [PSCustomObject]@{
                    Tipo = "FALSO NEGATIVO (CORRIDA BOA REJEITADA)"
                    Valor = "R$ $valorTotal ($([math]::Round($ganhoKm, 2))/km, $([math]::Round($ganhoHora, 0))/h)"
                    Busca = "${kmBusca} km (${tempoBuscaMin} min)"
                    Viagem = "${kmViagem} km (${tempoViagemMin} min)"
                    Origem = $origem
                    Destino = $destino
                    RegraBarrada = $res.Rule
                    MotivoCritica = if ($kmBusca -gt 2.2 -and $kmBusca -le 2.8) { "Busca limítrofe (2.3 a 2.8 km) descartou corrida de alto ganho!" } else { "Rejeição sob investigação" }
                }
            }
        }
    }

    # Pergunta 2: A corrida era uma CILADA FINANCEIRA e foi aprovada? (Falso Positivo)
    $eraCiladaFinanceira = ($ganhoKm -lt 1.50) -or ($ganhoHora -lt 32.0)
    if ($eraCiladaFinanceira -and $res.Status -eq "APPROVED") {
        $stats.FalsePositivesIdentified++
        if ($stats.Anomalies.Count -lt 10) {
            $stats.Anomalies += [PSCustomObject]@{
                Tipo = "FALSO POSITIVO (CILADA APROVADA)"
                Valor = "R$ $valorTotal ($([math]::Round($ganhoKm, 2))/km, $([math]::Round($ganhoHora, 0))/h)"
                Origem = $origem
                Destino = $destino
                RegraAprovada = $res.Rule
                MotivoCritica = "Ganho financeiro insuficiente mas passou pelo filtro!"
            }
        }
    }
}

Write-Host "==================================================================" -ForegroundColor Green
Write-Host "           RELATÓRIO DO TESTE DE ESTRESSE (2.000 CORRIDAS)        " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " • Total de Corridas Testadas : $($stats.Total)"
Write-Host " • Aprovadas (Verde / Filé)   : $($stats.Approved) ($([math]::Round(($stats.Approved / $stats.Total) * 100, 1))%)"
Write-Host " • Ciladas / Rejeitadas (Verm): $($stats.Rejected) ($([math]::Round(($stats.Rejected / $stats.Total) * 100, 1))%)"
Write-Host " • Alertas (Amarelo)          : $($stats.Warning) ($([math]::Round(($stats.Warning / $stats.Total) * 100, 1))%)"
Write-Host " • Retornos a Maringá (Azul)  : $($stats.GoingHome) ($([math]::Round(($stats.GoingHome / $stats.Total) * 100, 1))%)"
Write-Host "------------------------------------------------------------------"
Write-Host " • Falsos Negativos (Corridas Boas Perdidas) : $($stats.FalseNegativesIdentified)" -ForegroundColor Yellow
Write-Host " • Falsos Positivos (Ciladas que Passaram)   : $($stats.FalsePositivesIdentified)" -ForegroundColor Green

if ($stats.Anomalies.Count -gt 0) {
    Write-Host "`nCASOS DE ANÁLISE E PONTOS DE ATENÇÃO ENCONTRADOS:" -ForegroundColor Cyan
    foreach ($a in $stats.Anomalies) {
        Write-Host " -> $($a.Tipo)" -ForegroundColor Yellow
        Write-Host "    Valor: $($a.Valor) | Rota: $($a.Origem) -> $($a.Destino)"
        Write-Host "    Regra: $($a.RegraBarrada)$($a.RegraAprovada)"
        Write-Host "    Diagnóstico: $($a.MotivoCritica)`n" -ForegroundColor Gray
    }
}


# Análise Detalhada dos 19 Casos
Write-Host "`nDETALHAMENTO TÉCNICO DOS 19 CASOS DE FALSOS NEGATIVOS:" -ForegroundColor Cyan
$motivoStats = @{}
foreach ($a in $stats.Anomalies) {
    Write-Host "• $($a.RegraBarrada) | $($a.Valor) | Busca: $($a.Busca) | Viagem: $($a.Viagem)"
}
