# ==============================================================================
# permission/Permission-Verify.ps1
# 호스트 env($HostDirPermissions)에 정의된 대로 실제 NTFS 권한이 부여되어
# 있는지 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
param()

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

Load-HostEnv

Log-Info "=== 디렉터리 권한 검증 시작: $($script:HostnameShort) ==="

if ($HostDirPermissions.Count -eq 0) {
    Log-Warn "HostDirPermissions가 정의되어 있지 않습니다. 검증할 항목이 없습니다."
    exit 0
}

$PermMap = @{
    FullControl    = [System.Security.AccessControl.FileSystemRights]::FullControl
    Modify         = [System.Security.AccessControl.FileSystemRights]::Modify
    ReadAndExecute = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
}

$script:PassCount = 0
$script:FailCount = 0
function Check {
    param([string]$Description, [bool]$Ok)
    if ($Ok) { Log-Success "[PASS] $Description"; $script:PassCount++ }
    else { Log-Error "[FAIL] $Description"; $script:FailCount++ }
}

foreach ($entry in $HostDirPermissions) {
    $parts = $entry -split ':'
    if ($parts.Count -lt 3) { continue }

    $permLevel = $parts[-1]
    $account   = $parts[-2]
    $path      = ($parts[0..($parts.Count - 3)]) -join ':'

    if (-not (Test-Path $path)) {
        Check "경로 '$path' 존재" $false
        continue
    }
    Check "경로 '$path' 존재" $true

    if (-not $PermMap.ContainsKey($permLevel)) {
        Log-Warn "지원하지 않는 권한수준이라 건너뜁니다: '$permLevel' (경로: $path)"
        continue
    }

    $expectedRights = $PermMap[$permLevel]
    $acl = Get-Acl -Path $path
    $hasRule = $false
    foreach ($ar in $acl.Access) {
        $arAccount = $ar.IdentityReference.Value -replace '^.*\\', ''
        if ($arAccount -eq $account -and $ar.AccessControlType -eq 'Allow' -and
            (($ar.FileSystemRights -band $expectedRights) -eq $expectedRights)) {
            $hasRule = $true
            break
        }
    }
    Check "'$path' 에 '$account' 계정의 '$permLevel' 권한 존재" $hasRule
}

Log-Info "=================================================="
Log-Info " 검증 결과: PASS $($script:PassCount) / FAIL $($script:FailCount)"
Log-Info "=================================================="

exit ([int]($script:FailCount -gt 0))
