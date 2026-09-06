# ==============================================================================
# os-parameter/OsParam-Verify.ps1
# 호스트에 지정된 프로파일의 레지스트리 값이 실제로 적용됐는지 검증한다.
# 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
param()

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

Load-HostEnv

Log-Info "=== OS 파라미터 검증 시작: $($script:HostnameShort) ==="

if ([string]::IsNullOrEmpty($HostOsParamProfile)) {
    Log-Error "HostOsParamProfile이 정의되어 있지 않습니다."
    exit 1
}

$ProfileDir = Join-Path $OsParamProfileDir $HostOsParamProfile
$RegFile = Join-Path $ProfileDir "registry.reg"

function ConvertTo-PsRegPath {
    param([string]$KeyPath)
    return ($KeyPath `
        -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' `
        -replace '^HKEY_CURRENT_USER', 'HKCU:' `
        -replace '^HKEY_CLASSES_ROOT', 'HKCR:' `
        -replace '^HKEY_USERS', 'HKU:' `
        -replace '^HKEY_CURRENT_CONFIG', 'HKCC:')
}

function Get-RegFileEntries {
    param([string]$Path)
    $entries = New-Object System.Collections.Generic.List[PSCustomObject]
    $currentKey = $null
    foreach ($rawLine in Get-Content -Path $Path) {
        $line = $rawLine.Trim()
        if ($line -eq "" -or $line.StartsWith(";") -or $line -like "Windows Registry Editor*") { continue }
        if ($line -match '^\[(.+)\]$') { $currentKey = $matches[1]; continue }
        if ($null -eq $currentKey) { continue }

        if ($line -match '^"([^"]+)"=dword:([0-9a-fA-F]+)$') {
            $entries.Add([PSCustomObject]@{ KeyPath = $currentKey; ValueName = $matches[1]; Type = "DWord"; Data = [Convert]::ToInt32($matches[2], 16) })
        }
        elseif ($line -match '^"([^"]+)"="(.*)"$') {
            $entries.Add([PSCustomObject]@{ KeyPath = $currentKey; ValueName = $matches[1]; Type = "String"; Data = $matches[2] })
        }
    }
    return $entries
}

if (-not (Test-Path $RegFile)) {
    Log-Error "프로파일 파일이 없습니다: $RegFile"
    exit 1
}

$script:PassCount = 0
$script:FailCount = 0
function Check {
    param([string]$Description, [bool]$Ok)
    if ($Ok) { Log-Success "[PASS] $Description"; $script:PassCount++ }
    else { Log-Error "[FAIL] $Description"; $script:FailCount++ }
}

$Entries = Get-RegFileEntries -Path $RegFile
foreach ($e in $Entries) {
    $psPath = ConvertTo-PsRegPath -KeyPath $e.KeyPath
    $actual = $null
    if (Test-Path $psPath) {
        $prop = Get-ItemProperty -Path $psPath -Name $e.ValueName -ErrorAction SilentlyContinue
        if ($null -ne $prop) { $actual = $prop.($e.ValueName) }
    }
    Check "$($e.KeyPath)\$($e.ValueName) = $($e.Data) (실제: $actual)" ("$actual" -eq "$($e.Data)")
}

Log-Info "=================================================="
Log-Info " 검증 결과: PASS $($script:PassCount) / FAIL $($script:FailCount)"
Log-Info "=================================================="

exit ([int]($script:FailCount -gt 0))
