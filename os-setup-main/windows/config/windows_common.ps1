# config/windows_common.ps1
# ==============================================================================
# SW 전역 설정 및 표준 로그 출력 함수
# ==============================================================================

# [전역] 공통 웹 다운로드 서버 URL 및 기본 경로
$global:CON_URL = "https://osmanaged.samsungds.net/os_setup/files"
$global:DOWN_PATH = "C:\os-setup\temp"
$global:LOG_DIR = "C:\os-setup\logs"

# [전역] TLS 1.2 강제 지정 (모든 모듈에서 개별 설정 불필요)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# SSL 인증서 검증 무시 (유지)  
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# 로그 디렉토리 생성
if (-not (Test-Path $global:LOG_DIR)) {
    New-Item -ItemType Directory -Force -Path $global:LOG_DIR | Out-Null
}

# ------------------------------------------------------------------------------
# 표준 로그 출력 함수 정의
# ------------------------------------------------------------------------------
function Get-TimeStamp { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

function Log-Info    ([string]$msg) { Write-Host "[INFO]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Cyan }
function Log-Warn    ([string]$msg) { Write-Host "[WARN]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Yellow }
function Log-Error   ([string]$msg) { Write-Host "[ERROR]   $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Red }
function Log-Success ([string]$msg) { Write-Host "[SUCCESS] $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Green }
