# Suíte Completa de Testes + Simulação de Probabilidade (Maringá • Sarandi • Marialva + Meta 250+)
$ErrorActionPreference = "Stop"

function Parse-RideOCR([string]$rawText) {
    $priceMatch = [regex]::Match($rawText, 'R[\$S]\s*[\r\n]*\s*(\d+[.,]\d{2})(?!\s*\/?\s*(?:km|h))', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $priceMatch.Success) { return $null }
    $valorTotal = [double]($priceMatch.Groups[1].Value -replace ',', '.')

    $legPattern = '(?:(\d+)\s*h(?:oras?)?\s*)?(\d+)\s*(?:min(?:utos?)?\.?)\s*[\r\n]*\s*\(\s*(\d+(?:[.,]\d+)?)\s*km\s*\)\s*[\r\n]*\s*([^\r\n]+)'
    $legMatches = [regex]::Matches($rawText, $legPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($legMatches.Count -lt 2) { return $null }

    $legs = @()
    foreach ($m in $legMatches) {
        $hours = if ($m.Groups[1].Success) { [double]$m.Groups[1].Value } else { 0.0 }
        $mins  = [double]($m.Groups[2].Value -replace ',', '.')
        $kms   = [double]($m.Groups[3].Value -replace ',', '.')
        $addr  = $m.Groups[4].Value.Trim()
        $legs += [PSCustomObject]@{ Minutes = ($hours * 60.0) + $mins; Kilometers = $kms; Address = $addr }
    }

    $temParada = $rawText -imatch '\bparadas?\b'
    $pagamentoDinheiro = $rawText -imatch '\b(?:dinheiro|esp[eé]cie|troco)\b'
    $verificado = $rawText -imatch '\bverificado\b'

    $nota = $null
    $viagens = $null
    foreach ($line in ($rawText -split '\r?\n')) {
        if ($line -imatch 'R\$|RS|/KM') { continue }
        $rm = [regex]::Match($line, '\b([34][.,]\d{2}|5[.,]00)\b(?:\s*\(\s*(\d+)\s*\))?')
        if ($rm.Success) {
            $nota = [double]($rm.Groups[1].Value -replace ',', '.')
            if ($rm.Groups[2].Success) { $viagens = [int]$rm.Groups[2].Value }
            break
        }
    }

    $tempoTotal = $legs[0].Minutes + $legs[1].Minutes
    $kmTotal    = $legs[0].Kilometers + $legs[1].Kilometers
    $ganhoHora  = if ($tempoTotal -gt 0) { $valorTotal / ($tempoTotal / 60.0) } else { 0.0 }
    $ganhoKm    = if ($kmTotal -gt 0) { $valorTotal / $kmTotal } else { 0.0 }
    $velMedia   = if ($tempoTotal -gt 0) { $kmTotal / ($tempoTotal / 60.0) } else { 0.0 }

    return [PSCustomObject]@{
        ValorTotal  = $valorTotal
        TempoBusca  = $legs[0].Minutes
        KmBusca     = $legs[0].Kilometers
        EndBusca    = $legs[0].Address
        TempoViagem = $legs[1].Minutes
        KmViagem    = $legs[1].Kilometers
        EndDestino  = $legs[1].Address
        TempoTotal  = $tempoTotal
        KmTotal     = $kmTotal
        GanhoHora   = $ganhoHora
        GanhoKm     = $ganhoKm
        VelMedia    = $velMedia
        TemParada   = $temParada
        Dinheiro    = $pagamentoDinheiro
        Nota        = $nota
        Viagens     = $viagens
        Verificado  = $verificado
    }
}

function Evaluate-Ride(
    $ride,
    [bool]$traffic = $false,
    [bool]$goingHome = $false,
    [bool]$blockCash = $false,
    [double]$mapsMinutes = 0.0,
    [double]$currentDailyNet = 0.0
) {
    $dangerZones = @("Vila Pedreira", "Zona de Risco")
    $deadheadZones = @("Marialva", "Iguatemi", "Floriano", "Rural") # Sarandi NÃO entra aqui!
    $markets = @("Atacadao", "Atacadão", "Assai", "Assaí", "Muffato", "Condor", "Carrefour", "Supermercado")

    $destDeadhead = $null
    foreach ($b in $deadheadZones) {
        if ($ride.EndDestino -imatch [regex]::Escape($b)) { $destDeadhead = $b; break }
    }
    $pickupDeadhead = $false
    foreach ($b in $deadheadZones) {
        if ($ride.EndBusca -imatch [regex]::Escape($b)) { $pickupDeadhead = $true; break }
    }
    $isGoingToDeadhead = ($null -ne $destDeadhead) -and (-not $pickupDeadhead)

    $extraReturnKm  = if ($isGoingToDeadhead) { $ride.KmViagem * 0.60 } else { 0.0 }
    $extraReturnMin = if ($isGoingToDeadhead) { $ride.TempoViagem * 0.55 } else { 0.0 }

    $effectiveMinutes   = if ($mapsMinutes -gt 0) { $mapsMinutes } else { $ride.TempoTotal }
    $effectiveGanhoHora = $ride.ValorTotal / ($effectiveMinutes / 60.0)
    $effectiveVelMedia  = $ride.KmTotal / ($effectiveMinutes / 60.0)
    $diffMaps           = if ($mapsMinutes -gt 0) { $mapsMinutes - $ride.TempoTotal } else { 0.0 }

    $lucroLiq = [math]::Max(0.0, $ride.ValorTotal - (($ride.KmTotal + $extraReturnKm) * 0.65))
    $ganhoHoraLiqComVolta = $lucroLiq / (($effectiveMinutes + 1.5 + $extraReturnMin) / 60.0)
    $willHit250 = ($currentDailyNet -gt 0.0) -and ($currentDailyNet -lt 250.0) -and (($currentDailyNet + $lucroLiq) -ge 250.0)

    $combinedAddr = "$($ride.EndBusca) $($ride.EndDestino)"
    foreach ($d in $dangerZones) {
        if ($combinedAddr -imatch [regex]::Escape($d)) {
            return [PSCustomObject]@{ Status = "REJECTED"; Message = "PERIGO: $($d.ToUpper())"; LucroLiq = $lucroLiq }
        }
    }
    if ($blockCash -and $ride.Dinheiro) {
        return [PSCustomObject]@{ Status = "REJECTED"; Message = "CILADA: PGTO EM DINHEIRO"; LucroLiq = $lucroLiq }
    }
    if ($ride.TemParada) {
        return [PSCustomObject]@{ Status = "REJECTED"; Message = "CILADA: TEM PARADA"; LucroLiq = $lucroLiq }
    }
    if ($null -ne $ride.Nota -and $ride.Nota -lt 4.75) {
        return [PSCustomObject]@{ Status = "REJECTED"; Message = ("CILADA: NOTA BAIXA ({0:N2})" -f $ride.Nota); LucroLiq = $lucroLiq }
    }
    # Regra Marialva / Iguatemi / Floriano (ANTES da Excecao de Ouro!)
    if ($isGoingToDeadhead) {
        if ($ride.GanhoKm -lt 2.20 -and $ganhoHoraLiqComVolta -lt 30.0) {
            return [PSCustomObject]@{ Status = "REJECTED"; Message = "CILADA: VOLTA VAZIA ($($destDeadhead.ToUpper()))"; LucroLiq = $lucroLiq }
        }
    }
    # Retorno de Sarandi / Marialva -> Maringá
    $isReturningToMga = ($ride.EndBusca -imatch 'Sarandi|Marialva') -and ($ride.EndDestino -imatch 'Maringa|Maringá|Centro|Zona 7|Zona 1')
    if (($goingHome -or $isReturningToMga) -and $ride.GanhoKm -ge 1.40 -and $ride.TempoBusca -le 5.0) {
        return [PSCustomObject]@{ Status = "GOING_HOME"; Message = ('VOLTA P/ MARINGA: R${0:N2}/km' -f $ride.GanhoKm); LucroLiq = $lucroLiq }
    }

    # Verificar se eh Embarque em Mercado ou Conta Nova (< 15 viagens)
    $matchedMarket = $null
    foreach ($mk in $markets) {
        if ($ride.EndBusca -imatch [regex]::Escape($mk)) { $matchedMarket = $mk; break }
    }
    $isNewAccount = ($null -ne $ride.Viagens) -and ($ride.Viagens -lt 15)

    # Excecao de Ouro
    if (($null -eq $matchedMarket) -and (-not $isNewAccount) -and $effectiveGanhoHora -ge 50.0 -and $ride.GanhoKm -ge 2.00 -and $ride.ValorTotal -ge 7.50) {
        $prefix = if ($willHit250) { "BATE OS 250" } elseif ($null -ne $destDeadhead) { "$($destDeadhead.ToUpper()) TOP" } elseif ($diffMaps -le -4.0) { "MAPS TOP" } else { "CORRIDA TOP" }
        return [PSCustomObject]@{ Status = "APPROVED"; Message = ('{0}: R${1:N2}/km' -f $prefix, $ride.GanhoKm); LucroLiq = $lucroLiq }
    }
    # Busca Longa (Minutos > 5 ou KM > 2.2)
    if ($ride.TempoBusca -gt 5.0 -or $ride.KmBusca -gt 2.2) {
        return [PSCustomObject]@{ Status = "REJECTED"; Message = "CILADA: BUSCA LONGA"; LucroLiq = $lucroLiq }
    }
    # Corrida Mixuruca (< R$ 7,50)
    if ($ride.ValorTotal -lt 7.50) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = ('VALOR BAIXO: SO R$ {0:N2}' -f $ride.ValorTotal); LucroLiq = $lucroLiq }
    }
    # Transito
    if ($traffic -or $effectiveVelMedia -lt 25.0 -or $diffMaps -ge 4.0) {
        if ($effectiveGanhoHora -lt 35.0) {
            $prefix = if ($diffMaps -ge 4.0) { "MAPS TRANSITO" } else { "TRANSITO" }
            return [PSCustomObject]@{ Status = "REJECTED"; Message = ('{0}: SO R${1:N2}/h' -f $prefix, $effectiveGanhoHora); LucroLiq = $lucroLiq }
        }
    }
    # Alertas Amarelos: Mercado ou Conta Nova (< 15 viagens)
    if ($null -ne $matchedMarket) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = "EMBARQUE: $($matchedMarket.ToUpper())"; LucroLiq = $lucroLiq }
    }
    if ($isNewAccount) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = "CONTA NOVA ($($ride.Viagens) VIAGENS)"; LucroLiq = $lucroLiq }
    }
    if ($ride.GanhoKm -lt 1.65 -or $effectiveGanhoHora -lt 30.0) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = ('MEDIANA: R${0:N2}/km' -f $ride.GanhoKm); LucroLiq = $lucroLiq }
    }
    $msg = if ($willHit250) { ('BATE OS 250: R${0:N2}/km' -f $ride.GanhoKm) } else { ('R$ {0:N2}/km | R$ {1:N2}/h' -f $ride.GanhoKm, $effectiveGanhoHora) }
    return [PSCustomObject]@{ Status = "APPROVED"; Message = $msg; LucroLiq = $lucroLiq }
}

