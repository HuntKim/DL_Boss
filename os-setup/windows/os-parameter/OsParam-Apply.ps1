# ==============================================================================
# os-parameter/OsParam-Apply.ps1
# 호스트 env($HostOsParamProfile)가 가리키는 프로파일의 registry.reg를
# "reg import"로 그대로 적용한다(네이티브 .reg 형식 - 커스텀 파싱 없이
# 적용됨). 검증/롤백을 위해 dword/string 값만 별도로 추적한다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\OsParam-Apply.ps1 [-Yes]
# ==============================================================================
param(
    [switch]$Yes
)

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

$Global:AssumeYes = $Yes.IsPresent
Require-Admin
Load-HostEnv

Log-Info "=== OS 파라미터 적용 시작: $($script:HostnameShort) ==="

if ([string]::IsNullOrEmpty($HostOsParamProfile)) {
    Log-Error "HostOsParamProfile이 정의되어 있지 않습니다."
    exit 1
}

$ProfileDir = Join-Path $OsParamProfileDir $HostOsParamProfile
$RegFile = Join-Path $ProfileDir "registry.reg"

if (-not (Test-Path $RegFile)) {
    Log-Error "프로파일 파일이 없습니다: $RegFile"
    exit 1
}

# ------------------------------------------------------------------------------
# .reg 파일 파싱 (dword/string 값만 검증/백업 대상으로 다룸 - binary,
# multi-string 등은 reg import로 적용은 되지만 이 스크립트의 확인/복원
# 로직에서는 제외되고 경고만 남긴다)
# ------------------------------------------------------------------------------
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
        else {
            Log-Warn "지원하지 않는 형식이라 검증/백업 대상에서 제외합니다(reg import 적용 자체는 정상 처리됨): $line"
        }
    }
    return $entries
}

$Entries = Get-RegFileEntries -Path $RegFile
Log-Info "적용할 프로파일: $HostOsParamProfile ($($Entries.Count)개 값 추적, $RegFile)"

# ------------------------------------------------------------------------------
# 적용 전 원래 값 백업 (재실행 시 최초 값을 계속 보존)
# ------------------------------------------------------------------------------
$BackupManifest = "original_registry_values.txt"
if ((Get-ManifestRecords -ManifestName $BackupManifest).Count -eq 0) {
    foreach ($e in $Entries) {
        $psPath = ConvertTo-PsRegPath -KeyPath $e.KeyPath
        $existing = $null
        if (Test-Path $psPath) {
            $prop = Get-ItemProperty -Path $psPath -Name $e.ValueName -ErrorAction SilentlyContinue
            if ($null -ne $prop) { $existing = $prop.($e.ValueName) }
        }
        # 원래 값이 아예 없었을 수도 있으므로 __NOTSET__ 으로 구분
        $existingStr = if ($null -eq $existing) { "__NOTSET__" } else { $existing }
        Add-ManifestRecord -ManifestName $BackupManifest -Value "$($e.KeyPath)|$($e.ValueName)|$existingStr"
    }
    Log-Info "적용 전 레지스트리 값 백업 완료 (rollback 시 복원용)"
}

# ------------------------------------------------------------------------------
# reg import로 실제 적용 (네이티브 명령 - 커스텀 로직으로 값을 하나씩
# 설정하지 않음)
# ------------------------------------------------------------------------------
$ImportOutput = & reg.exe import "$RegFile" 2>&1
if ($LASTEXITCODE -eq 0) {
    Log-Success "레지스트리 프로파일 적용 완료: $RegFile"
} else {
    Log-Error "reg import 실패: $ImportOutput"
    exit 1
}

# ------------------------------------------------------------------------------
# 적용 확인 (우리가 추적하는 값들만)
# ------------------------------------------------------------------------------
$ApplyFail = $false
foreach ($e in $Entries) {
    $psPath = ConvertTo-PsRegPath -KeyPath $e.KeyPath
    $actual = $null
    if (Test-Path $psPath) {
        $prop = Get-ItemProperty -Path $psPath -Name $e.ValueName -ErrorAction SilentlyContinue
        if ($null -ne $prop) { $actual = $prop.($e.ValueName) }
    }
    if ("$actual" -eq "$($e.Data)") {
        Log-Success "적용 확인: $($e.KeyPath)\$($e.ValueName) = $($e.Data)"
    } else {
        Log-Error "적용 실패: $($e.KeyPath)\$($e.ValueName) (기대: $($e.Data), 실제: $actual)"
        $ApplyFail = $true
    }
}

if ($ApplyFail) {
    Log-Error "일부 레지스트리 값이 적용되지 않았습니다."
    exit 1
}

Log-Success "=== OS 파라미터 적용 완료: $($script:HostnameShort) (프로파일: $HostOsParamProfile) ==="
