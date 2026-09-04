# ---------------------------------------------------------------------------                 
# Windows Server 계정 생성 전용 스크립트 (일반 계정: 최초 암호 변경 / osmanaged: 만료 비활성화)
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
$ServerIndex = Read-Host "이 서버의 순번을 입력하세요 (1~$TotalServers)"

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
# [대상 확인 로직] 호스트네임 및 실제 IP 정확하게 추출      
# ---------------------------------------------------------------------------          

$ipList = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }      
$CurrentIP = if ($ipList) { $ipList[0].IPAddress } else { "IP를 찾을 수 없음" }

$HostnameInCSV = $Target.PSObject.Properties.Value[0]    
$ActualHostname = hostname

Write-Host "`n====================================================" -ForegroundColor Yellow              
Write-Host "           [ 계정 생성 대상 확인 ]" -ForegroundColor Yellow              
Write-Host "====================================================" -ForegroundColor Yellow              
Write-Host " 실제 서버 이름 : $ActualHostname" -ForegroundColor White              
Write-Host " CSV 등록 이름 : $HostnameInCSV" -ForegroundColor Gray      
Write-Host " 현재 서버 실제 IP : $CurrentIP" -ForegroundColor Cyan            
Write-Host "----------------------------------------------------" -ForegroundColor Yellow

$UserColumns = $Target.PSObject.Properties.Name | Where-Object { $_ -like "User*" }                
Write-Host " 생성 예정 계정 목록 :" -ForegroundColor White                
foreach ($Col in $UserColumns) {                
    $Val = $Target.$Col                
    if (-not [string]::IsNullOrWhiteSpace($Val)) {                
        Write-Host "    - $Val" -ForegroundColor Cyan                
    }                
}                
Write-Host "====================================================`n" -ForegroundColor Yellow

$Confirm = Read-Host "이 서버에 위 계정들을 생성하시겠습니까? (Y/N)"                
if ($Confirm -ne "Y") {                
    Write-Host "작업이 취소되었습니다." -ForegroundColor Gray                
    exit                
}

# 관리 전용 계정 목록 (최초 암호 변경 강제 대상에서 제외)
$SpecialUsers = @("osmanaged")

# ---------------------------------------------------------------------------                 
# 계정 생성 및 권한 설정 수행 (가변 루프)                
# ---------------------------------------------------------------------------                 
Write-Host "`n[작업 시작] 계정 및 권한 설정을 적용 중입니다..." -ForegroundColor Cyan

foreach ($UserCol in $UserColumns) {                
    $Num = $UserCol.Substring(4)                
    $PassCol = "Pass$Num"                
    $GroupCol = "Group$Num"

    $Username = $Target.$UserCol                
    $Password = if ($Target.$PassCol) { $Target.$PassCol.Trim() } else { $null }                
    $Groups   = $Target.$GroupCol

    try {                
        if ([string]::IsNullOrWhiteSpace($Username)) { continue }    
        if ([string]::IsNullOrWhiteSpace($Password)) {     
            Write-Warning "  -> $Username 의 패스워드가 비어있어 생성을 건너뜁니다."    
            continue     
        }

        $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force                
                         
        # 1. 계정 생성 및 초기 패스워드 설정                
        if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {                
            New-LocalUser -Name $Username -Password $SecurePass                
            Write-Host "  -> 계정 생성 완료: $Username" -ForegroundColor Green                
        } else {                
            Write-Host "  -> 계정 이미 존재: $Username" -ForegroundColor Gray                
        }

        Set-LocalUser -Name $Username -Password $SecurePass    
        Write-Host "     - 패스워드 설정 및 동기화 완료" -ForegroundColor Gray

        # 2. 계정 유형별 패스워드 정책 적용
        if ($Username -in $SpecialUsers) {
            # [osmanaged 계정 처리]
            # 최초 로그인 시 암호 변경 제외(0) + 패스워드 만료 비활성화(UF_DONT_EXPIRE_PASSWORD) 적용
            try {
                $UserObj = [ADSI]"WinNT://localhost/$Username,user"
                $UserObj.Put("PasswordExpired", 0)
                $UserObj.userFlags = $UserObj.userFlags.Value -bor 0x10000
                $UserObj.SetInfo()

                Set-LocalUser -Name $Username -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                Write-Host "     - 관리 계정 정책 적용 완료 (최초 암호 변경 안 함 / 만료 비활성화)" -ForegroundColor Green
            } catch {
                Write-Warning "     - 관리 계정 정책 설정 실패: $($_.Exception.Message)"
            }
        } else {
            # [일반 계정 처리]
            # 최초 로그인 시 암호 변경 강제(1)
            try {    
                $UserObj = [ADSI]"WinNT://localhost/$Username,user"    
                $UserObj.Put("PasswordExpired", 1)     
                $UserObj.SetInfo()    
                Write-Host "     - 최초 로그인 시 암호 변경 설정 적용 완료 (ADSI)" -ForegroundColor Gray    
            } catch {    
                Write-Warning "     - 암호 변경 강제 설정 실패: $($_.Exception.Message)"    
            }
        }

        # 3. 가변 그룹 할당 (세미콜론 ';' 구분자로 분리)                
        if (-not [string]::IsNullOrWhiteSpace($Groups)) {                
            $GroupArray = $Groups.Split(';')                
            foreach ($G in $GroupArray) {                
                $GroupName = $G.Trim()                
                if (-not [string]::IsNullOrWhiteSpace($GroupName)) {

                    if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {                
                        New-LocalGroup -Name $GroupName                
                        Write-Host "     - 그룹 신규 생성: $GroupName" -ForegroundColor Cyan                
                    }                
                    Add-LocalGroupMember -Group $GroupName -Member $Username -ErrorAction SilentlyContinue                
                    Write-Host "     - 그룹 할당 완료: $GroupName" -ForegroundColor Green                
                }
            }                
        }                
    } catch {                
        Write-Warning "오류 발생 ($Username): $($_.Exception.Message)"                
    }                
}

Write-Host "`n====================================================" -ForegroundColor Yellow                
Write-Host "   모든 계정 설정이 완료되었습니다! (재부팅 불필요)   " -ForegroundColor White -BackgroundColor DarkGreen                
Write-Host "====================================================`n" -ForegroundColor Yellow
