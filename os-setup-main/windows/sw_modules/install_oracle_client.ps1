# sw_modules/install_oracle_client.ps1
# ==============================================================================
# Oracle Client 설치 모듈
# 원격 서버에서 zip 설치 파일을 다운로드 후, switch 로 버전별 파일 선정하여
# Silent 모드로 설치 
# ==============================================================================

param(
    [string]$TargetVersion,       # 설치 대상 버전 (예: 23, 21, 19)
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
Log-Info "=== Oracle Client $TargetVersion 설치 모듈 시작 ==="

# ---------------------------------------------------------------------------
# [4단계] 버전별 설치 파일명 매핑 (switch 방식)
# ---------------------------------------------------------------------------

Log-Info $TargetVersion
switch ($TargetVersion) {
    "19.3.0.0" { $OracleZipName = "WINDOWS.X64_193000_client.zip"; $OracleFullVersion = "19.3.0.0" }
    Default {
        Log-Error "지원하지 않거나 잘못된 Oracle Client 버전 지정입니다: '$TargetVersion'"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# [5단계] 다운로드 디렉토리 생성 및 zip 파일 다운로드
# ---------------------------------------------------------------------------
if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }

$DownloadUrl = "$($global:CON_URL)/windows/oracle_client_${TargetVersion}/$OracleZipName"
$ZipFilePath = "$($global:DOWN_PATH)\$OracleZipName"

Log-Info "Oracle Client zip 파일 다운로드 시작: $DownloadUrl"
try {  
    $wc = New-Object System.Net.WebClient  
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
    $wc.DownloadFile($DownloadUrl, $ZipFilePath)  
    Log-Success "Oracle Client zip 파일 다운로드 완료: $ZipFilePath"  
} catch {  
    Log-Error "Oracle Client zip 파일 다운로드 실패: $_"  
    exit 1  
} 

# ---------------------------------------------------------------------------
# [6단계] zip 파일 압축 해제
# ---------------------------------------------------------------------------
$ExtractPath = "C:\app\oracle\oracle_client_$TargetVersion"
$SetupExe = "$ExtractPath\client\setup.exe"

New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null

Log-Info "Oracle Client 압축 해제 시작: $ZipFilePath -> $ExtractPath"
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $ExtractPath)
    Log-Success "압축 해제 완료"
}
catch {
    Log-Error "Oracle Client 압축 해제 실패: $_"
    exit 1
}

if (-not (Test-Path $SetupExe)) {
    Log-Error "Oracle Client 설치 프로그램(setup.exe)을 찾을 수 없습니다: $SetupExe"
    exit 1
}

# ---------------------------------------------------------------------------
# [7단계] ORACLE_HOME 디렉토리 및 응답 파일 준비
# ---------------------------------------------------------------------------
$oracleBase = "C:\app\oracle"
if (-not (Test-Path $oracleBase)) { New-Item -ItemType Directory -Force -Path $oracleBase | Out-Null }

# 기본 응답 파일 사용 (clientsetup.rsp)
$rspFile = "$ExtractPath\client\response\client_install.rsp"
#$rspFile = "$ExtractPath\client\response\clientsetup.rsp"
if (-not (Test-Path $rspFile)) {
    Log-Error "기본 응답 파일을 찾을 수 없습니다: $rspFile"
    exit 1
}

# 응답 파일 수정 (ORACLE_BASE 및 IsBuiltInAccount)
# Oracle Installer가 ORACLE_BASE 아래에 Oracle Home을 자동 생성함
# Regex를 사용하여 = 뒤의 값만 정확히 교체 (기존 값 보존 방지)
$rspBytes = [System.IO.File]::ReadAllBytes($rspFile)
$rspContent = [System.Text.Encoding]::UTF8.GetString($rspBytes)
$rspContent = [regex]::Replace($rspContent, '(?<=ORACLE_BASE=).*', $oracleBase)
$rspContent = [regex]::Replace($rspContent, '(?<=ORACLE_HOME=).*', $ExtractPath)
$rspContent = [regex]::Replace($rspContent, '(?<=oracle\.install\.IsBuiltInAccount=).*', 'true')
$rspContent = [regex]::Replace($rspContent, '(?<=oracle\.install\.client\.installType=).*', 'Administrator')
$rspContent += "`r`nINVENTORY_LOCATION=$ExtractPath\inventory"

