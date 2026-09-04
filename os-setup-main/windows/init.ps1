<#        
================================================================================        
Script Name    : init.ps1        
Description    : OS Setup 파일 및 구조 자동 배포 스크립트 (Windows PowerShell)        
-------------------------------------------------------------------------------        
[Quick Guide]        
파일 다운로드 후 실행 (가장 안정적):        
1. 브라우저에서 직접 다운로드: https://osmanaged.samsungds.net/os_setup/scripts/windows/init.ps1  
2. 관리자 권한 PowerShell에서 실행:  
  Set-ExecutionPolicy Bypass -Scope Process  
  .\init.ps1
================================================================================        
#>

# [보완 코드] TLS 1.2 강제 설정 (구형 OS 대응)    
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# [보완 코드] 관리자 권한 체크    
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())    
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {    
    Write-Error "이 스크립트는 반드시 '관리자 권한'으로 실행되어야 합니다. PowerShell을 관리자 권한으로 다시 열어주세요."    
    exit 1    
}  

# 1. 기본 설정 (중앙 서버 정보 및 표준 설치 경로)        
$BASE_URL = "https://osmanaged.samsungds.net/os_setup/scripts/windows"        
$TARGET_ROOT = "C:\os-setup\windows"        
$LOG_DIR = "C:\os-setup\logs"                
$DATE_STR = Get-Date -Format "yyyyMMdd_HHmmss"      
$LOG_FILE = "$LOG_DIR\os-setup_init_$($DATE_STR).log"        
$HOSTNAME = $env:COMPUTERNAME

# 로그 디렉토리 생성      
if (!(Test-Path $LOG_DIR)) {        
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null        
}

# 로그 기록 함수 정의      
function Write-Log {        
    param([string]$Message)        
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"        
    $LogEntry = "[$Timestamp] $Message"        
    Write-Host $Message        
    Add-Content -Path $LOG_FILE -Value $LogEntry        
}

# 기존 작업 영역 삭제 (Fresh Install을 위해)    
if (Test-Path $TARGET_ROOT) {        
    Write-Log "[INFO] Cleaning up previous installation files..."        
    Remove-Item -Path $TARGET_ROOT -Recurse -Force        
}

# 로그 시작        
Add-Content -Path $LOG_FILE -Value "==============================================================="        
Write-Log "  OS Setup Initialization started at $(Get-Date)"        
Write-Log "  Target Host: $HOSTNAME"        
Add-Content -Path $LOG_FILE -Value "==============================================================="

# 2. OS 버전 확인      
try {        
    $OS_VER = (Get-CimInstance Win32_OperatingSystem).Caption        
    Write-Log "[INFO] Detected OS Version: $OS_VER"        
} catch {        
    Write-Log "[ERROR] Cannot detect Windows version."        
    exit 1        
}

# 3. 디렉토리 구조 생성    
Write-Log "[INFO] Creating directory structure..."        
$Dirs = @(        
    "$TARGET_ROOT\config\env",        
    "$TARGET_ROOT\account",             
    "$TARGET_ROOT\sw_modules",        
    "$TARGET_ROOT\monitoring"          
)        
foreach ($dir in $Dirs) {        
    New-Item -ItemType Directory -Path $dir -Force | Out-Null        
}

# ------------------------------------------------------------------------------  
# 4. 보안 우회 다운로드 함수 (WebClient 방식)  
# ------------------------------------------------------------------------------  
function Download-File {        
    param (        
        [string]$RemotePath,        
        [string]$LocalPath        
    )        
    try {        
        # WebClient 객체 생성 및 User-Agent 위장  
        $wc = New-Object System.Net.WebClient  
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36")  
          
        # 서버 인증서 검증 무시 (필요 시)  
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}  
          
        $url = "$BASE_URL/$RemotePath"  
        $wc.DownloadFile($url, $LocalPath)  
          
        Write-Log "[DOWNLOAD] $RemotePath $\rightarrow$ $LocalPath"        
    } catch {        
        if (Test-Path $LocalPath) { Remove-Item $LocalPath -Force }        
        Write-Log "[SKIP] $RemotePath not found or download failed. Skipping... ($($_.Exception.Message))"        
    }        
}

