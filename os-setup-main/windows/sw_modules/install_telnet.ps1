# sw_modules/install_telnet.ps1
# ==============================================================================
# Windows Server용 Telnet Client 설치 모듈
# ==============================================================================
# 윈도우 자체 포함된 기능 활성화이므로 버전 관리 및 변수 받지 않음
# ==============================================================================

Log-Info "========================================================="
Log-Info "Telnet Client 모듈 설치 시작합니다."
Log-Info "========================================================="

# Telnet Client 활성화 (Windows Server)
try {
    Install-WindowsFeature -Name Telnet-Client -IncludeManagementTools -ErrorAction Stop
    Log-Success "Telnet Client 설치 완료"
}
catch {
    # Windows Server가 아닌 경우 (Desktop Edition) OptionalFeature로 시도
    try {
        Enable-WindowsOptionalFeature -FeatureName Telnet-Client -Online -NoRestart -ErrorAction Stop
        Log-Success "Telnet Client 설치 완료"
    }
    catch {
        Log-Error "Telnet Client 설치 실패: $_"
        exit 1
    }
}

# Telnet 설치 확인
$telnetFeature = Get-WindowsFeature -Name Telnet-Client -ErrorAction SilentlyContinue
if ($telnetFeature -and $telnetFeature.Installed) {
    Log-Success "Telnet Client 설치 검증 완료"
}
else {
    # OptionalFeature 경로의 경우 확인 방법 다르게
    $telnetOptional = Get-WindowsOptionalFeature -FeatureName Telnet-Client -Online -ErrorAction SilentlyContinue
    if ($telnetOptional -and $telnetOptional.State -eq "Enabled") {
        Log-Success "Telnet Client 설치 검증 완료"
    }
    else {
        Log-Warn "Telnet Client 설치 후 검증 실패 - 수동 확인 필요"
    }
}

# telnet 명령어 존재 여부 확인
try {
    $telnetCmd = Get-Command telnet -ErrorAction Stop
    Log-Success "Telnet 명령어 확인 완료: $($telnetCmd.Source)"
}
catch {
    Log-Warn "Telnet 명령어를 찾을 수 없습니다 - 수동 확인 필요"
}
