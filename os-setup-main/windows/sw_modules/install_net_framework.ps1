# sw_modules/install_net_framework.ps1
# ==============================================================================
# .NET Framework 통합 설치 모듈 (3.5 / 4.8 지원)
# - .NET Framework 3.5와 4.x는 공존 가능하므로, TargetVersion에 따라 해당 버전만 설치
# - TargetVersion: 3.5 → CON_URL에서 sxs.zip 다운로드 후 DISM 설치
# - TargetVersion: 4.8 → exe silent 설치
# ==============================================================================

param(
    [string]$TargetVersion,       # 설치 대상 버전 (예: 3.5, 4.8)
    [string]$HostConfigFile,      # 호스트 전용 설정 파일 경로
    [string]$CommonConfigFile     # 전역 공통 설정 파일 경로 ($global:CON_URL, 로그 함수 등)
)

# ------------------------------------------------------------------------------
# [1단계] 공통 설정 및 호스트 설정 로드
# ------------------------------------------------------------------------------
if (Test-Path $CommonConfigFile) { . $CommonConfigFile } else {
    Write-Host "[ERROR] 공통 설정 파일($CommonConfigFile)을 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

if (Test-Path $HostConfigFile) { . $HostConfigFile }

if ([string]::IsNullOrEmpty($TargetVersion)) {
    Log-Error "TargetVersion 파라미터가 지정되지 않았습니다."
    exit 1
}

$TargetVersion = $TargetVersion.Trim()
Log-Info "=== .NET Framework $TargetVersion 설치 모듈 시작 ==="

# ------------------------------------------------------------------------------
# [2단계] 버전별 설치 파일 준비
# ------------------------------------------------------------------------------
if ($TargetVersion -eq "3.5_64b") {
    # --- .NET Framework 3.5: CON_URL에서 sxs.zip 다운로드 후 DISM설치 ---
    $SxsZipFileName = "sxs.zip"
    $SxsZipUrl = "$($global:CON_URL)/windows/sxs/$SxsZipFileName"
    $SxsZipPath = "$($global:DOWN_PATH)\$SxsZipFileName"
    $LocalSxsPath = "C:\os-setup\temp\sxs"

    if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }

    # zip 파일 다운로드
    Log-Info "sxs.zip 다운로드 시작: $SxsZipUrl"
    try {
        Invoke-WebRequest -Uri $SxsZipUrl -OutFile $SxsZipPath -UseBasicParsing
        Log-Success "sxs.zip 다운로드 완료: $SxsZipPath"
    }
    catch {
        Log-Error "sxs.zip 다운로드 실패: $_"
        exit 1
    }

    # 기존 풀어둔 폴더 삭제 후 새로 풀기
    if (Test-Path $LocalSxsPath) { Remove-Item -Path $LocalSxsPath -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $LocalSxsPath | Out-Null

    Log-Info "sxs.zip 압축 해제 시작: $SxsZipPath -> $LocalSxsPath"
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($SxsZipPath, $LocalSxsPath)
        Log-Success "압축 해제 완료"
    }
    catch {
        Log-Error "압축 해제 실패: $_"
        if (Test-Path $LocalSxsPath) { Remove-Item -Path $LocalSxsPath -Recurse -Force -ErrorAction SilentlyContinue }
        exit 1
    }

    # 압축 파일 삭제
    Remove-Item -Path $SxsZipPath -Force -ErrorAction SilentlyContinue
    Log-Info "임시 zip 파일 정리 완료"

    # DISM 설치 실행
    Log-Info ".NET Framework 3.5 설치 진행 중..."
    
    dism /online /enable-feature /featureName:NetFx3 /All /LimitAccess /Source:$LocalSxsPath /NoRestart

    Log-Info "===== $LocalSxsPath"

    # 설치 확인
    $netfxState = dism /Online /Get-FeatureInfo /FeatureName:NetFX3 2>&1 | Select-String "State"
    Log-Info "NetFX3 상태: $netfxState"

    if ($netfxState -match "Enabled") {
        Log-Success ".NET Framework 3.5 설치 완료!"
    }
    elseif ($netfxState -match "Disabled") {
        Log-Warn ".NET Framework 3.5이(가) 아직 비활성화되어 있습니다."
        exit 1
    }
    else {
        Log-Info "상태: $netfxState"
    }

    # 로컬 폴더 정리
    if (Test-Path $LocalSxsPath) { Remove-Item -Path $LocalSxsPath -Recurse -Force -ErrorAction SilentlyContinue }
    Log-Info "임시 폴더 정리 완료"
}
elseif ($TargetVersion -eq "4.8_64b") {  
    # --- .NET Framework 4.8: standalone exe 또는 web exe 다운로드 및 설치 ---

    # 이미 4.8 이상 설치 여부 확인  
    $CurrentV4Version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Version  
    if ($CurrentV4Version -and ($CurrentV4Version -ge [Version]"4.8")) {  
        Log-Success ".NET Framework $CurrentV4Version 이 이미 설치되어 있어 설치를 건너뜁니다."  
        exit 0  
    }  
    Log-Info "현재 .NET Framework v4 버전: $CurrentV4Version (4.8 설치 필요)"

    if (-not (Test-Path $global:DOWN_PATH)) { New-Item -ItemType Directory -Force -Path $global:DOWN_PATH | Out-Null }

    # [수정 포인트] 시도할 파일 목록을 배열로 정의 (우선순위 순)  
    $CandidateFiles = @("ndp48-web.exe", "ndp48-x86-x64-allos-enu.exe")  
    $ExePath = $null  
    $FinalExeFileName = $null

    foreach ($FileName in $CandidateFiles) {  
        $ExeUrl = "$($global:CON_URL)/windows/Net_Framework_${TargetVersion}/$FileName"  
        $TempPath = "$($global:DOWN_PATH)\$FileName"  
          
        Log-Info "설치 파일 확인 및 다운로드 시도: $FileName"  
        try {  
            $wc = New-Object System.Net.WebClient  
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")  
            $wc.DownloadFile($ExeUrl, $TempPath)  
              
            # 다운로드에 성공했다면 파일명을 저장하고 루프 종료  
            $ExePath = $TempPath  
            $FinalExeFileName = $FileName  
            Log-Success "파일 다운로드 성공: $FinalExeFileName"  
            break   
        }  
        catch {  
            Log-Warn "파일을 찾을 수 없거나 다운로드 실패: $FileName (다음 파일 시도...)"  
            if (Test-Path $TempPath) { Remove-Item $TempPath -Force }  
        }  
    }

    # 모든 후보 파일을 시도했는데도 실패한 경우  
    if ($null -eq $ExePath) {  
        Log-Error "서버에서 .NET 4.8 설치 파일(enu 또는 web)을 모두 찾을 수 없습니다."  
        exit 1  
    }

    # Silent 설치  
    Log-Info ".NET Framework 4.8 Silent 설치 진행 중... ($FinalExeFileName)"  
    $process = Start-Process -FilePath $ExePath -ArgumentList "/q /norestart" -Wait -Verb runAs

    if ($process.ExitCode -eq 0) {  
        Log-Success ".NET Framework 4.8 설치 완료 (재부팅 불필요)"    
    }    
    elseif ($process.ExitCode -eq 3010) {    
        Log-Warn ".NET Framework 4.8 설치 완료 (재부팅 후 적용됨)"  
    }  
    else {  
        Log-Error ".NET Framework 4.8 설치 실패 (ExitCode: $($process.ExitCode))"    
        exit 1  
    }

    # 설치 파일 정리  
    if (Test-Path $ExePath) { Remove-Item -Path $ExePath -Force -ErrorAction SilentlyContinue }  
    Log-Info "임시 설치 파일 정리 완료"  
}  

else {
    # 지원하지 않는 버전
    Log-Error "지원하지 않거나 잘못된 .NET Framework 버전 지정입니다: '$TargetVersion'"
    exit 1
}

Log-Success ".NET Framework $TargetVersion 설치 모듈 완료"
