# Runner de Testes Automatizados no Terminal (Maringá • Sarandi • Marialva + Apple Maps + IA Local)
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
    [double]$mapsMinutes = 0.0
) {
    $dangerZones = @("Vila Pedreira", "Zona de Risco")
    $deadheadZones = @("Marialva", "Iguatemi", "Floriano", "Rural") # Sarandi NÃO entra aqui!
    $markets = @("Atacadao", "Atacadão", "Assai", "Assaí", "Muffato", "Condor", "Carrefour", "Supermercado")
    $homeZones = @("Maringa", "Maringá", "Centro", "Zona 7", "Zona 1")

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

    # Excecao de Ouro (so dispara se NAO for embarque em mercado e NAO for conta nova)
    if (($null -eq $matchedMarket) -and (-not $isNewAccount) -and $effectiveGanhoHora -ge 60.0 -and $ride.GanhoKm -ge 2.20 -and $ride.ValorTotal -ge 7.50) {
        $prefix = if ($null -ne $destDeadhead) { "$($destDeadhead.ToUpper()) TOP" } elseif ($diffMaps -le -4.0) { "MAPS TOP" } else { "CORRIDA TOP" }
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
    foreach ($mk in $markets) {
        if ($ride.EndBusca -imatch [regex]::Escape($mk)) {
            return [PSCustomObject]@{ Status = "WARNING"; Message = "EMBARQUE: $($mk.ToUpper())"; LucroLiq = $lucroLiq }
        }
    }
    if ($null -ne $ride.Viagens -and $ride.Viagens -lt 15) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = "CONTA NOVA ($($ride.Viagens) VIAGENS)"; LucroLiq = $lucroLiq }
    }
    if ($ride.GanhoKm -lt 1.65 -or $effectiveGanhoHora -lt 30.0) {
        return [PSCustomObject]@{ Status = "WARNING"; Message = ('MEDIANA: R${0:N2}/km' -f $ride.GanhoKm); LucroLiq = $lucroLiq }
    }
    return [PSCustomObject]@{ Status = "APPROVED"; Message = ('R$ {0:N2}/km | R$ {1:N2}/h' -f $ride.GanhoKm, $effectiveGanhoHora); LucroLiq = $lucroLiq }
}

$tests = @(
    @{
        Name = "1. Maringa -> Maringa (Tiro Curto Z7 -> Centro: R$ 12,91)"
        OCR = "R$ 12,91`n4,97 (254) Verificado`n2 min (0.4 km) Av. Maringa, Zona 7`n9 minutos (3.3 km) Av. Brasil, Centro"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "CORRIDA TOP"
    },
    @{
        Name = "2. Maringa -> Sarandi (Boa R$ 20,35 p/ 11 km -> NAO cobra volta vazia pois toca em Sarandi!)"
        OCR = "R$ 20,35`n4,94 (190) Verificado`n2 min (0.8 km) Av. Colombo, Zona 7`n16 minutos (10.2 km) Av. Londrina, Sarandi"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "R$ 1,85/km"
    },
    @{
        Name = "3. Sarandi -> Maringa (Retorno pago p/ Base Maringa: R$ 16,50 p/ 11 km)"
        OCR = "R$ 16,50`n4,92 (140) Verificado`n2 min (0.7 km) Av. Maringa, Sarandi`n16 minutos (10.3 km) Av. Brasil, Zona 1, Maringa"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "GOING_HOME"; ExpectedSub = "VOLTA P/ MARINGA"
    },
    @{
        Name = "4. Maringa -> Marialva Comum (R$ 26,00 p/ 18 km -> REPROVADA pois cobra a volta vazia!)"
        OCR = "R$ 26,00`n4,95 (310) Verificado`n3 min (1.0 km) Av. Brasil, Centro`n21 minutos (17.0 km) Centro, Marialva"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "REJECTED"; ExpectedSub = "VOLTA VAZIA (MARIALVA)"
    },
    @{
        Name = "5. Maringa -> Marialva VALOR BOM DE FATO (R$ 42,00 p/ 18 km -> APROVADA mesmo descontando volta!)"
        OCR = "R$ 42,00`n4,98 (420) Verificado`n3 min (1.0 km) Av. Brasil, Centro`n21 minutos (17.0 km) Centro, Marialva"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "APPROVED"; ExpectedSub = "MARIALVA TOP"
    },
    @{
        Name = "6. Alerta de Embarque em Supermercado / Atacadao"
        OCR = "R$ 10,50`n4,91 (110) Verificado`n2 min (0.6 km) Atacadao, Av. Colombo`n9 minutos (3.8 km) Jardim Alvorada"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "WARNING"; ExpectedSub = "EMBARQUE: ATACADAO"
    },
    @{
        Name = "7. Alerta de Passageiro Conta Nova (Nota 5,00 mas apenas 4 viagens)"
        OCR = "R$ 12,00`n5,00 (4)`n2 min (0.5 km) Zona 5`n9 minutos (4.0 km) Jardim America"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "WARNING"; ExpectedSub = "CONTA NOVA (4 VIAGENS)"
    },
    @{
        Name = "8. Busca Longa por KM (2.8 km de busca em 4 min -> REPROVADA pela trava de 2.2 km)"
        OCR = "R$ 9,50`n4,95 (180) Verificado`n4 min (2.8 km) Av. Colombo`n6 minutos (2.2 km) Zona 7"
        Traffic = $false; Home = $false; BlockCash = $false; MapsMin = 0.0
        ExpectedStatus = "REJECTED"; ExpectedSub = "BUSCA LONGA"
    }
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  SUITE DE TESTES CALIBRADA: MARINGA • SARANDI • MARIALVA" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$passed = 0; $failed = 0
foreach ($t in $tests) {
    $parsed = Parse-RideOCR $t.OCR
    $verdict = Evaluate-Ride $parsed -traffic $t.Traffic -goingHome $t.Home -blockCash $t.BlockCash -mapsMinutes $t.MapsMin
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
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ("  RESULTADO FINAL: {0} APROVADOS | {1} FALHAS" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "==================================================================" -ForegroundColor Cyan
if ($failed -gt 0) { exit 1 }
