# ==============================================================================
# os-parameter/OsParam-Rollback.ps1
# OsParam-Apply.ps1이 적용 전에 백업해둔 원래 레지스트리 값으로 복원한다.
# 원래 값이 없던 항목(__NOTSET__)은 값을 삭제해 "없던 상태"로 되돌린다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\OsParam-Rollback.ps1 [-Yes]
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

Log-Warn "=== OS 파라미터 롤백 시작: $($script:HostnameShort) ==="

function ConvertTo-PsRegPath {
    param([string]$KeyPath)
    return ($KeyPath `
        -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' `
        -replace '^HKEY_CURRENT_USER', 'HKCU:' `
        -replace '^HKEY_CLASSES_ROOT', 'HKCR:' `
        -replace '^HKEY_USERS', 'HKU:' `
        -replace '^HKEY_CURRENT_CONFIG', 'HKCC:')
}

$BackupRecords = Get-ManifestRecords -ManifestName "original_registry_values.txt"
if ($BackupRecords.Count -eq 0) {
    Log-Warn "생성 기록(manifest)이 없습니다. OsParam-Apply.ps1을 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
}

Log-Warn "아래 레지스트리 값을 적용 이전 상태로 되돌립니다:"
foreach ($rec in $BackupRecords) {
    $parts = $rec -split '\|', 3
    Log-Warn "  - $($parts[0])\$($parts[1]) -> $($parts[2])"
}
Confirm-OrExit "정말로 진행하시겠습니까?"

foreach ($rec in $BackupRecords) {
    $parts = $rec -split '\|', 3
    if ($parts.Count -lt 3) { continue }
    $keyPath, $valueName, $origValue = $parts
    $psPath = ConvertTo-PsRegPath -KeyPath $keyPath

    if (-not (Test-Path $psPath)) {
        Log-Warn "키가 존재하지 않습니다: $psPath. 건너뜁니다."
        continue
    }

    try {
        if ($origValue -eq "__NOTSET__") {
            Remove-ItemProperty -Path $psPath -Name $valueName -ErrorAction SilentlyContinue
            Log-Success "복원 완료(값 삭제): $keyPath\$valueName"
        } else {
            Set-ItemProperty -Path $psPath -Name $valueName -Value $origValue -ErrorAction Stop
            Log-Success "복원 완료: $keyPath\$valueName = $origValue"
        }
    } catch {
        Log-Error "복원 실패: $keyPath\$valueName ($($_.Exception.Message))"
    }
}

Remove-Manifest -ManifestName "original_registry_values.txt"

Log-Warn "=== OS 파라미터 롤백 완료: $($script:HostnameShort) ==="
