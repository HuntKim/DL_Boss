<#  
==========================================================================================  
 [ Cloud OS Tech Service 윈도우 통합 설치 가이드 ]

 본 스크립트는 OSmanaged Collector의 설치 및 구동 상태를 확인하고  
 누락된 구성 요소만 선택적으로 설치하는 최적화 도구입니다.

 [ 필수 실행 조건 ]  
 1. 반드시 '관리자 권한으로 실행'된 PowerShell 창에서 진행해 주세요.  
    (권한 부족 시 서비스 등록 및 작업 스케줄러 설정이 실패합니다.)

 [ 실행 명령어 ]    
 ------------------------------------------------------------------------------------------    
 # 관리자 권한 PowerShell에서 아래 명령어를 한 번에 복사하여 실행하세요.  
 # 이 명령어는 권한 설정, 인코딩 설정 및 로그 파일 저장을 동시에 수행합니다.  
   
Set-ExecutionPolicy Bypass -Scope Process -Force; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; cmd /c "chcp 65001"  
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"; .\setup_monitoring.ps1 *>&1 | Tee-Object -FilePath "C:\os-setup\logs\$($env:COMPUTERNAME).monitor-result_$($TIMESTAMP).txt"  
 ------------------------------------------------------------------------------------------

 [ 주요 기능 ]  
 - 서비스 상태(Running 여부) 및 스케줄러 등록 여부 자동 체크  
 - 로컬에 설치 파일(.msi, .ps1)이 존재할 경우 네트워크 다운로드 없이 우선 설치  
 - 필수 설정 파일(.keyfile, .conf 등) 자동 배치 및 통신 확인  
==========================================================================================  
#>

# ==============================================================================      
# [0] 환경 설정 (로그 기록은 실행 명령어의 리다이렉션(*>)을 통해 수행됨)  
# ==============================================================================      
$LOG_DIR = "C:\os-setup\logs"    
$HOSTNAME = $env:COMPUTERNAME  
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$LOG_FILE_NAME = "$($HOSTNAME).monitor-result_$($TIMESTAMP).txt"  
$LOG_FULL_PATH = "$LOG_DIR\$LOG_FILE_NAME"

# 로그 디렉토리 생성 (리다이렉션 전 폴더가 반드시 있어야 함)  
if (!(Test-Path $LOG_DIR)) {    
    New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null    
}

# 1. 환경 변수 및 설정  
# $MSI_URL = "http://artifact.samsungds.net/artifactory/devops-template-generic/exporter/windows_exporter-0.20.0-amd64.msi"  
# $MSI_PATH = "C:\windows_exporter-0.20.0-amd64.msi"  
$COLLECTOR_BAT = "C:\osmanaged\bin\collector.bat"  
$TARGET_URL = "https://osmanaged.samsungds.net"  
# $EXE_PATH = "C:\Program Files\windows_exporter\windows_exporter.exe"  
$BASE_DIR = "C:\osmanaged"  
$INSTALL_PS1 = "install.ps1"

Write-Host "============================================================" -ForegroundColor Cyan  
Write-Host " Cloud OS Tech Service 윈도우 통합 설치를 시작합니다." -ForegroundColor Cyan  
Write-Host " 로그 저장 경로: $LOG_FULL_PATH" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

# 사전 통신 확인  
Write-Host "[CHECK] osmanaged 서버 통신 상태를 확인합니다..." -ForegroundColor Gray  
$connCheck = curl.exe -s -k -o nul https://osmanaged.samsungds.net  
if ($LASTEXITCODE -eq 0) {  
    Write-Host " -> 통신 상태 정상" -ForegroundColor Green  
} else {  
    Write-Host "------------------------------------------------------------" -ForegroundColor Red  
    Write-Host "[ERROR] osmanaged 서버(https://osmanaged.samsungds.net)와 통신이 불가능합니다." -ForegroundColor Red  
    Write-Host " 443 포트 오픈 여부를 확인해 주세요. (대상 IP: 10.172.104.132)" -ForegroundColor Red  
    Write-Host "------------------------------------------------------------" -ForegroundColor Red  
    exit  
}  

