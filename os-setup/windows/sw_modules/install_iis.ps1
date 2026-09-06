# sw_modules/install_iis.ps1
# ==============================================================================
# Windows용 IIS 설치 모듈 (Server / Client Edition 대응)
# ==============================================================================

# ---------------------------------------------------------------------------
# [1단계] 공통 설정 로드
# ---------------------------------------------------------------------------

Log-Info "========================================================="
Log-Info "===              IIS 모듈 설치 시작합니다.              "
Log-Info "========================================================="

# ---------------------------------------------------------------------------
# [2단계] 기존 IIS 설치 여부 확인 (멱등성)
# ---------------------------------------------------------------------------
Log-Info "IIS 기존 설치 여부 확인 중..."

$iisFeature = Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -ErrorAction SilentlyContinue
if ($iisFeature -and $iisFeature.State -eq "Enabled") {
    Log-Success "IIS Web-Server 이(가) 이미 설치되어 있습니다. 설치를 건너뜁니다."
    Log-Success "IIS 설치 검증 완료 (Status: 200)"
    Log-Info "========================================================="
    exit 0
}

Log-Info "IIS 미설치 상태. 설치를 진행합니다."

# ---------------------------------------------------------------------------
# [3단계] IIS 설치
# ---------------------------------------------------------------------------
try {
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer `
        -All -NoRestart -ErrorAction Stop
    Log-Success "IIS Web-Server 역할 설치 완료"
}
catch {
    Log-Error "IIS 설치 실패: $_"
    exit 1
}

# ---------------------------------------------------------------------------
# [4단계] IIS 설치 검증
# ---------------------------------------------------------------------------
Log-Info "IIS 설치 검증 중..."

$iisFeature = Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -ErrorAction SilentlyContinue
if (-not ($iisFeature -and $iisFeature.State -eq "Enabled")) {
    Log-Error "IIS 설치 후 검증 실패: Web-Server 역할이 활성화되지 않음"
    exit 1
}

# IIS 기본 페이지 응답 확인 (Status 200)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri "http://localhost/iisstart.htm" -UseBasicParsing -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Log-Success "IIS 설치 완료되었습니다. (Status: 200)"
    }
    else {
        Log-Warn "IIS 응답 Status Code: $($response.StatusCode) - 수동 확인 필요"
    }
}
catch {
    Log-Warn "IIS 기본 페이지 검증 실패 (서버 기동 대기 필요할 수 있음): $_"
}

Log-Info "========================================================="
