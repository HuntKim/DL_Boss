# sw_modules/install_ssms.ps1
# ===========================================================================
# SSMS (SQL Server Management Studio) 설치 모듈
# SSMS 22 버전 silent 설치 지원
# ===========================================================================

param(
    [string]$TargetVersion,       # 설치 대상 버전 (예: 22)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로
)

# ---------------------------------------------------------------------------
# [1단계] 공통 설정 및 호스트 설정 로드
# ---------------------------------------------------------------------------
if (Test-Path $CommonConfigFile) { . $CommonConfigFile } else {
    Write-Host "[ERROR] 공통 설정 파일($CommonConfigFile)을 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

if (Test-Path $HostConfigFile) {
    . $HostConfigFile
}

if ([string]::IsNullOrEmpty($TargetVersion)) {
    Log-Error "TargetVersion 파라미터가 지정되지 않았습니다."
    exit 1
}

$TargetVersion = $TargetVersion.Trim()
Log-Info "=== SSMS $TargetVersion 설치 모듈 시작 ==="

# ---------------------------------------------------------------------------
# [3단계] 버전별 설치 파일명 매핑
# ---------------------------------------------------------------------------
switch ($TargetVersion) {
    "22" { $SsmsZipName = "SSMS_${TargetVersion}.zip" }
    Default {
        Log-Error "지원하지 않거나 잘못된 SSMS 버전 지정입니다: '$TargetVersion'"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# [4단계] 다운로드 디렉토리 생성 및 zip 파일 다운로드
# ---------------------------------------------------------------------------
if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }

$DownloadUrl = "$($global:CON_URL)/windows/ssms_${TargetVersion}/$SsmsZipName"
$ZipFilePath = "$($global:DOWN_PATH)\$SsmsZipName"

Log-Info "SSMS zip 파일 다운로드 시작: $DownloadUrl"
try {  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
    $wc.DownloadFile($DownloadUrl, $ZipFilePath)  
    Log-Success "SSMS zip 파일 다운로드 완료: $ZipFilePath"  
} catch {  
    Log-Error "SSMS zip 파일 다운로드 실패: $_"  
    exit 1  
} 

# ---------------------------------------------------------------------------
# [5단계] zip 파일 압축 해제
# ---------------------------------------------------------------------------
$ExtractPath = "C:\os-setup\temp\SSMS_$TargetVersion"
$InstallerFile = "vs_SSMS.exe"

if (-not (Test-Path $ExtractPath)) {
    New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null
}

Log-Info "SSMS $TargetVersion 압축 해제 시작: $ZipFilePath -> $ExtractPath"
try {
    if (Test-Path $ExtractPath) { Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue }  
    New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $ExtractPath)

    Log-Success "압축 해제 완료"
}
catch {
    Log-Error "SSMS $TargetVersion 압축 해제 실패: $_"
    exit 1
}

Log-Info "설치 파일($InstallerFile) 위치 탐색 중..."  
$ActualInstaller = Get-ChildItem -Path $ExtractPath -Filter $InstallerFile -Recurse | Select-Object -First 1

if ($null -eq $ActualInstaller) {  
    Log-Error "SSMS 설치 프로그램을 찾을 수 없습니다. (탐색 경로: $ExtractPath)"  
    exit 1  
}

$InstallerPath = $ActualInstaller.FullName  

Log-Info "== $InstallerPath"

# ---------------------------------------------------------------------------
# [6단계] SSMS Silent 설치
# ---------------------------------------------------------------------------
# SSMS 설치 옵션
# --noWeb      : No WEB Connection
# --quiet        : 완전 silent (UI 없음)
# --norestart    : 재부팅 불필요
$installArgs = @(
    "--noWeb"
    "--quiet"
    "--norestart"
    "--wait"
)

Log-Info "========================================================="
Log-Info "SSMS $TargetVersion 설치 중... (시간이 오래 걸릴 수 있습니다.)"
Log-Info "========================================================="

# Start-Process 로 실행하되, 창 숨기기 및 백그라운드 처리
Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait

# ---------------------------------------------------------------------------
# [7단계] 임시 파일 정리
# ---------------------------------------------------------------------------
Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $ZipFilePath -Force -ErrorAction SilentlyContinue
Log-Info "임시 파일 및 zip 파일 정리 완료"

exit 0
