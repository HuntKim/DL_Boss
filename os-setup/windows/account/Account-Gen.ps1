# ==============================================================================
# account/Account-Gen.ps1
# 호스트 env($HostGroups, $HostAccounts)를 기준으로 그룹 -> 계정 순으로 생성.
#
# ※ 비밀번호는 절대 config에 넣지 않는다. 계정 생성 시 임의의 임시
#   비밀번호를 생성해 이번 실행의 콘솔 출력에만 1회 표시하고, 어디에도
#   저장하지 않는다. 계정은 "다음 로그온 시 암호 변경 필수"로 설정되므로
#   실제 사용자가 최초 로그온 시 자신의 비밀번호로 바꾸게 된다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Account-Gen.ps1 [-Yes]
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
# 2. 계정 생성
# ==============================================================================
function New-RandomPassword {
    # 대문자/소문자/숫자/특수문자를 섞은 16자리 임의 비밀번호
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*'
    -join (1..16 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

$createdSummary = New-Object System.Collections.Generic.List[PSCustomObject]
$fail = $false

foreach ($acct in $HostAccounts) {
    $uname = $acct.User

    if (Get-LocalUser -Name $uname -ErrorAction SilentlyContinue) {
        Log-Info "계정 '$uname'은 이미 존재합니다. 건너뜁니다 (필드 일치 여부는 Account-Verify.ps1로 확인하세요)."
        continue
    }

    $plainPassword = New-RandomPassword
    $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

    try {
        New-LocalUser -Name $uname -Password $securePassword -FullName $uname `
            -Description "os-setup 자동 생성 계정 ($(Get-TimeStamp))" -ErrorAction Stop | Out-Null

        # New-LocalUser는 "다음 로그온 시 암호 변경 필수" 옵션을 직접
        # 노출하지 않으므로 WinNT ADSI provider로 설정한다(표준적인 방법).
        try {
            $objUser = [ADSI]"WinNT://$env:COMPUTERNAME/$uname,user"
            $objUser.PasswordExpired = 1
            $objUser.SetInfo()
        } catch {
            Log-Warn "'다음 로그온 시 암호 변경' 설정 실패: $uname ($($_.Exception.Message)) - 수동으로 설정 필요"
        }

        foreach ($grp in $acct.Groups) {
            try {
                Add-LocalGroupMember -Group $grp -Member $uname -ErrorAction Stop
            } catch {
                Log-Warn "그룹 추가 실패: '$uname' -> '$grp' ($($_.Exception.Message))"
            }
        }

        Add-ManifestRecord -ManifestName "created_accounts.txt" -Value $uname
        $createdSummary.Add([PSCustomObject]@{ User = $uname; TempPassword = $plainPassword })
        Log-Success "계정 생성 완료: $uname (그룹: $($acct.Groups -join ', '))"
    } catch {
        Log-Error "계정 생성 실패: $uname ($($_.Exception.Message))"
        $fail = $true
    }

    $plainPassword = $null
    $securePassword = $null
}

if ($createdSummary.Count -gt 0) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Magenta
    Write-Host " 아래 임시 비밀번호는 이번 실행에서만 출력되며 어디에도" -ForegroundColor Magenta
    Write-Host " 저장되지 않습니다. 지금 안전한 곳에 기록해두세요." -ForegroundColor Magenta
    Write-Host " (각 계정은 다음 로그온 시 반드시 비밀번호를 변경해야 합니다)" -ForegroundColor Magenta
    Write-Host "==================================================" -ForegroundColor Magenta
    $createdSummary | Format-Table -AutoSize | Out-String | Write-Host
}

if ($fail) {
    Log-Error "일부 계정 생성에 실패했습니다."
    exit 1
}

Log-Success "=== 계정/그룹 생성 완료: $($script:HostnameShort) ==="
