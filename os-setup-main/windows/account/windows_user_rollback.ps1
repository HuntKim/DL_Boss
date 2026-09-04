# ---------------------------------------------------------------------------                
# Windows Server 계정 및 그룹 설정 원복(Rollback) 스크립트 - 최적화 버전      
# ---------------------------------------------------------------------------

# 1. 현재 스크립트 경로: C:\os-setup\windows\account
$CurrentDir = $PSScriptRoot 
              
# 2. 상위 폴더(windows)로 이동 후 config 폴더 결합  
# Split-Path -Parent를 통해 'account'를 제거하고 'C:\os-setup\windows'를 얻습니다.  
$ConfigDir = Join-Path -Path (Split-Path -Parent $CurrentDir) -ChildPath "config"

# 3. 최종 CSV 파일 경로 지정  
$ConfigFile = Join-Path -Path $ConfigDir -ChildPath "Windows_user_gen.csv"

$CSVData = Import-Csv "$ConfigFile"                
$TotalServers = $CSVData.Count

Write-Host "`n[ 시스템 로드 확인 ]" -ForegroundColor Cyan  
Write-Host "로드된 설정 파일: $ConfigFile"    
Write-Host "총 대상 서버 수: $TotalServers 대"    
$CSVData | Format-Table  # CSV 내용을 표 형태로 출력하여 사용자에게 보여줌
Write-Host "----------------------------------------------------`n" -ForegroundColor Cyan

# 1. 순번 입력 및 유효성 검사        
$ServerIndex = Read-Host "원복할 서버의 순번을 입력하세요 (1~$TotalServers)"

if ($ServerIndex -as [int] -eq $null) {                  
    Write-Error "입력 오류: 숫자만 입력 가능합니다."                  
    exit                  
}

$Target = $CSVData[[int]$ServerIndex - 1]

if ($null -eq $Target) {                  
    Write-Error "입력 오류: CSV 파일에 해당 순번의 정보가 없습니다."                  
    exit                  
}

# ---------------------------------------------------------------------------                
# [사전 분석 단계] 삭제 대상 리스트 수집      
# ---------------------------------------------------------------------------                
$UserColumns = $Target.PSObject.Properties.Name | Where-Object { $_ -like "User*" }        
$UsersToDelete = New-Object System.Collections.Generic.List[string]      
$GroupsToDelete = New-Object System.Collections.Generic.List[string]

foreach ($UserCol in $UserColumns) {                  
    $Username = $Target.$UserCol                  
    if ([string]::IsNullOrWhiteSpace($Username)) { continue }

    # 실제 시스템에 존재하는 계정만 삭제 리스트에 추가      
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {      
        $UsersToDelete.Add($Username)      
    }

    # 삭제 대상 그룹 수집      
    $Num = $UserCol.Substring(4)                  
    $GroupCol = "Group$Num"      
    $Groups = $Target.$GroupCol      
    if (-not [string]::IsNullOrWhiteSpace($Groups)) {                  
        $GroupArray = $Groups.Split(';')                  
        foreach ($G in $GroupArray) {                  
            $GroupName = $G.Trim()                  
            if ([string]::IsNullOrWhiteSpace($GroupName)) { continue }        
                  
            # [수정] 시스템 기본 그룹 제외 (안전 장치) - 정의되지 않은 $CreatedGroups 제거    
            $SystemGroups = @("Administrators", "Users", "Guests", "Remote Desktop Users", "Backup Operators", "Power Users")        
            if ($SystemGroups -notcontains $GroupName) {        
                # 중복 추가 방지    
                if ($GroupsToDelete -notcontains $GroupName) {    
                    $GroupsToDelete.Add($GroupName)      
                }    
            }      
        }                  
    }                  
}

# [추가] 시스템 전용 계정(osmanaged, appuser) 삭제 여부 결정    
# 만약 이 계정들도 원복 대상이라면 아래 리스트에 추가하십시오.    
$SysUsers = @("osmanaged", "appuser")    
foreach ($su in $SysUsers) {    
    if (Get-LocalUser -Name $su -ErrorAction SilentlyContinue) {    
        if ($UsersToDelete -notcontains $su) { $UsersToDelete.Add($su) }    
    }    
}

# ---------------------------------------------------------------------------                
# [확인 단계] 삭제 예정 목록 표시 및 사용자 승인      
# ---------------------------------------------------------------------------                
if ($UsersToDelete.Count -eq 0 -and $GroupsToDelete.Count -eq 0) {      
    Write-Host "`n[확인] 삭제할 계정이나 그룹이 시스템에 존재하지 않습니다." -ForegroundColor Gray      
    exit      
}

Write-Host "`n====================================================" -ForegroundColor Yellow      
Write-Host "           [ ⚠️  원복 대상 목록 확인 ]" -ForegroundColor Yellow      
Write-Host "====================================================" -ForegroundColor Yellow

Write-Host " [삭제 예정 계정] :" -ForegroundColor White      
if ($UsersToDelete.Count -gt 0) {      
    foreach ($u in $UsersToDelete) { Write-Host "    - $u" -ForegroundColor Cyan }      
} else { Write-Host "    - 없음" -ForegroundColor Gray }

Write-Host "`n [삭제 예정 그룹] :" -ForegroundColor White      
if ($GroupsToDelete.Count -gt 0) {      
    foreach ($g in $GroupsToDelete) { Write-Host "    - $g" -ForegroundColor Cyan }      
} else { Write-Host "    - 없음" -ForegroundColor Gray }

Write-Host "====================================================" -ForegroundColor Yellow      
Write-Host " 위 목록의 모든 계정과 그룹이 영구적으로 삭제됩니다." -ForegroundColor White      
$Confirm = Read-Host "정말로 진행하시겠습니까? (y/n)"

if ($Confirm -ne "y" -and $Confirm -ne "Y") {      
    Write-Host "`n[작업 취소] 원복 프로세스를 중단합니다." -ForegroundColor Gray      
    exit      
}

# ---------------------------------------------------------------------------                  
# [실행 단계] 실제 원복 수행      
# ---------------------------------------------------------------------------                
Write-Host "`n>>> 원복 프로세스를 시작합니다..." -ForegroundColor Cyan

# 1. 계정 삭제      
foreach ($Username in $UsersToDelete) {                  
    try {        
        Remove-LocalUser -Name $Username        
        Write-Host "  -> 계정 삭제 완료: $Username" -ForegroundColor Green        
    } catch {        
        Write-Warning "  -> 계정 삭제 실패 ($Username): $($_.Exception.Message)"        
    }        
}

# 2. 사용자 정의 그룹 삭제      
Write-Host "`n[그룹 정리 중...]" -ForegroundColor Cyan        
foreach ($GroupName in $GroupsToDelete) {        
    if (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue) {        
        try {                
            Remove-LocalGroup -Name $GroupName        
            Write-Host "  -> 그룹 삭제 완료: $GroupName" -ForegroundColor Green        
        } catch {        
            Write-Host "  -> 그룹 삭제 실패 ($GroupName): $($_.Exception.Message)" -ForegroundColor Red        
        }        
    }        
}

Write-Host "`n====================================================" -ForegroundColor Yellow        
Write-Host "   모든 원복 작업이 완료되었습니다." -ForegroundColor White        
Write-Host "====================================================`n" -ForegroundColor Yellow 
