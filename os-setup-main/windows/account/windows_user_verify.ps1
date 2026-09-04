# ---------------------------------------------------------------------------                 
# Windows Server 계정 설정 검증 스크립트 (windows_user_verify_v02.ps1 수정본)
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

$ServerIndex = Read-Host "검증할 서버 순번 입력 (1~$TotalServers)"

if ($ServerIndex -as [int] -eq $null) {
    Write-Error "입력 오류: 숫자만 입력 가능합니다."
    exit
}

$Target = $CSVData[[int]$ServerIndex - 1]

if ($null -eq $Target) {
    Write-Error "입력 오류: CSV 파일에 해당 순번의 정보가 없습니다."
    exit
}

$ActualHostname = hostname
Write-Host "`n[검증 시작] 서버 $ActualHostname 계정 설정 확인 중...`n" -ForegroundColor Cyan
Write-Host "[ 통합 계정 설정 검증 결과 ]`n" -ForegroundColor White

# 예외 관리 계정 목록
$SpecialUsers = @("osmanaged")

$UserColumns = $Target.PSObject.Properties.Name | Where-Object { $_ -like "User*" }
$ErrorCount = 0

# 헤더 출력
"{0,-10} {1,-10} {2,-6} {3}" -f "영역", "계정", "결과", "내용"
"{0,-10} {1,-10} {2,-6} {3}" -f "----", "----", "----", "----"

foreach ($UserCol in $UserColumns) {
    $Num = $UserCol.Substring(4)
    $GroupCol = "Group$Num"
    
    $Username = $Target.$UserCol

    if ([string]::IsNullOrWhiteSpace($Username)) { continue }

    # 계정 존재 여부 확인
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        "{0,-10} {1,-10} {2,-6} {3}" -f "CSV-일반", $Username, "X 실패", "계정이 존재하지 않음"
        $ErrorCount++
        continue
    }

    # ADSI 객체로 속성 검출
    try {
        $UserObj = [ADSI]"WinNT://localhost/$Username,user"
        $IsPasswordExpired = ($UserObj.PasswordExpired.Value -eq 1)
        
        # UF_DONT_EXPIRE_PASSWORD (0x10000 = 65536) 비트 플래그 확인
        $UserFlags = $UserObj.userFlags.Value
        $NeverExpires = (($UserFlags -band 0x10000) -eq 0x10000)
    } catch {
        $IsPasswordExpired = $false
        $NeverExpires = $false
    }

    # 현재 계정이 속한 그룹 추출
    $CurrentGroups = (Get-LocalGroup | Where-Object { 
        (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -like "*\$Username" 
    }).Name -join ","

    # ---------------------------------------------------------------------------
    # 계정 유형별 검증 로직
    # ---------------------------------------------------------------------------
    if ($Username -in $SpecialUsers) {
        # [관리 계정 검증 조건] 암호강제: False & 만료비활성: True
        if (-not $IsPasswordExpired -and $NeverExpires) {
            $ResultStr = "✔ 성공"
            $Color = "Green"
        } else {
            $ResultStr = "X 실패"
            $Color = "Red"
            $ErrorCount++
        }

        $Detail = "암호강제:$IsPasswordExpired/만료비활성:$NeverExpires/그룹:$CurrentGroups"
        Write-Host ("{0,-10} {1,-10} {2,-6} {3}" -f "CSV-관리", $Username, $ResultStr, $Detail) -ForegroundColor $Color

    } else {
        # [일반 계정 검증 조건] 암호강제: True
        if ($IsPasswordExpired) {
            $ResultStr = "✔ 성공"
            $Color = "Green"
        } else {
            $ResultStr = "X 실패"
            $Color = "Red"
            $ErrorCount++
        }

        $Detail = "암호강제:$IsPasswordExpired/그룹:$CurrentGroups"
        Write-Host ("{0,-10} {1,-10} {2,-6} {3}" -f "CSV-일반", $Username, $ResultStr, $Detail) -ForegroundColor $Color
    }
}

Write-Host ""
if ($ErrorCount -eq 0) {
    Write-Host "결과: 모든 계정 검증을 성공적으로 완료했습니다!" -ForegroundColor Green
} else {
    Write-Host "결과: 총 $ErrorCount 건의 오류가 발견되었습니다." -ForegroundColor Red
}
