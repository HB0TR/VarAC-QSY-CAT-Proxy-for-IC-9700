# Offline checks for the optional 10 Hz CAT transport. Never opens a COM port.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\VarAC_QSY-CAT_Proxy_IC-9700_HB0TR.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw
$start = $text.IndexOf("`$source = @'")
if ($start -lt 0) { throw 'Embedded C# source was not found.' }
$bodyStart = $text.IndexOf("`n", $start) + 1
$end = $text.IndexOf("`n'@", $bodyStart)
if ($bodyStart -le 0 -or $end -lt 0) { throw 'Embedded C# source markers are incomplete.' }
$csharp = $text.Substring($bodyStart, $end - $bodyStart)
Add-Type -TypeDefinition $csharp -Language CSharp -ReferencedAssemblies 'System.dll'

function Test-Map($proxy, [string]$methodName, [long]$inputValue, [bool]$expectedOk, [long]$expectedValue) {
    $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
    $method = $proxy.GetType().GetMethod($methodName, $flags)
    if ($null -eq $method) { throw "Missing method: $methodName" }
    $parameters = [object[]]::new(2)
    $parameters[0] = $inputValue
    $parameters[1] = [long]-1
    $ok = [bool]$method.Invoke($proxy, $parameters)
    if ($ok -ne $expectedOk -or ($ok -and [long]$parameters[1] -ne $expectedValue)) {
        throw "$methodName($inputValue): got $ok / $($parameters[1]), expected $expectedOk / $expectedValue"
    }
}

$common = @('127.0.0.1', 9701, '127.0.0.1', 4532, 'COM1', 115200, [byte]0xA2,
            [long]289500000, [long]433000000, [long]434000000, [long]144000000, [long]146000000,
            $false, [long]433595000, [long]144095000, $true)
foreach ($rfMode in @($true, $false)) {
    $constructorArguments = $common + @($rfMode, [long]10056000000, 'offline-test.log')
    $proxy = New-Object -TypeName QO100CatProxyV504.Proxy -ArgumentList $constructorArguments
    try {
        if ($rfMode) {
            Test-Map $proxy 'TryMapVaracFrequency' 1048959500 $true 433595000
            Test-Map $proxy 'TryMapVaracFrequency' 1048959755 $true 433597550
            Test-Map $proxy 'TryMapVaracFrequency' 1048959245 $true 433592450
            Test-Map $proxy 'TryMapVaracFrequency' 433595000 $false -1
            Test-Map $proxy 'TryMapVaracFrequency' 1048000000 $false -1
            Test-Map $proxy 'TryMapRxToVarac' 433595000 $true 1048959500
            Test-Map $proxy 'TryMapRxToVarac' 433595001 $false -1
            Test-Map $proxy 'TryMapRxToVarac' 435000000 $false -1
        } else {
            Test-Map $proxy 'TryMapVaracFrequency' 433595000 $true 433595000
            Test-Map $proxy 'TryMapRxToVarac' 433595000 $true 433595000
        }
    } finally {
        $proxy.Dispose()
    }
}
Write-Host 'Offline RF/10-Hz CAT mapping OK; no radio port opened.'
