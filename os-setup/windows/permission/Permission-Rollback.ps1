# ==============================================================================
# permission/Permission-Rollback.ps1
# Permission-Apply.ps1이 변경하기 전에 SDDL로 백업해둔 원래 ACL로
# 복원하고, 새로 만든 디렉터리는 삭제한다(비어있을 때만).
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Permission-Rollback.ps1 [-Yes]
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

Log-Warn "=== 디렉터리 권한 롤백 시작: $($script:HostnameShort) ==="

$Backups     = Get-ManifestRecords -ManifestName "original_acls.txt"
$CreatedDirs = Get-ManifestRecords -ManifestName "created_dirs.txt"

if ($Backups.Count -eq 0 -and $CreatedDirs.Count -eq 0) {
    Log-Warn "생성 기록(manifest)이 없습니다. Permission-Apply.ps1을 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
}

Log-Warn "아래 항목을 적용 이전 상태로 되돌립니다:"
foreach ($rec in $Backups) {
    $path = ($rec -split '\|', 2)[0]
    Log-Warn "  - $path -> 원래 ACL 복원"
}
foreach ($path in $CreatedDirs) {
    Log-Warn "  - $path -> 삭제 (Permission-Apply.ps1이 새로 만든 디렉터리, 비어있을 때만 삭제)"
}
Confirm-OrExit "정말로 진행하시겠습니까?"

# 1. 새로 만든 디렉터리는 삭제한다(비어있을 때만 - 데이터 손실 방지)
foreach ($path in $CreatedDirs) {
    if (-not (Test-Path $path)) {
        Log-Info "경로 '$path'가 이미 존재하지 않습니다. 건너뜁니다."
        continue
    }
    $items = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
    if ($items) {
        Log-Warn "디렉터리 '$path'가 비어있지 않아 삭제하지 않았습니다(데이터 보호). 수동 확인 필요."
        continue
    }
    try {
        Remove-Item -Path $path -Force -ErrorAction Stop
        Log-Success "새로 만든 디렉터리 삭제 완료: $path"
    } catch {
        Log-Error "디렉터리 삭제 실패: $path ($($_.Exception.Message))"
    }
}

# 2. 기존에 있던 경로는 백업해둔 원래 ACL(SDDL)로 복원한다
foreach ($rec in $Backups) {
    $parts = $rec -split '\|', 2
    if ($parts.Count -lt 2) { continue }
    $path = $parts[0]
    $sddl = $parts[1]

    if (-not (Test-Path $path)) {
        Log-Warn "경로 '$path'가 존재하지 않습니다. 건너뜁니다."
        continue
    }
    try {
        $acl = Get-Acl -Path $path
        $acl.SetSecurityDescriptorSddlForm($sddl)
        Set-Acl -Path $path -AclObject $acl
        Log-Success "ACL 복원 완료: $path"
    } catch {
        Log-Error "ACL 복원 실패: $path ($($_.Exception.Message))"
    }
}

Remove-Manifest -ManifestName "original_acls.txt"
Remove-Manifest -ManifestName "created_dirs.txt"

Log-Warn "=== 디렉터리 권한 롤백 완료: $($script:HostnameShort) ==="