$tests = @(
    @{
        Name = "1. Maringa -> Maringa (Tiro Curto Z7 -> Centro: R$ 12,91)"
        OCR = "R$ 12,91`n4,97 (254) Verificado`n2 min (0.4 km) Av. Maringa, Zona 7`n9 minutos (3.3 km) Av. Brasil, Centro"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "CORRIDA TOP"
    },
    @{
        Name = "2. Maringa -> Sarandi (Boa R$ 20,35 p/ 11 km -> NAO cobra volta vazia pois toca em Sarandi!)"
        OCR = "R$ 20,35`n4,94 (190) Verificado`n2 min (0.8 km) Av. Colombo, Zona 7`n16 minutos (10.2 km) Av. Londrina, Sarandi"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "R$ 1,85/km"
    },
    @{
        Name = "3. Giro Interno em Sarandi -> Sarandi no Pico (R$ 11,00 p/ 5.2 km em 11 min)"
        OCR = "R$ 11,00`n4,91 (180) Verificado`n2 min (0.6 km) Av. Londrina, Sarandi`n9 minutos (4.6 km) Jardim Independencia, Sarandi"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "CORRIDA TOP"
    },
    @{
        Name = "4. Sarandi -> Maringa (Retorno pago p/ Base Maringa: R$ 16,50 p/ 11 km)"
        OCR = "R$ 16,50`n4,92 (140) Verificado`n2 min (0.7 km) Av. Maringa, Sarandi`n16 minutos (10.3 km) Av. Brasil, Zona 1, Maringa"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "GOING_HOME"; ExpectedSub = "VOLTA P/ MARINGA"
    },
    @{
        Name = "5. Marialva -> Maringa (Retorno pago de Marialva p/ Maringa: R$ 26,00 p/ 18 km)"
        OCR = "R$ 26,00`n4,96 (290) Verificado`n2 min (0.8 km) Centro, Marialva`n20 minutos (17.2 km) Av. Brasil, Centro, Maringa"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "GOING_HOME"; ExpectedSub = "VOLTA P/ MARINGA"
    },
    @{
        Name = "6. Maringa -> Marialva Comum (R$ 26,00 p/ 18 km -> REPROVADA pois cobra a volta vazia!)"
        OCR = "R$ 26,00`n4,95 (310) Verificado`n3 min (1.0 km) Av. Brasil, Centro`n21 minutos (17.0 km) Centro, Marialva"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "REJECTED"; ExpectedSub = "VOLTA VAZIA (MARIALVA)"
    },
    @{
        Name = "7. Maringa -> Marialva VALOR BOM DE FATO (R$ 42,00 p/ 18 km -> APROVADA mesmo descontando volta!)"
        OCR = "R$ 42,00`n4,98 (420) Verificado`n3 min (1.0 km) Av. Brasil, Centro`n21 minutos (17.0 km) Centro, Marialva"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "MARIALVA TOP"
    },
    @{
        Name = "8. Maringa -> Iguatemi Fraca (R$ 22,00 p/ 16 km -> REPROVADA pela Volta Vazia)"
        OCR = "R$ 22,00`n4,90 (120) Verificado`n3 min (1.0 km) Zona 7`n18 minutos (15.0 km) Distrito de Iguatemi"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "REJECTED"; ExpectedSub = "VOLTA VAZIA (IGUATEMI)"
    },
    @{
        Name = "9. Alerta de Embarque em Supermercado / Atacadao"
        OCR = "R$ 10,50`n4,91 (110) Verificado`n2 min (0.6 km) Atacadao, Av. Colombo`n9 minutos (3.8 km) Jardim Alvorada"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "WARNING"; ExpectedSub = "EMBARQUE: ATACADAO"
    },
    @{
        Name = "10. Alerta de Passageiro Conta Nova (Nota 5,00 mas apenas 4 viagens)"
        OCR = "R$ 12,00`n5,00 (4)`n2 min (0.5 km) Zona 5`n9 minutos (4.0 km) Jardim America"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "WARNING"; ExpectedSub = "CONTA NOVA (4 VIAGENS)"
    },
    @{
        Name = "11. Busca Longa por KM (2.8 km de busca em 4 min -> REPROVADA pela trava de 2.2 km)"
        OCR = "R$ 9,50`n4,95 (180) Verificado`n4 min (2.8 km) Av. Colombo`n6 minutos (2.2 km) Zona 7"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 0.0
        ExpectedStatus = "REJECTED"; ExpectedSub = "BUSCA LONGA"
    },
    @{
        Name = "12. Detector de Corrida que Fecha a Meta 250+ (Acumulado R$ 241 + R$ 10,51 = R$ 251,51!)"
        OCR = "R$ 12,91`n4,97 (254) Verificado`n2 min (0.4 km) Av. Maringa, Zona 7`n9 minutos (3.3 km) Av. Brasil, Centro"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0; DailyNet = 241.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "BATE OS 250"
    }
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  PARTE 1: 12 TESTES DETERMINISTICOS (MARINGA • SARANDI • MARIALVA)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$passed = 0; $failed = 0
foreach ($t in $tests) {
    $parsed = Parse-RideOCR $t.OCR
    $verdict = Evaluate-Ride $parsed -traffic $t.Traffic -goingHome $t.Home -blockCash $t.BlockCash -mapsMinutes $t.MapsMin -currentDailyNet $t.DailyNet
    $ok = ($verdict.Status -eq $t.ExpectedStatus) -and ($verdict.Message.Contains($t.ExpectedSub))
    if ($ok) {
        Write-Host ("[PASS] {0}" -f $t.Name) -ForegroundColor Green
        Write-Host ("       -> [{0}] {1} | Bruto: R$ {2:N2} | Liq Real: R$ {3:N2}" -f $verdict.Status, $verdict.Message, $parsed.ValorTotal, $verdict.LucroLiq) -ForegroundColor Gray
        $passed++
    } else {
        Write-Host ("[FAIL] {0} -> Esperado: {1} ({2}), Obtido: {3} ({4})" -f $t.Name, $t.ExpectedStatus, $t.ExpectedSub, $verdict.Status, $verdict.Message) -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Yellow
Write-Host "  PARTE 2: SIMULACAO DE PROBABILIDADE (100 CORRIDAS SORTEADAS)" -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Yellow

$random = New-Object System.Random(2026)
$pool = @(
    @{ Type = "Maringa Curta Top";    Prob = 28; OCR = "R$ 12,50`n4,96 (210) Verificado`n2 min (0.5 km) Zona 7`n8 minutos (3.2 km) Centro, Maringa"; RealMin = 11.5; RealKm = 3.7 },
    @{ Type = "Maringa Normal Boa";   Prob = 22; OCR = "R$ 15,20`n4,93 (180) Verificado`n3 min (0.9 km) Zona 5`n12 minutos (6.8 km) Jardim Alvorada, Maringa"; RealMin = 16.5; RealKm = 7.7 },
    @{ Type = "Maringa -> Sarandi";   Prob = 12; OCR = "R$ 20,35`n4,94 (190) Verificado`n2 min (0.8 km) Av. Colombo`n16 minutos (10.2 km) Av. Londrina, Sarandi"; RealMin = 19.5; RealKm = 11.0 },
    @{ Type = "Sarandi -> Maringa";   Prob = 10; OCR = "R$ 16,80`n4,92 (140) Verificado`n2 min (0.7 km) Centro, Sarandi`n16 minutos (10.3 km) Zona 1, Maringa"; RealMin = 19.5; RealKm = 11.0 },
    @{ Type = "Marialva Cilada";      Prob = 8;  OCR = "R$ 25,50`n4,95 (310) Verificado`n3 min (1.0 km) Av. Brasil`n21 minutos (17.0 km) Centro, Marialva"; RealMin = 36.0; RealKm = 28.2 },
    @{ Type = "Marialva Dinamico";    Prob = 4;  OCR = "R$ 42,00`n4,98 (420) Verificado`n3 min (1.0 km) Av. Brasil`n21 minutos (17.0 km) Centro, Marialva"; RealMin = 36.0; RealKm = 28.2 },
    @{ Type = "Transito Travado";     Prob = 8;  OCR = "R$ 9,20`n4,91 (88) Verificado`n3 min (0.8 km) Av. Morangueira`n17 minutos (3.5 km) Centro"; RealMin = 21.5; RealKm = 4.3 },
    @{ Type = "Busca Longa (>2.2km)"; Prob = 8;  OCR = "R$ 9,80`n4,94 (150) Verificado`n4 min (2.9 km) Contorno Norte`n7 minutos (2.5 km) Zona 7"; RealMin = 12.5; RealKm = 5.4 }
)

$copilotoLucro = 0.0; $copilotoMinutos = 0.0; $copilotoAceitas = 0; $copilotoRecusadas = 0
$corridasAte250 = 0; $horasAte250 = 0.0

for ($i = 1; $i -le 100; $i++) {
    $roll = $random.Next(1, 101)
    $acc = 0; $chosen = $pool[0]
    foreach ($item in $pool) {
        $acc += $item.Prob
        if ($roll -le $acc) { $chosen = $item; break }
    }
    $parsed = Parse-RideOCR $chosen.OCR
    $verdict = Evaluate-Ride $parsed -currentDailyNet $copilotoLucro
    if ($verdict.Status -eq "APPROVED" -or $verdict.Status -eq "GOING_HOME") {
        $copilotoAceitas++
        $copilotoLucro += $verdict.LucroLiq
        $copilotoMinutos += $chosen.RealMin
        if ($corridasAte250 -eq 0 -and $copilotoLucro -ge 250.0) {
            $corridasAte250 = $copilotoAceitas
            $horasAte250 = $copilotoMinutos / 60.0
        }
    } else {
        $copilotoRecusadas++
        $copilotoMinutos += 1.2 # 1.2 min esperando tocar a proxima corrida boa
    }
}

$ganhoHoraLiqCopiloto = $copilotoLucro / ($copilotoMinutos / 60.0)
Write-Host ("  • Ofertas Tocadas no Dia        : 100 chamadas") -ForegroundColor White
Write-Host ("  • Corridas Aprovadas (Filé)     : {0} aceitas | {1} ciladas bloqueadas" -f $copilotoAceitas, $copilotoRecusadas) -ForegroundColor Green
Write-Host ("  • Tempo para Bater a Meta 250+  : {0} corridas (~{1:N1} horas de trabalho)" -f $corridasAte250, $horasAte250) -ForegroundColor Cyan
Write-Host ("  • Lucro Liquido Medio por Hora  : R$ {0:N2}/h LIVRES (ja descontando gasolina e volta)" -f $ganhoHoraLiqCopiloto) -ForegroundColor Green

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Magenta
Write-Host "  PARTE 3: ANTI-GAGUEIRA DA VOZ (FRAMES DO OCR COM O CARD ANIMANDO)" -ForegroundColor Magenta
Write-Host "==================================================================" -ForegroundColor Magenta

# Replica a logica do SpeechManager.triggerAlertIfNeeded (trava por preco + cooldown 12s + fingerprint numerico)
$script:lastFp = ""; $script:lastPrice = -1.0; $script:lastTime = -999.0; $script:lastStatus = "WAITING"; $script:falas = @()
function Invoke-VoiceGate([double]$t, [double]$price, [string]$fp, [string]$status) {
    $samePrice = ($price -gt 0) -and ([math]::Abs($price - $script:lastPrice) -lt 0.05) -and (($t - $script:lastTime) -lt 12.0)
    $sameFp = ($fp -eq $script:lastFp)
    $flip = ($sameFp -or $samePrice) -and ($status -ne $script:lastStatus) -and ($script:lastStatus -ne "WAITING")
    if (($sameFp -or $samePrice) -and -not $flip) { return }
    $script:lastFp = $fp; $script:lastPrice = $price; $script:lastTime = $t; $script:lastStatus = $status
    $script:falas += ("t={0:N1}s R$ {1:N2} [{2}]" -f $t, $price, $status)
}
function Reset-VoiceGate([double]$t) {
    if (($t - $script:lastTime) -gt 6.0) { $script:lastFp = ""; $script:lastPrice = -1.0; $script:lastStatus = "WAITING" }
}
function Get-Fp($p) { return ("{0:N2}_{1:N1}_{2:N0}" -f $p.ValorTotal, $p.KmTotal, $p.TempoTotal) }

# Corrida 1 (R$ 20,35): 10 frames em 3,5s com o OCR lendo endereco/km diferentes enquanto o card sobe
$frames1 = @(
    "R$ 20,35`n4,94 (190) Verificado`n2 min (0.8 km) Av. Colombo, Zona 7`n16 minutos (10.2 km) Av. Londrina, Sarandi",
    "R$ 20,35`n4,94 (190) Verificado`n2 min (0.8 km) Av. Colombo, Zona 7`n16 minutos (10.2 km) Av. Londrlna, Sarandi",
    "R$ 20,35`n4,94 (190)`n2 min (0.8 km) Av Colombo Zona 7`n16 minutos (10,2 km) Av. Londrina, Sarandi",
    "R$ 20,35`n4,94 (190) Verificado`n3 min (0.9 km) Av. Colombo, Zona 7`n16 minutos (10.2 km) Av. Londrina, Sarandi"
)
$t = 0.0
for ($k = 0; $k -lt 10; $k++) {
    $p = Parse-RideOCR $frames1[$k % $frames1.Count]
    $v = Evaluate-Ride $p
    Invoke-VoiceGate $t $p.ValorTotal (Get-Fp $p) $v.Status
    $t += 0.35
}
# Card some por 1 frame (piscada) e volta -> NAO pode repetir
Reset-VoiceGate $t; $t += 0.4
$p = Parse-RideOCR $frames1[0]; $v = Evaluate-Ride $p
Invoke-VoiceGate $t $p.ValorTotal (Get-Fp $p) $v.Status
$falasCorrida1 = $script:falas.Count

# Corrida 2 diferente (R$ 26,00 Marialva) 20s depois -> TEM que falar de novo
$t += 20.0; Reset-VoiceGate $t
$p = Parse-RideOCR "R$ 26,00`n4,95 (310) Verificado`n3 min (1.0 km) Av. Brasil, Centro`n21 minutos (17.0 km) Centro, Marialva"
$v = Evaluate-Ride $p
Invoke-VoiceGate $t $p.ValorTotal (Get-Fp $p) $v.Status

foreach ($f in $script:falas) { Write-Host "       voz -> $f" -ForegroundColor Gray }
if ($falasCorrida1 -eq 1 -and $script:falas.Count -eq 2) {
    Write-Host "[PASS] 13. Voz falou 1x na corrida de R$ 20,35 (11 frames variando) e 1x na nova corrida de Marialva" -ForegroundColor Green
    $passed++
} else {
    Write-Host ("[FAIL] 13. Anti-gagueira: esperado 1 + 1 falas, obtido {0} + {1}" -f $falasCorrida1, ($script:falas.Count - $falasCorrida1)) -ForegroundColor Red
    $failed++
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ("  RESULTADO FINAL: {0} APROVADOS | {1} FALHAS" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "==================================================================" -ForegroundColor Cyan
if ($failed -gt 0) { exit 1 }
