# ==============================================================================
# storage/Storage-Rollback.ps1
# Storage-Gen.ps1이 "실제로 생성한" 드라이브/디스크만 삭제한다 (manifest
# 기반 - HostVolumes를 직접 순회하지 않는다. 이미 존재해서 건드리지 않은
# 드라이브까지 지우는 사고를 막기 위함).
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Storage-Rollback.ps1 [-Yes]
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

Log-Warn "=== 스토리지 롤백 시작: $($script:HostnameShort) ==="

$Created = Get-ManifestRecords -ManifestName "created_volumes.txt"
if ($Created.Count -eq 0) {
    Log-Warn "생성 기록(manifest)이 없습니다. Storage-Gen.ps1을 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
}

Log-Warn "아래 드라이브와 디스크의 모든 데이터를 삭제합니다. 되돌릴 수 없습니다:"
foreach ($rec in $Created) {
    $parts = $rec -split '\|'
    Log-Warn "  - $($parts[0]): (디스크 $($parts[1]))"
}
Confirm-OrExit "정말로 진행하시겠습니까?"

foreach ($rec in $Created) {
    $parts = $rec -split '\|'
    if ($parts.Count -lt 2) { continue }
    $driveLetter = $parts[0]
    $diskNumber = $parts[1]

    try {
        if (Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue) {
            Remove-Partition -DriveLetter $driveLetter -Confirm:$false -ErrorAction Stop
        }
        Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        Log-Success "삭제 완료: $($driveLetter): (디스크 $diskNumber)"
    } catch {
        Log-Error "삭제 실패: $($driveLetter): (디스크 $diskNumber) - $($_.Exception.Message)"
    }
}

Remove-Manifest -ManifestName "created_volumes.txt"

Log-Warn "=== 스토리지 롤백 완료: $($script:HostnameShort) ==="