# ==============================================================================  
# [사전 체크] 에이전트 구동 상태 확인  
# ==============================================================================  
Write-Host "[CHECK] 기존 에이전트 구동 상태를 확인합니다..." -ForegroundColor Gray

# 1) Windows Exporter 서비스 확인  
# $service = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue  
# $nodeUp = ($null -ne $service -and $service.Status -eq 'Running')

# 2) Collector 작업 스케줄러 확인  
$task = Get-ScheduledTask -TaskName "OSmanaged_Collector" -ErrorAction SilentlyContinue  
$collectorUp = ($null -ne $task)

# Collector 정상 여부만 확인하여 종료 처리 
if ($collectorUp) {  
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan  
    Write-Host " [결과] Collector가 이미 정상 작동 중입니다." -ForegroundColor Green  
    Write-Host " 기존 설정을 유지하며 스크립트를 종료합니다." -ForegroundColor Green  
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan  
    exit  
}

Write-Host " -> 설치가 필요하거나 일부 구성 요소가 누락되었습니다. 작업을 진행합니다." -ForegroundColor Yellow

# ==============================================================================  
# [모듈 1] Windows Exporter 체크 및 설치  
# ==============================================================================  
# if ($nodeUp) {  
#     Write-Host "[1/2] Windows Exporter: 이미 정상 작동 중입니다. 건너뜁니다." -ForegroundColor Green  
# } else {  
#     Write-Host "[1/2] Windows Exporter 설치 진행 중..." -ForegroundColor Yellow  
        
#     # 기존 제거 (안전한 삭제)  
#     Stop-Service -Name "windows_exporter" -Force -ErrorAction SilentlyContinue  
#     sc.exe delete windows_exporter  
#     Remove-Item -Recurse -Force "HKLM:\SYSTEM\CurrentControlSet\Services\windows_exporter" -ErrorAction SilentlyContinue  
        
#     # 설치 파일 체크 및 실행  
#     if (Test-Path $MSI_PATH) {  
#         Write-Host " -> 로컬 MSI 파일을 발견했습니다. 이를 사용하여 설치합니다." -ForegroundColor Gray  
#     } else {  
#         Write-Host " -> 로컬 설치 파일이 없습니다. 신규 다운로드 합니다." -ForegroundColor Gray  
#         curl.exe -L -o $MSI_PATH $MSI_URL  
#     }  
#     Start-Process msiexec.exe -ArgumentList "/i $MSI_PATH ENABLED_COLLECTORS=`"[defaults],tcp,memory`" LISTEN_PORT=`"9182`" /qn" -Wait  
        
#     # 서비스 재등록 및 시작  
#     $binPath = "`"$EXE_PATH`" --collectors.enabled=cpu,cpu_info,cs,logical_disk,logon,memory,net,os,service,tcp,time,system --telemetry.addr=0.0.0.0:9182"  
#     New-Service -Name "windows_exporter" -BinaryPathName $binPath -StartupType Automatic  
#     Start-Service -Name "windows_exporter"  
#     Write-Host " -> Windows Exporter 설치 완료." -ForegroundColor Green  
# }

