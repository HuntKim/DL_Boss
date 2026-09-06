# ==============================================================================
# account/Account-Rollback.ps1
# Account-Gen.ps1이 "실제로 생성한" 계정/그룹만 삭제한다 (manifest 기반 -
# HostGroups/HostAccounts를 직접 순회하지 않는다. env에는 Administrators
# 같은 내장 그룹도 계정의 소속 그룹으로 참조될 수 있는데, 이를 직접
# 순회하며 지우면 내장 그룹을 건드리는 사고로 이어질 수 있다).
#
# 계정 삭제는 로컬 계정만 제거하며, 사용자 프로필 폴더(C:\Users\<계정>)는
# 별도로 삭제되지 않는다 - 필요 시 수동으로 확인/정리할 것.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Account-Rollback.ps1 [-Yes]
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

Log-Warn "=== 계정/그룹 롤백 시작: $($script:HostnameShort) ==="

$createdAccounts = Get-ManifestRecords -ManifestName "created_accounts.txt"
$createdGroups   = Get-ManifestRecords -ManifestName "created_groups.txt"

if ($createdAccounts.Count -eq 0 -and $createdGroups.Count -eq 0) {
    Log-Warn "생성 기록(manifest)이 없습니다. Account-Gen.ps1을 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
}

if ($createdAccounts.Count -gt 0) { Log-Warn "삭제 대상 계정 (Account-Gen.ps1이 생성한 것만): $($createdAccounts -join ', ')" }
if ($createdGroups.Count -gt 0)   { Log-Warn "삭제 대상 그룹 (Account-Gen.ps1이 생성한 것만): $($createdGroups -join ', ')" }
Log-Warn "사용자 프로필 폴더(C:\Users\<계정>)는 자동으로 삭제되지 않습니다."
Confirm-OrExit "정말로 위 계정/그룹을 삭제하시겠습니까?"

foreach ($uname in $createdAccounts) {
    if (Get-LocalUser -Name $uname -ErrorAction SilentlyContinue) {
        try {
            Remove-LocalUser -Name $uname -ErrorAction Stop
            Log-Success "계정 삭제 완료: $uname"
        } catch {
            Log-Error "계정 삭제 실패: $uname ($($_.Exception.Message))"
        }
    } else {
        Log-Info "계정 '$uname'은 존재하지 않습니다. 건너뜁니다."
    }
}

foreach ($gname in $createdGroups) {
    if (Get-LocalGroup -Name $gname -ErrorAction SilentlyContinue) {
        try {
            Remove-LocalGroup -Name $gname -ErrorAction Stop
            Log-Success "그룹 삭제 완료: $gname"
        } catch {
            Log-Error "그룹 삭제 실패: $gname ($($_.Exception.Message)) - 아직 멤버가 남아있는지 확인 필요"
        }
    } else {
        Log-Info "그룹 '$gname'은 존재하지 않습니다. 건너뜁니다."
    }
}

Remove-Manifest -ManifestName "created_accounts.txt"
Remove-Manifest -ManifestName "created_groups.txt"

Log-Warn "=== 계정/그룹 롤백 완료: $($script:HostnameShort) ==="
