# sw_modules/install_openjdk.ps1
# ==============================================================================
# JDK Integrated Installation Module for Windows Server
# ==============================================================================

param(
    [string]$TargetVersion,       # 설치 대상 JDK 버전 (예: 8u265, 11, 17)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로 ($global:JAVA_HOME 정의)
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로 ($global:CON_URL, 로그 함수 등)
)

# ------------------------------------------------------------------------------
# [1단계] 설정 파일 및 공통 로그 함수 로드
# - 전역 공통 설정(로그 함수 포함)과 호스트별 설정($global:JAVA_HOME)을 불러옵니다.
# ------------------------------------------------------------------------------
if (Test-Path $CommonConfigFile) { 
    . $CommonConfigFile 
} else {
    Write-Host "[ERROR] 공통 설정 파일($CommonConfigFile)을 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

if (Test-Path $HostConfigFile) { 
    . $HostConfigFile 
} else {
    Log-Error "호스트 설정 파일($HostConfigFile)을 찾을 수 없습니다."
    exit 1
}

# 파라미터 양끝 공백 제거 (매핑 파일 파싱 시 에러 방지)
$TargetVersion = $TargetVersion.Trim()

Log-Info "=== JDK 통합 설치 모듈 시작 (타겟 버전: $TargetVersion) ==="

# ------------------------------------------------------------------------------
# [2단계] 사전 검증 및 기존 설치 여부 확인 (멱등성 보장)
# - 필수 변수 유효성을 체크하고, 이미 설치되어 있다면 재설치 없이 정상 종료합니다.
# ------------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($global:JAVA_HOME)) {
    Log-Error "JAVA_HOME 변수가 설정되지 않았습니다."
    exit 1
}

# 기존 java.exe 존재 시 버전 출력 후 스킵
$ExistingJavaExe = "$global:JAVA_HOME\bin\java.exe"
if (Test-Path $ExistingJavaExe) {
    Log-Warn "지정된 경로($global:JAVA_HOME)에 이미 Java가 설치되어 있습니다."
    Log-Info "기존 설치된 Java 버전을 검증합니다..."
    & $ExistingJavaExe -version
    Log-Success "기존 JDK가 확인되어 설치 과정을 건너뜁니다."
    exit 0
}

# ==============================================================================  
# [수정된 3~4단계] 동적 파일 탐색 및 다운로드 로직  
# ==============================================================================

# 1. 타겟 버전 기반 URL 생성 (예: 1.8.0_482)  
$VersionDir = $TargetVersion.Trim()  
$VersionDir = "openjdk_$VersionDir" 
$DownloadUrlDir = "$($global:CON_URL)/windows/$VersionDir/"  
$TargetRootDir = "$global:DOWN_PATH"

Log-Info "JDK 파일 탐색 시작: $DownloadUrlDir"

try {  
    # [동적 탐색] 서버 페이지의 HTML을 읽어와서 .zip 또는 .exe 파일명만 추출  
    $PageContent = (New-Object System.Net.WebClient).DownloadString($DownloadUrlDir)  
      
    # 정규표현식으로 href="파일명.zip" 또는 href="파일명.exe" 추출  
    # 리눅스의 grep -ioE 'href="[^"]+\.zip"' 와 동일한 역할  
    $FileMatch = [regex]::Matches($PageContent, 'href="([^"]+\.(zip|exe))"')  
      
    if ($FileMatch.Count -eq 0) {  
        Log-Error "서버의 $DownloadUrlDir 경로에서 설치 파일(.zip, .exe)을 찾을 수 없습니다."  
        exit 1  
    }

    # 가장 첫 번째로 매칭된 파일명을 가져옴  
    $JdkFileName = $FileMatch[0].Groups[1].Value  
    Log-Success "동적으로 파일 탐색 완료: $JdkFileName"

    $FullDownloadUrl = "$DownloadUrlDir$JdkFileName"  
    $InstallerPath = Join-Path $TargetRootDir $JdkFileName

    # 파일 다운로드  
    Log-Info "파일 다운로드 중... : $FullDownloadUrl"  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")  
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}  
    $wc.DownloadFile($FullDownloadUrl, $InstallerPath)  
    Log-Success "다운로드 완료: $InstallerPath"

} catch {  
    Log-Error "동적 파일 탐색 및 다운로드 중 오류 발생: $_"  
    exit 1  
}

# 이후 [5단계] 설치 처리(ZIP/EXE 분기) 로직은 기존과 동일하게 유지...  

