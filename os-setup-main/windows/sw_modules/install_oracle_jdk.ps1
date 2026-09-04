# sw_modules/install_jdk.ps1
# ==============================================================================
# Windows Server용 JDK 통합 설치 모듈
# ==============================================================================

param(
    [string]$TargetVersion,       # 설치 대상 JDK 버전 (예: 1.7.0_80, 1.8.0_265 등)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로 ($global:JAVA_HOME 정의)
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로 ($global:CON_URL, 로그 함수 등)
)

# ------------------------------------------------------------------------------
# [1단계] 설정 파일 및 공통 로그 함수 로드
# - 전역 공통 설정(로그 함수 포함)과 호스트별 설정($global:JAVA_HOME)을 불러옵니다.
# ------------------------------------------------------------------------------
if (Test-Path $CommonConfigFile) { 
    . $CommonConfigFile 
}
else {
    Write-Host "[ERROR] 공통 설정 파일($CommonConfigFile)을 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

if (Test-Path $HostConfigFile) { 
    . $HostConfigFile 
}
else {
    Log-Error "호스트 설정 파일($HostConfigFile)을 찾을 수 없습니다."
    exit 1
}

# 파라미터 양끝 공백 제거 (매핑 파일 파싱 시 에러 방지)
$TargetVersion = $TargetVersion.Trim()

Log-Info "=== JDK 통합 설치 모듈 시작 (타겟 버전: $TargetVersion) ==="

# ------------------------------------------------------------------------------
# [3단계] 타겟 버전에 따른 JDK 설치 파일명 매핑
# - sw_mapping_windows.txt 에서 전달된 $TargetVersion (예: 1.7.0_80, 1.8.0_265)
#   에 따라 다운로드할 바이너리 파일명을 지정합니다.
# ------------------------------------------------------------------------------
switch ($TargetVersion) {
    "1.7.0_80_64b" { $JdkFileName = "jdk-7u80-windows-x64.exe" }
    "1.8.0_271_64b" { $JdkFileName = "jdk-8u271-windows-x64.exe" }
    "1.8.0_45_64b" { $JdkFileName = "jdk-8u45-windows-x64.exe" }
    Default {
        Log-Error "지원하지 않거나 잘못된 JDK 버전 지정입니다: '$TargetVersion'"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# [4단계] 디렉토리 생성 및 설치 파일 다운로드
# - 타겟 디렉토리를 준비하고, sw_mapping_windows.txt 기반의 경로에서
#   TLS 1.2 프로토콜을 강제하여 웹 서버에서 인스톨러를 받아옵니다.
#   다운로드 URL: $CON_URL/windows/oracle_jdk_{TargetVersion}/{JdkFileName}
# ------------------------------------------------------------------------------
#if (-not (Test-Path $global:JAVA_HOME)) { New-Item -ItemType Directory -Force -Path $global:JAVA_HOME | Out-Null }
if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }

$DownloadUrl = "$($global:CON_URL)/windows/oracle_jdk_${TargetVersion}/$JdkFileName"
$InstallerPath = "$($global:DOWN_PATH)\$JdkFileName"

Log-Info "JDK 다운로드 시작: $DownloadUrl"
try {  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
    $wc.DownloadFile($DownloadUrl, $InstallerPath)  
    Log-Success "JDK 파일 다운로드 완료: $InstallerPath"  
} catch {  
    Log-Error "JDK 다운로드 실패: $_"  
    exit 1  
}

# ------------------------------------------------------------------------------
# [5단계] JDK Silent 자동 설치
# - 사용자 입력을 받지 않고 Background에서 지정된 경로로 Silent 설치를 진행합니다.
# ------------------------------------------------------------------------------
Log-Info "JDK Silent 설치 진행 중 (Target: $global:JAVA_HOME)..."
$InstallArgs = "/s INSTALLDIR=`"$global:JAVA_HOME`""

$Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru -Verb runAs

if ($Process.ExitCode -eq 0) {
    Log-Success "JDK Silent 설치 프로세스 정상 종료"
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force }
}
else {
    Log-Error "JDK 설치 실패 (Exit Code: $($Process.ExitCode))"
    if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force }
    exit 1
}