[System.IO.File]::WriteAllBytes($rspFile, [System.Text.Encoding]::UTF8.GetBytes($rspContent))
Log-Info "응답 파일 수정 완료: ORACLE_BASE=$oracleBase"
Log-Info "응답 파일 수정 완료: ORACLE_HOME=$ExtractPath"

# ---------------------------------------------------------------------------
# [8단계] Oracle Client Silent 설치
# ---------------------------------------------------------------------------
Log-Info "========================================================="
Log-Info "Oracle Client $TargetVersion ($OracleFullVersion) 설치 중... (시간이 오래 걸릴 수 있습니다.)"
Log-Info "========================================================="

# Oracle 19c Client 설치: 이미 정의된 $SetupExe (setup.exe)를 사용합니다.
$installArgs = @("-silent", "-responseFile", "`"$rspFile`"", "-waitforcompletion", "-ignorePrereqFailure")
$installTimeout = 1800
$startTime = Get-Date

try {
    $process = Start-Process -FilePath $SetupExe -ArgumentList $installArgs -Wait -PassThru

    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -gt $installTimeout) {
        Log-Warn "설치 시간이 $installTimeout 초를 초과했습니다."
        Log-Error "Oracle Client 설치 시간 초과"
        exit 1
    }

    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Log-Success "Oracle Client 설치 완료 (ExitCode: $($process.ExitCode))"
    }
    else {
        Log-Error "Oracle Client 설치 실패 (ExitCode: $($process.ExitCode))"
        exit 1
    }
}
catch {
    Log-Error "Oracle Client 설치 중 오류 발생: $_"
    exit 1
}

# ---------------------------------------------------------------------------
# [9단계] Oracle Home 설정 및 PATH 추가
# ---------------------------------------------------------------------------
# Oracle 19c Client는 추출 디렉토리가 ORACLE_HOME이 됨
$oracleHome = "$ExtractPath"

# 환경 변수 설정 (현재 세션)
[System.Environment]::SetEnvironmentVariable("ORACLE_BASE", $oracleBase, "Machine")
[System.Environment]::SetEnvironmentVariable("ORACLE_HOME", $oracleHome, "Machine")
$env:ORACLE_BASE = $oracleBase
$env:ORACLE_HOME = $oracleHome

### [수정됨] PATH에 Oracle bin 추가 로직 개선  
# 1. 시스템 레벨의 PATH 값만 정확하게 가져옵니다.  
$sysPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

# 2. 시스템 PATH 내에 해당 경로가 이미 존재하는지 확인합니다.  
if ($sysPath -notlike "*$oracleHome\bin*") {  
    Log-Info "System PATH에 Oracle bin 경로를 추가합니다."  
      
    # 3. 새로운 경로를 시스템 PATH 앞에 추가합니다. (기존 값 보존)  
    $newSysPath = "$oracleHome\bin;$sysPath"  
      
    # 4. 수정된 값을 다시 'Machine' 레벨에 저장합니다.  
    [System.Environment]::SetEnvironmentVariable("PATH", $newSysPath, "Machine")  
      
    # 5. 현재 실행 중인 PowerShell 세션에도 즉시 반영합니다.  
    $env:PATH = "$oracleHome\bin;$env:PATH"  
    Log-Success "System PATH 업데이트 완료."  
} else {  
    Log-Info "Oracle bin 경로가 이미 PATH에 존재하여 추가하지 않습니다."  
}

# ---------------------------------------------------------------------------
# [10단계] 임시 파일 정리 (zip 파일만 삭제, Oracle Home은 유지)
# ---------------------------------------------------------------------------
#Remove-Item -Path $ZipFilePath -Force -ErrorAction SilentlyContinue
Log-Info "zip 파일 정리 완료"

# ---------------------------------------------------------------------------
# [11단계] 설치 검증
# ---------------------------------------------------------------------------
Log-Info "========================================================="
Log-Info "Oracle Client $TargetVersion 설치 검증 중..."

if (Test-Path "$oracleHome\bin\sqlplus.exe") {
    $SqlplusExe = "$oracleHome\bin\sqlplus.exe"
    Log-Info "SQL*Plus 버전 확인:"
    & $SqlplusExe -V 2>&1 | Select-Object -First 3
    Log-Success "Oracle Client $TargetVersion ($OracleFullVersion) 설치 및 검증 완료! (ORACLE_HOME=$oracleHome)"
    exit 0
}
else {
    Log-Error "sqlplus.exe 를 찾을 수 없습니다: $oracleHome\bin\sqlplus.exe"
    exit 1
}
