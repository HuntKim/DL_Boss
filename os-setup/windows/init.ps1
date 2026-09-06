# ==============================================================================
# os-setup/windows/init.ps1
# 계정/그룹 -> OS 파라미터 -> 스토리지 -> 디렉터리 권한 순서로 4개 모듈을
# 실행하는 오케스트레이터.
# ==============================================================================
# 사용법:
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode apply [-Yes]
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode verify
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode rollback [-Yes]
#
# apply/rollback 도중 한 단계라도 실패하면 즉시 중단한다. verify는 실패한
# 항목이 있어도 전체 현황을 보기 위해 끝까지 계속 진행한다.
# ==============================================================================
param(
    [ValidateSet("apply", "verify", "rollback")]
    [string]$Mode = "apply",
    [switch]$Yes
)

$CurrentDir = $PSScriptRoot

switch ($Mode) {
    "apply" {
        $Steps = @(
            "account\Account-Gen.ps1",
            "os-parameter\OsParam-Apply.ps1",
            "storage\Storage-Gen.ps1",
            "permission\Permission-Apply.ps1"
        )
    }
    "verify" {
        $Steps = @(
            "account\Account-Verify.ps1",
            "os-parameter\OsParam-Verify.ps1",
            "storage\Storage-Verify.ps1",
            "permission\Permission-Verify.ps1"
        )
    }
    "rollback" {
        # 적용의 역순: 권한 -> 스토리지 -> OS 파라미터 -> 계정
        $Steps = @(
            "permission\Permission-Rollback.ps1",
            "storage\Storage-Rollback.ps1",
            "os-parameter\OsParam-Rollback.ps1",
            "account\Account-Rollback.ps1"
        )
    }
}

$ExtraArgs = @()
if ($Yes) { $ExtraArgs += "-Yes" }

$OverallFail = $false

foreach ($step in $Steps) {
    $scriptPath = Join-Path $CurrentDir $step
    Write-Host "=================================================="
    Write-Host ">>> [$Mode] 실행: $step"
    Write-Host "=================================================="

    & $scriptPath @ExtraArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host ">>> 실패: $step"
        $OverallFail = $true
        if ($Mode -ne "verify") {
            Write-Host "=================================================="
            Write-Host "실패가 발생해 이후 단계를 중단합니다: $step"
            Write-Host "=================================================="
            exit 1
        }
    } else {
        Write-Host ">>> 성공: $step"
    }
    Write-Host ""
}

if (-not $OverallFail) {
    Write-Host "=================================================="
    Write-Host " 전체 $Mode 완료 (모든 단계 성공)"
    Write-Host "=================================================="
} else {
    Write-Host "=================================================="
    Write-Host " $Mode 완료 - 일부 항목 실패 (위 로그에서 확인)"
    Write-Host "=================================================="
}

exit ([int]$OverallFail)