# ------------------------------------------------------------------------------  
# [5단계] 설치 처리 (확장자에 따라 분기)  
# ------------------------------------------------------------------------------  
if ($JdkFileName -like "*.zip") {    
    Log-Info "JDK ZIP 압축 해제 및 경로 최적화 진행 중... (Target: $global:JAVA_HOME)"    
    # 1. 임시 폴더 생성  
    $TempExtractPath = Join-Path $env:TEMP "jdk_extract_$(Get-Random)"  
    New-Item -ItemType Directory -Path $TempExtractPath -Force | Out-Null  
        
    try {    
        Add-Type -AssemblyName System.IO.Compression.FileSystem    
        # 임시 폴더에 먼저 압축 해제  
        [System.IO.Compression.ZipFile]::ExtractToDirectory($InstallerPath, $TempExtractPath)    
          
        # 2. ZIP 내부의 실제 JDK 폴더(첫 번째 하위 폴더) 찾기  
        $InnerFolder = Get-ChildItem -Path $TempExtractPath | Select-Object -First 1  
        if ($null -eq $InnerFolder) { throw "ZIP 파일 내부에 폴더가 존재하지 않습니다." }

        # 3. 실제 JDK 내용물만 JAVA_HOME으로 이동 (상위 폴더 뎁스 제거)  
        if (-not (Test-Path $global:JAVA_HOME)) { New-Item -ItemType Directory -Force -Path $global:JAVA_HOME | Out-Null }  
        Copy-Item -Path "$($InnerFolder.FullName)\*" -Destination $global:JAVA_HOME -Recurse -Force  
          
        # 임시 폴더 삭제  
        Remove-Item -Path $TempExtractPath -Recurse -Force  
        Log-Success "JDK ZIP 압축 해제 및 경로 최적화 배치 완료"    
    } catch {    
        Log-Error "JDK 압축 해제 실패: $_"; exit 1    
    }
} else {  
    # --- EXE 파일 처리: Silent 설치 ---  
    Log-Info "JDK Silent 설치 진행 중 (Target: $global:JAVA_HOME)..."  
    $InstallArgs = "/s INSTALLDIR=`"$global:JAVA_HOME`""  
    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru -Verb runAs  
    if ($Process.ExitCode -eq 0) { Log-Success "JDK Silent 설치 정상 종료" } else { Log-Error "JDK 설치 실패 (ExitCode: $($Process.ExitCode))"; exit 1 }  
}

if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force }

# ------------------------------------------------------------------------------
# [6단계] 설치 디렉토리 보안 권한(ACL) 설정
# - Well-Known SID를 활용하여 언어 독립적(한글/영문 OS 공통)으로 표준 권한을 부여합니다.
#   - Administrators (S-1-5-32-544) : 모든 권한 (FullControl)
#   - Users          (S-1-5-32-545) : 읽기 및 실행 (ReadAndExecute)
# ------------------------------------------------------------------------------
Log-Info "설치 디렉토리 디폴트 권한(ACL) 세팅 중..."
$Acl = Get-Acl $global:JAVA_HOME

$SidAdmin = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$SidUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")

$ArAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule($SidAdmin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$ArUsers = New-Object System.Security.AccessControl.FileSystemAccessRule($SidUsers, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")

$Acl.SetAccessRule($ArAdmin)
$Acl.SetAccessRule($ArUsers)
Set-Acl $global:JAVA_HOME $Acl
Log-Success "권한 적용 완료 (Administrators: Full / Users: Read&Execute)"

# ------------------------------------------------------------------------------
# [7단계] 시스템 환경변수(JAVA_HOME & PATH) 등록 및 검증
# - 윈도우 시스템 레벨 환경변수에 무영구 등록하고 현재 세션 동기화 후 자바 버전을 검증합니다.
# ------------------------------------------------------------------------------
Log-Info "시스템 환경변수 등록 중..."
[Environment]::SetEnvironmentVariable("JAVA_HOME", $global:JAVA_HOME, "Machine")

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$JavaBinPath = "$global:JAVA_HOME\bin"

if ($CurrentPath -notlike "*$JavaBinPath*") {
    $NewPath = "$JavaBinPath;$CurrentPath"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
}

# 현재 실행 중인 파워쉘 세션에 즉시 즉시 적용 (터미널 재시작 없이 검증 가능)
$env:JAVA_HOME = $global:JAVA_HOME
$env:Path = "$JavaBinPath;$env:Path"

# 최종 실행 및 버전 동작 검증
$JavaExe = "$global:JAVA_HOME\bin\java.exe"
if (Test-Path $JavaExe) {
    Log-Info "Java 버전 출력 검증:"
    & $JavaExe -version
    Log-Success "JDK ($TargetVersion) 설치 및 검증 완벽 완료!"
} else {
    Log-Error "Java 실행 파일을 찾을 수 없습니다."
    exit 1
}
