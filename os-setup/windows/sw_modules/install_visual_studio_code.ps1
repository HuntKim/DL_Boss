# sw_modules/install_vscode.ps1
# ==============================================================================
# Windows Server용 VSCode 통합 설치 모듈
# ==============================================================================

param(
    [string]$TargetVersion,       # 설치 대상 VSCode 버전 (예: 1.108.1)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로 
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로 ($global:CON_URL, 로그 함수 등)
)

# ------------------------------------------------------------------------------
# [1단계] 공통 설정 및 호스트 설정 로드
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

$TargetVersion = $TargetVersion.Trim()
Log-Info "=== VSCode 설치 모듈 시작 (버전: $TargetVersion) ==="

# ------------------------------------------------------------------------------
# [3단계] 버전별 설치 파일명 매핑
# ------------------------------------------------------------------------------
switch ($TargetVersion) {
    "1.108.1_64b" { $VscFileName = "VSCodeSetup-x64-1.108.1.exe" }
    default {
        Log-Error "지원하지 않는 VSCode 버전: '$TargetVersion'"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# [4단계] 다운로드 및 준비
# ------------------------------------------------------------------------------
if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }
$FolderVersion = $TargetVersion -replace "_64b", ""
$DownloadUrl = "$($global:CON_URL)/windows/visual_studio_code_${FolderVersion}/$VscFileName"
$InstallerPath = "$($global:DOWN_PATH)\$VscFileName"

Log-Info "VSCode 다운로드 시작: $DownloadUrl"
try {  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
    $wc.DownloadFile($DownloadUrl, $InstallerPath)  
    Log-Success "VSCode 다운로드 완료: $InstallerPath"  
} catch {  
    Log-Error "VSCode 다운로드 실패: $_"  
    exit 1  
} 

# ------------------------------------------------------------------------------
# [5 단계] Silent 설치 실행
# ------------------------------------------------------------------------------
Log-Info "VSCode Silent 설치 진행 중 (Target: $global:CODE_HOME)..."
$InstallArgs = @(
    "/VERYSILENT"
    "/NORESTART"
    "/MERGETASKS=!runcode,addtopath"
    "/D=`"$global:CODE_HOME`""
)

$process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru -Verb runAs

if ($process.ExitCode -eq 0) {
    Log-Success "VSCode 설치 프로세스 정상 종료"
    Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
}
else {
    Log-Error "VSCode 설치 실패 (ExitCode: $($process.ExitCode))"
    Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
    exit 1
}
