# sw_modules/setup_sw.ps1
# ==============================================================================
# SW 설치 메인 컨트롤러 (로그 기능 활성화)
# ==============================================================================

$HostName = $env:COMPUTERNAME

# 내부 config 경로 설정
$ConfigDir    = Resolve-Path "$PSScriptRoot\..\config"
$CommonConfig = "$ConfigDir\windows_common.ps1"
$HostConfig   = "$ConfigDir\env\$HostName.ps1"
$MappingFile  = "$ConfigDir\sw_mapping_window.txt"

# 1. 공통 설정 로드 (로그 함수 사용을 위해)
if (Test-Path $CommonConfig) { . $CommonConfig } else {
    Write-Host "[ERROR] 공통 설정 스크립트($CommonConfig)가 없습니다." -ForegroundColor Red
    exit 1
}

# 2. 파일 로깅 시작 (Transcript)
$LogFile = "$global:LOG_DIR\setup_sw_$($HostName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $LogFile -Append | Out-Null

Log-Info "========================================================="
Log-Info " SW 자동 설치 작업을 시작합니다. (Host: $HostName)"
Log-Info " 로그 파일 저장 위치: $LogFile"
Log-Info "========================================================="

# 3. 매핑 파일 읽기 및 설치 진행
if (-not (Test-Path $MappingFile)) {
    Log-Error "SW 매핑 파일($MappingFile)을 찾을 수 없습니다."
    Stop-Transcript | Out-Null
    exit 1
}

$TargetLine = @(Get-Content $MappingFile | Where-Object { $_ -like "${HostName}:*" })

if ($TargetLine) {
    $SwItems = $TargetLine[0].Split(":")[1].Trim().Split(",")
    
    foreach ($item in $SwItems) {
        $Parts = $item.Split("_")
        # 모듈 이름에서 버전 부분을 분리하여 install_*.ps1 파일 탐색
        $SwName    = $null
        $SwVersion = ""
        $ModuleScript = $null
        
        for ($i = $Parts.Count; $i -ge 1; $i--) {
            $Candidate = $Parts[0..($i - 1)] -join "_"
            $CandidatePath = "$PSScriptRoot\install_$Candidate.ps1"
            if (Test-Path $CandidatePath) {
                $ModuleScript = $CandidatePath
                $SwName = $Candidate
                $SwVersion = if ($i -lt $Parts.Count) { $Parts[$i..($Parts.Count - 1)] -join "_" } else { "" }
                break
            }
        }
        
        if (Test-Path $ModuleScript) {
            Log-Info "모듈 스크립트 호출: install_$SwName.ps1 (버전: $SwVersion)"
            & $ModuleScript `
                -TargetVersion $SwVersion `
                -HostConfigFile $HostConfig `
                -CommonConfigFile $CommonConfig
        } else {
            Log-Warn "설치 모듈 스크립트를 찾을 수 없습니다: $ModuleScript"
        }
    }
    Log-Success "모든 소프트웨어 설치 작업이 완료되었습니다."
} else {
    Log-Warn "$HostName 서버에 매핑된 SW 설치 항목이 없습니다."
}

Log-Info "========================================================="
Stop-Transcript | Out-Null
