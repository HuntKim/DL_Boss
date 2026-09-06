# sw_modules/install_ftp.ps1
# ==============================================================================
# Windows Server용 FTP Server 설치 모듈
# ==============================================================================
# 윈도우 자체 포함된 기능 활성화이므로 버전 관리 및 변수 받지 않음
# ==============================================================================

Log-Info "========================================================="
Log-Info "===          FTP Server 모듈 설치 시작합니다."
Log-Info "========================================================="

# FTP 설치를 위해 IIS 사전 의존성 확인
$iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if (-not ($iisFeature -and $iisFeature.Installed)) {
    Log-Error "FTP 설치 전 IIS가 설치되어 있지 않습니다. IIS를 먼저 설치하세요."
    exit 1
}

# FTP Server 활성화 (Windows Server)
try {
    Install-WindowsFeature Web-FTP-Server -IncludeAllSubFeature -IncludeManagementTools -ErrorAction Stop
    Log-Success "FTP Server 설치 완료되었습니다."
}
catch {
    Log-Error "FTP Server 설치 실패: $_"
    exit 1
}