# TXT 다운로드 후 CSV 변환 저장  
function Download-and-Convert-File {  
    param (  
        [string]$RemotePath,  
        [string]$LocalPath  
    )  
    try {  
        $tmp_file = "$LocalPath.tmp"  
        $wc = New-Object System.Net.WebClient    
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36")    
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}    
            
        $url = "$BASE_URL/$RemotePath"    
        $wc.DownloadFile($url, $tmp_file)  

        # 파일 내용을 읽어와서 UTF8(BOM 없이)로 저장하며 CSV로 변환  
        # -Raw로 읽어와서 불필요한 공백 제거 후 저장  
        $content = Get-Content -Path $tmp_file -Raw  
        [System.IO.File]::WriteAllText($LocalPath, $content, [System.Text.Encoding]::UTF8)  
          
        Remove-Item $tmp_file -Force  
        Write-Log "[CONVERTED] $RemotePath $\rightarrow$ $LocalPath"          
    } catch {          
        if (Test-Path $tmp_file) { Remove-Item $tmp_file -Force }          
        Write-Log "[SKIP] $RemotePath not found or download failed. Skipping... ($($_.Exception.Message))"          
    }          
}

# 5. 파일 다운로드 실행

# 5.1 Config 영역      
Write-Log "[INFO] Downloading configuration files..."        
Download-and-Convert-File "config\windows_user_gen.txt" "$TARGET_ROOT\config\windows_user_gen.csv"     
Download-File "config\sw_mapping_window.txt" "$TARGET_ROOT\config\sw_mapping_window.txt"
Download-File "config\windows_common.ps1" "$TARGET_ROOT\config\windows_common.ps1"
Download-File "config\env\$HOSTNAME.ps1" "$TARGET_ROOT\config\env\$HOSTNAME.ps1"

# 5.2 메인 공통 스크립트        
# Write-Log "[INFO] Downloading common script..."        
# Download-File "common.ps1" "$TARGET_ROOT\common.ps1"

# 5.3 계정 관리 모듈        
Write-Log "[INFO] Downloading account modules..."        
Download-File "account\windows_user_gen.ps1" "$TARGET_ROOT\account\windows_user_gen.ps1"
Download-File "account\windows_user_rollback.ps1" "$TARGET_ROOT\account\windows_user_rollback.ps1"
Download-File "account\windows_user_verify.ps1" "$TARGET_ROOT\account\windows_user_verify.ps1"

# 5.4 Monitoring 설치 모듈      
Write-Log "[INFO] Downloading monitoring modules..."        
Download-File "monitoring\setup_monitoring.ps1" "$TARGET_ROOT\monitoring\setup_monitoring.ps1"

# 5.5 SW 설치 모듈 (자동 리스트 추출 방식 적용)    
Write-Log "[INFO] Downloading SW modules from sw_modules directory..."

# 다운로드할 파일 목록을 명시적으로 정의  
$SW_FILES = @("install_ftp.ps1", "install_iis.ps1", "install_openjdk.ps1", "install_net_framework.ps1", "install_oracle_client.ps1", "install_oracle_jdk.ps1", "install_python.ps1", "install_ssms.ps1", "install_telnet.ps1", "install_visual_studio_code.ps1", "setup_sw.ps1")

if ($null -eq $SW_FILES -or $SW_FILES.Count -eq 0) {  
    Write-Log "[WARN] 다운로드할 SW 모듈 목록이 정의되지 않았습니다."  
} else {  
    foreach ($FILE in $SW_FILES) {  
        # Download-File 함수를 호출하여 다운로드 진행  
        Download-File "sw_modules\$FILE" "$TARGET_ROOT\sw_modules\$FILE"  
    }  
}

# 6. 마무리 및 실행 권한 안내        
Write-Log "[INFO] Initialization completed. Please ensure ExecutionPolicy is set to Bypass."

Add-Content -Path $LOG_FILE -Value "==============================================================="        
Write-Log "  Initialization Completed Successfully!"        
Write-Log "  Path: $TARGET_ROOT"        
# Write-Log "  Next Step: powershell -ExecutionPolicy Bypass -File $TARGET_ROOT\common.ps1"        
Add-Content -Path $LOG_FILE -Value "==============================================================="        
