# ==============================================================================
# permission/Permission-Apply.ps1
# 호스트 env($HostDirPermissions)에 정의된 디렉터리의 NTFS 권한을 적용한다.
# 스토리지(볼륨 생성)와 별개의 단계다.
#
# 형식: "경로:계정또는그룹:권한수준"  (권한수준: FullControl/Modify/ReadAndExecute)
# ※ 경로 자체에 드라이브 문자 콜론(예: F:\AppData)이 포함되므로, 뒤에서부터
#   2개 필드(계정, 권한수준)만 분리하고 나머지를 경로로 합친다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Permission-Apply.ps1 [-Yes]
# ==============================================================================
param(
    [switch]$Yes
)

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

$Global:AssumeYes = $Yes.IsPresent
Require-Admin
Load-HostEnv

Log-Info "=== 디렉터리 권한 적용 시작: $($script:HostnameShort) ==="

if ($HostDirPermissions.Count -eq 0) {
    Log-Warn "HostDirPermissions가 정의되어 있지 않습니다. 적용할 항목이 없어 종료합니다."
    exit 0
}

$PermMap = @{
    FullControl    = [System.Security.AccessControl.FileSystemRights]::FullControl
    Modify         = [System.Security.AccessControl.FileSystemRights]::Modify
    ReadAndExecute = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
}

$BackupManifest = "original_acls.txt"
$Fail = $false

foreach ($entry in $HostDirPermissions) {
    $parts = $entry -split ':'
    if ($parts.Count -lt 3) { Log-Warn "형식이 잘못된 항목을 건너뜁니다: '$entry'"; continue }

    $permLevel = $parts[-1]
    $account   = $parts[-2]
    $path      = ($parts[0..($parts.Count - 3)]) -join ':'

    if (-not $PermMap.ContainsKey($permLevel)) {
        Log-Error "지원하지 않는 권한수준입니다: '$permLevel' (경로: $path). FullControl/Modify/ReadAndExecute 중 하나여야 합니다."
        $Fail = $true
        continue
    }

    $isNewDir = $false
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Add-ManifestRecord -ManifestName "created_dirs.txt" -Value $path
        $isNewDir = $true
        Log-Info "디렉터리가 없어 새로 생성했습니다: $path (rollback 시 삭제 대상으로 기록)"
    }

    try {
        $null = Get-LocalUser -Name $account -ErrorAction Stop
    } catch {
        try {
            $null = Get-LocalGroup -Name $account -ErrorAction Stop
        } catch {
            Log-Error "'$path'의 계정/그룹으로 지정된 '$account'을 찾을 수 없습니다. Account-Gen.ps1을 먼저 실행했는지 확인하세요."
            $Fail = $true
            continue
        }
    }

    # 새로 만든 디렉터리는 rollback에서 통째로 삭제되므로 원래 ACL을 백업할
    # 필요가 없다(오히려 두 기록이 겹치면 rollback이 혼란스러워진다).
    # 기존에 있던 경로만 백업 대상이다.
    if (-not $isNewDir) {
        $alreadyBackedUp = (Get-ManifestRecords -ManifestName $BackupManifest) | Where-Object { $_ -like "$path|*" }
        if (-not $alreadyBackedUp) {
            $origSddl = (Get-Acl -Path $path).Sddl
            Add-ManifestRecord -ManifestName $BackupManifest -Value "$path|$origSddl"
        }
    }

    try {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $account, $PermMap[$permLevel], "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl = Get-Acl -Path $path
        $acl.AddAccessRule($rule)
        Set-Acl -Path $path -AclObject $acl
        Log-Success "권한 적용 완료: $path ($account : $permLevel)"
    } catch {
        Log-Error "권한 적용 실패: $path ($($_.Exception.Message))"
        $Fail = $true
    }
}

if ($Fail) {
    Log-Error "일부 디렉터리 권한 적용에 실패했습니다."
    exit 1
}

Log-Success "=== 디렉터리 권한 적용 완료: $($script:HostnameShort) ==="
