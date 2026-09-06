# ==============================================================================
# os-setup/windows/init.ps1
# 계정/그룹 -> OS 파라미터 -> 스토리지 -> 디렉터리 권한 -> SW 설치 -> 모니터링
# 순서로 실행하는 오케스트레이터.
# ==============================================================================
# 사용법:
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode apply [-Yes]
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode verify
#   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode rollback [-Yes]
#
# apply/rollback 도중 한 단계라도 실패하면 즉시 중단한다. verify는 실패한
# 항목이 있어도 전체 현황을 보기 위해 끝까지 계속 진행한다.
#
# ※ sw_modules\setup_sw.ps1, monitoring\setup_monitoring.ps1은
#   os-setup-main에서 그대로 가져온 것으로(다운로드 URL/옵션 등 내부
#   로직 변경 없음), 인자를 받지 않고 자체적으로 $env:COMPUTERNAME 기준
#   설정을 읽어 동작한다. 이 둘은 rollback/verify 스크립트가 원래부터
#   없어(os-setup-main에서도 없었음) apply 모드에만 포함한다.
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

# ==============================================================================
# 5~6. SW 설치 / 모니터링 (apply 모드에서만, 인자 없이 실행)
# ==============================================================================
if ($Mode -eq "apply" -and -not $OverallFail) {
    $ExtraSteps = @("sw_modules\setup_sw.ps1", "monitoring\setup_monitoring.ps1")
    foreach ($extraStep in $ExtraSteps) {
        $scriptPath = Join-Path $CurrentDir $extraStep
        if (-not (Test-Path $scriptPath)) {
            Write-Host "건너뜀 (파일 없음): $extraStep"
            continue
        }
        Write-Host "=================================================="
        Write-Host ">>> [$Mode] 실행: $extraStep"
        Write-Host "=================================================="

        & $scriptPath

        if ($LASTEXITCODE -ne 0) {
            Write-Host ">>> 실패: $extraStep"
            $OverallFail = $true
            Write-Host "=================================================="
            Write-Host "실패가 발생해 이후 단계를 중단합니다: $extraStep"
            Write-Host "=================================================="
            exit 1
        } else {
            Write-Host ">>> 성공: $extraStep"
        }
        Write-Host ""
    }
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
