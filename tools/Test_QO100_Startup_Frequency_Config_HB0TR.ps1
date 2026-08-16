# QO-100 startup frequency configuration test
# Reads proxy_config.ini and shows the derived IC-9700 SAT IFs.
# NO COM port, NO CI-V, NO PTT, NO radio changes.

$IniPath = Join-Path $PSScriptRoot "proxy_config.ini"

function Read-IniSimple {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "INI nicht gefunden: $Path"
    }

    $cfg = @{}

    foreach ($line in Get-Content -LiteralPath $Path) {
        $s = $line.Trim()
        if ($s.Length -eq 0 -or $s.StartsWith("#") -or $s.StartsWith(";") -or $s.StartsWith("[")) {
            continue
        }

        $p = $s.IndexOf("=")
        if ($p -lt 1) { continue }

        $key = $s.Substring(0,$p).Trim()
        $val = $s.Substring($p+1).Trim()
        $cfg[$key] = $val
    }

    return $cfg
}

function Need-Int64 {
    param($Cfg,[string]$Key)

    if (-not $Cfg.ContainsKey($Key)) {
        throw "Fehlt in INI: $Key"
    }

    [Int64]$v = 0
    if (-not [Int64]::TryParse($Cfg[$Key],[ref]$v)) {
        throw "Ungueltiger Integer-Hz-Wert fuer $Key : $($Cfg[$Key])"
    }

    return $v
}

try {
    $cfg = Read-IniSimple -Path $IniPath

    $enabled = ($cfg["STARTUP_SET_FREQUENCIES"] -ne "0")
    $dlRfHz = Need-Int64 -Cfg $cfg -Key "QO100_DL_RF_HZ"
    $loHz = Need-Int64 -Cfg $cfg -Key "RX_CONVERTER_LO_HZ"
    $deltaHz = Need-Int64 -Cfg $cfg -Key "RX_TX_DELTA_HZ"

    [Int64]$rxIfHz = $dlRfHz - $loHz
    [Int64]$txIfHz = $rxIfHz - $deltaHz

    Write-Host ""
    Write-Host "QO-100 STARTFREQUENZ-KONFIGURATION" -ForegroundColor Cyan
    Write-Host "---------------------------------"
    Write-Host ("STARTUP_SET_FREQUENCIES = {0}" -f $(if ($enabled) {"1 / ON"} else {"0 / OFF"}))
    Write-Host ""
    Write-Host ("QO-100 Downlink RF = {0} Hz = {1:F6} MHz" -f $dlRfHz,($dlRfHz/1000000.0))
    Write-Host ("RX Converter LO     = {0} Hz = {1:F6} MHz" -f $loHz,($loHz/1000000.0))
    Write-Host ("RX/TX IF Delta      = {0} Hz = {1:F6} MHz" -f $deltaHz,($deltaHz/1000000.0))
    Write-Host ""
    Write-Host ("D0 / RX IF          = {0} Hz = {1:F6} MHz" -f $rxIfHz,($rxIfHz/1000000.0)) -ForegroundColor Yellow
    Write-Host ("D1 / TX IF          = {0} Hz = {1:F6} MHz" -f $txIfHz,($txIfHz/1000000.0)) -ForegroundColor Yellow
    Write-Host ""

    $rxOk = ($rxIfHz -ge 433000000 -and $rxIfHz -le 434000000)
    $txOk = ($txIfHz -ge 144000000 -and $txIfHz -le 146000000)

    if ($rxOk -and $txOk) {
        Write-Host "ERGEBNIS: IF-Werte liegen in den erwarteten Sicherheitsfenstern." -ForegroundColor Green
    }
    else {
        Write-Host "ERGEBNIS: STOP - mindestens ein IF-Wert liegt ausserhalb des Sicherheitsfensters." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Dieses Skript veraendert nichts am Funkgeraet."
}
catch {
    Write-Host ""
    Write-Host ("FEHLER: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