# ==============================================================================  
# [모듈 2] Collector 체크 및 설치  
# ==============================================================================  
if ($collectorUp) {  
    Write-Host "[2/2] Collector: 이미 정상 등록되어 있어 건너뜁니다." -ForegroundColor Green  
} else {  
    Write-Host "[2/2] Collector 설치 진행 중..." -ForegroundColor Yellow  
        
    # 기존 제거  
    Unregister-ScheduledTask -TaskName "OSmanaged_Collector" -Confirm:$false -ErrorAction SilentlyContinue  
    if (Test-Path $BASE_DIR) {  
        Remove-Item -Path "$BASE_DIR\bin\*" -Recurse -Force -ErrorAction SilentlyContinue  
        Remove-Item -Path "$BASE_DIR\sbin\*" -Recurse -Force -ErrorAction SilentlyContinue  
    }  
        
    # 설치 파일 체크 및 실행  
    if (Test-Path $INSTALL_PS1) {  
        Write-Host " -> 로컬 설치 파일($INSTALL_PS1)을 발견했습니다. 이를 사용하여 설치합니다." -ForegroundColor Gray  
          
        # 로컬 install.ps1 실행 전 필수 환경 구성 (폴더 및 설정파일)  
        New-Item -ItemType Directory -Force -Path "$BASE_DIR\sbin", "$BASE_DIR\bin", "$BASE_DIR\conf", "$BASE_DIR\log" | Out-Null  
        curl.exe -k -L -o "$BASE_DIR\conf\agent.conf" "$TARGET_URL/agent_deploy/agent.conf"  
        curl.exe -k -L -o "$BASE_DIR\conf\token.conf" "$TARGET_URL/agent_deploy/token.conf"  
        curl.exe -k -L -o "$BASE_DIR\conf\.keyfile" "$TARGET_URL/agent_deploy/.keyfile"  

        # 버전 파일 생성 추가
        curl.exe -k -L -o "$BASE_DIR\conf\version" "$TARGET_URL/windows_agent_deploy/version"
          
        powershell -ExecutionPolicy Bypass -File $INSTALL_PS1  
    } else {    
        Write-Host " -> 로컬 설치 파일이 없습니다. 신규 다운로드 후 설치합니다." -ForegroundColor Gray    
        
        $tempInstallPath = "$env:TEMP\install.ps1"  
        
        # 1. 다운로드  
        curl.exe -k -s -L -o $tempInstallPath "$TARGET_URL/windows_agent_deploy/install.ps1"  
        
        # 2. [핵심] 파일을 UTF8 인코딩으로 읽어서 변수에 담은 후 실행  
        # Get-Content -Encoding UTF8를 통해 파일 내용을 강제로 UTF8로 읽어옵니다.  
        $scriptContent = Get-Content -Path $tempInstallPath -Encoding UTF8 -Raw  
        Invoke-Expression $scriptContent  
    }
 
        
    # 작업 스케줄러 최종 등록  
    $TaskName = "OSmanaged_Collector"  
    $Action = New-ScheduledTaskAction -Execute $COLLECTOR_BAT  
    $Trigger = New-ScheduledTaskTrigger -Daily -At 5:30am  
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest  
    Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -TaskName $TaskName  
    Write-Host " -> Collector 설치 및 스케줄링 완료." -ForegroundColor Green  
}

# ==============================================================================  
# [최종 확인] 에이전트 동작 및 서버 통신 테스트  
# ==============================================================================  
Write-Host "============================================================" -ForegroundColor Cyan  
Write-Host "[FINAL] 최종 통신 및 버전 확인 중... (약 1분 소요될 수 있습니다)" -ForegroundColor Cyan  
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path $COLLECTOR_BAT) {  
    & $COLLECTOR_BAT --version  
} else {  
    Write-Host "버전 정보 확인 불가" -ForegroundColor Red  
}

# ==============================================================================      
# 최종 설치 검증 (Verification)    
# ==============================================================================      
Write-Host "`n[VERIFICATION] 설치 구성 요소를 최종 검증합니다..." -ForegroundColor Cyan

$verificationResults = @()

# 실제 설치된 파일명으로 확인  
$filesToCheck = @(    
    $COLLECTOR_BAT,              # C:\osmanaged\bin\collector.bat    
    "$BASE_DIR\conf\agent.conf.ps1", # 실제 생성 파일명 반영  
    "$BASE_DIR\conf\token"           # 실제 생성 파일명 반영  
)

foreach ($file in $filesToCheck) {      
    $status = if (Test-Path $file) { "OK" } else { "FAIL" }      
    $verificationResults += [PSCustomObject]@{ 항목 = "파일: $(Split-Path $file -Leaf)"; 결과 = $status }      
}

# 스케줄러 등록 확인    
$taskCheck = Get-ScheduledTask -TaskName "OSmanaged_Collector" -ErrorAction SilentlyContinue    
$taskStatus = if ($null -ne $taskCheck) { "OK" } else { "FAIL" }    
$verificationResults += [PSCustomObject]@{ 항목 = "스케줄러: OSmanaged_Collector"; 결과 = $taskStatus }

# 결과 표로 출력    
$verificationResults | Format-Table -AutoSize  


Write-Host "============================================================" -ForegroundColor Cyan  
Write-Host " 모든 체크 및 설치 절차가 성공적으로 완료되었습니다!" -ForegroundColor Cyan  
Write-Host "============================================================" -ForegroundColor Cyan  
