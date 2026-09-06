# ==============================================================================
# account/Account-Verify.ps1
# 호스트 env($HostGroups, $HostAccounts)에 정의된 대로 실제로 그룹/계정이
# 생성되어 있는지 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
param()

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

Load-HostEnv

Log-Info "=== 계정/그룹 검증 시작: $($script:HostnameShort) ==="

$script:PassCount = 0
$script:FailCount = 0

function Check {
    param([string]$Description, [bool]$Ok)
    if ($Ok) {
        Log-Success "[PASS] $Description"
        $script:PassCount++
    } else {
        Log-Error "[FAIL] $Description"
        $script:FailCount++
    }
}

foreach ($gname in $HostGroups) {
    $grp = Get-LocalGroup -Name $gname -ErrorAction SilentlyContinue
    Check "그룹 '$gname' 존재" ($null -ne $grp)
}

foreach ($acct in $HostAccounts) {
    $uname = $acct.User
    $u = Get-LocalUser -Name $uname -ErrorAction SilentlyContinue

    if ($null -eq $u) {
        Check "계정 '$uname' 존재" $false
        continue
    }
    Check "계정 '$uname' 존재" $true
    Check "계정 '$uname' 활성화 상태" $u.Enabled

    foreach ($grp in $acct.Groups) {
        $isMember = $false
        try {
            $members = Get-LocalGroupMember -Group $grp -ErrorAction Stop
            $isMember = ($members | Where-Object { $_.Name -like "*\$uname" }).Count -gt 0
        } catch { }
        Check "계정 '$uname' 그룹 '$grp' 소속" $isMember
    }
}

Log-Info "=================================================="
Log-Info " 검증 결과: PASS $($script:PassCount) / FAIL $($script:FailCount)"
Log-Info "=================================================="

exit ([int]($script:FailCount -gt 0))
