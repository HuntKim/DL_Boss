# ==============================================================================
# account/Account-Gen.ps1
# 호스트 env($HostGroups, $HostAccounts)를 기준으로 그룹 -> 계정 순으로 생성.
#
# ※ 새로 만드는 모든 계정에 동일한 초기 비밀번호($HostInitialPassword,
#   호스트 env 파일에 평문으로 지정)를 적용한다. 계정마다 다른 임의
#   비밀번호를 만들어 한 번만 보여주고 어디에도 저장하지 않던 이전
#   방식은 계정이 여러 개일 때 담당자가 비밀번호를 하나하나 따로
#   전달/관리해야 해서 번거롭다는 피드백에 따라 단순화함 - 담당자가
#   이 초기 비밀번호로 로그온해 바로 자신의 비밀번호로 바꾸는 것을
#   전제로 하므로, 재사용되는 값이 아니다.
#   ※ "다음 로그온 시 반드시 암호 변경" 강제(PasswordExpired)는 넣지
#     않는다 - hiware 쪽에서 이미 로그온 시 비밀번호 변경을 처리하고
#     있어서, OS 레벨에서 중복으로 강제하면 오류가 날 수 있다는
#     피드백에 따라 뺐다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Account-Gen.ps1 [-Yes]
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

Log-Info "=== 계정/그룹 생성 시작: $($script:HostnameShort) ==="

if ($HostGroups.Count -eq 0 -and $HostAccounts.Count -eq 0) {
    Log-Warn "HostGroups/HostAccounts가 정의되어 있지 않습니다. 종료합니다."
    exit 0
}

# ==============================================================================
# 1. 커스텀 그룹 생성 (Administrators 등 내장 그룹은 항상 존재하므로
#    여기서 다루지 않는다 - HostGroups에는 앱 전용 커스텀 그룹만 나열됨)
# ==============================================================================
foreach ($gname in $HostGroups) {
    if (Get-LocalGroup -Name $gname -ErrorAction SilentlyContinue) {
        Log-Info "그룹 '$gname'은 이미 존재합니다. 건너뜁니다."
        continue
    }
    try {
        New-LocalGroup -Name $gname -ErrorAction Stop | Out-Null
        Add-ManifestRecord -ManifestName "created_groups.txt" -Value $gname
        Log-Success "그룹 생성 완료: $gname"
    } catch {
        Log-Error "그룹 생성 실패: $gname ($($_.Exception.Message))"
    }
}

# ==============================================================================
# 2. 계정 생성 (모든 신규 계정에 $HostInitialPassword 하나를 동일하게 적용)
# ==============================================================================
$accountsToCreate = @($HostAccounts | Where-Object { -not (Get-LocalUser -Name $_.User -ErrorAction SilentlyContinue) })

if ($accountsToCreate.Count -gt 0 -and [string]::IsNullOrEmpty($HostInitialPassword)) {
    Log-Error "HostInitialPassword가 정의되어 있지 않습니다 (config/os_env/$($script:HostnameShort).ps1 확인)"
    exit 1
}

$SecureInitialPassword = if ($accountsToCreate.Count -gt 0) {
    ConvertTo-SecureString $HostInitialPassword -AsPlainText -Force
} else {
    $null
}

$fail = $false
$createdUsers = New-Object System.Collections.Generic.List[string]

foreach ($acct in $HostAccounts) {
    $uname = $acct.User

    if (Get-LocalUser -Name $uname -ErrorAction SilentlyContinue) {
        Log-Info "계정 '$uname'은 이미 존재합니다. 건너뜁니다 (필드 일치 여부는 Account-Verify.ps1로 확인하세요)."
        continue
    }

    try {
        New-LocalUser -Name $uname -Password $SecureInitialPassword -FullName $uname `
            -Description "os-setup 자동 생성 계정 ($(Get-TimeStamp))" -ErrorAction Stop | Out-Null

        foreach ($grp in $acct.Groups) {
            try {
                Add-LocalGroupMember -Group $grp -Member $uname -ErrorAction Stop
            } catch {
                Log-Warn "그룹 추가 실패: '$uname' -> '$grp' ($($_.Exception.Message))"
            }
        }

        Add-ManifestRecord -ManifestName "created_accounts.txt" -Value $uname
        $createdUsers.Add($uname)
        Log-Success "계정 생성 완료: $uname (그룹: $($acct.Groups -join ', '))"
    } catch {
        Log-Error "계정 생성 실패: $uname ($($_.Exception.Message))"
        $fail = $true
    }
}

if ($createdUsers.Count -gt 0) {
    Log-Success "생성된 계정: $($createdUsers -join ', ') (호스트 env에 지정된 초기 비밀번호 적용됨)"
}

if ($fail) {
    Log-Error "일부 계정 생성에 실패했습니다."
    exit 1
}

Log-Success "=== 계정/그룹 생성 완료: $($script:HostnameShort) ==="
