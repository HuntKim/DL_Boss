# sw_modules/install_python.ps1
# ==============================================================================
# Python Integrated Installation Module for Windows Server
# ==============================================================================
param(
    [string]$TargetVersion,       # 설치 대상 Python 버전 (예: 3.12.0)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로 
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로
)

# -------------------------------------------------------------------------------
# [1단계] 공통·호스트 설정 로드
# -------------------------------------------------------------------------------
if (Test-Path $CommonConfigFile) {
    . $CommonConfigFile
}
else {
    Write-Host "[ERROR] 공통 설정 파일(windows_common.ps1: $CommonConfigFile)을 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

if (Test-Path $HostConfigFile) {
    . $HostConfigFile
}
else {
    Log-Error "호스트 설정 파일($HostConfigFile)을 찾을 수 없습니다."
    exit 1
}

$TargetVersion = $TargetVersion.Trim()
Log-Info "=== Python 설치 모듈 시작 (버전: $TargetVersion) ==="

# -------------------------------------------------------------------------------
# [2단계] 버전별 설치 파일명 매핑
# -------------------------------------------------------------------------------
switch ($TargetVersion) {
    "3.12.0_64b" { $PyFileName = "python-3.12.0-amd64.exe" }
    default {
        Log-Error "지원되지 않는 Python 버전: '$TargetVersion'"
        exit 1
    }
}

# -------------------------------------------------------------------------------
# [3단계] 다운로드 및 준비
# -------------------------------------------------------------------------------
if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH   | Out-Null }

$DownloadUrl = "$($global:CON_URL)/windows/python_${TargetVersion}/$PyFileName"
$InstallerPath = "$($global:DOWN_PATH)\$PyFileName"

Log-Info "Python 다운로드 시작: $DownloadUrl"
try {  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
    $wc.DownloadFile($DownloadUrl, $InstallerPath)  
    Log-Success "다운로드 완료: $InstallerPath"  
}  
catch {  
    Log-Error "Python 다운로드 실패: $_"  
    exit 1  
}  

# -------------------------------------------------------------------------------
# [4단계] Silent 설치 실행
# -------------------------------------------------------------------------------
Log-Info "Python Silent 설치 진행 중..."

$InstallArgs = @(  
    "/quiet",  
    "InstallAllUsers=1",   
    "TargetDir=`"$global:PYTHON_HOME`"",
    "PrependPath=1",  
    "Include_pip=1"  
)

$process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru -Verb runAs

if ($process.ExitCode -eq 0) {
    Log-Success "Python 설치 프로세스 정상 종료"
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue }
}
else {
    Log-Error "Python 설치 실패 (ExitCode: $($process.ExitCode))"
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue }
    exit 1
}

if ($process.ExitCode -eq 0) {  
    Log-Success "Python 설치 프로세스 정상 종료"  
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue }  
}  
else {  
    Log-Error "Python 설치 실패 (ExitCode: $($process.ExitCode))"  
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue }  
    exit 1  
}

# -------------------------------------------------------------------------------  
# 내부망 PyPI 레포지토리 설정 (pip.ini 생성)  
# -------------------------------------------------------------------------------  
Log-Info "내부망 PyPI 레포지토리 설정을 진행합니다..."

# pip.ini 파일 경로 설정 (사용자별 설정 경로: %APPDATA%\pip\pip.ini)  
$PipConfigDir = "$env:APPDATA\pip"  
$PipConfigFile = "$PipConfigDir\pip.ini"

# pip 설정 내용 정의  
$PipConfigContent = @"  
[global]  
index-url = http://repository.samsungds.net/repository/proxy-pypi-files.pythonhosted.org/simple  
trusted-host = repository.samsungds.net  
"@

try {  
    if (-not (Test-Path $PipConfigDir)) {  
        New-Item -ItemType Directory -Force -Path $PipConfigDir | Out-Null  
        Log-Info "pip 설정 디렉토리 생성 완료: $PipConfigDir"  
    }

    Set-Content -Path $PipConfigFile -Value $PipConfigContent -Encoding Ascii -Force  
    Log-Success "내부망 pip.ini 설정 완료: $PipConfigFile"  
}  
catch {  
    Log-Error "pip.ini 설정 중 오류 발생: $_"  
    # 레포지토리 설정 실패는 설치 자체의 실패는 아니므로 Log-Warn 처리 후 계속 진행 가능  
}


# 5단계 : 설치 완료 검증
if (Test-Path "$global:PYTHON_HOME\python.exe") {
    Log-Info "Python 설치 성공 - PYTHON_HOME: $global:PYTHON_HOME"
}
else {
    Log-Warn "Python 설치 경로에서 python.exe를 찾을 수 없습니다: $global:PYTHON_HOME"
}
