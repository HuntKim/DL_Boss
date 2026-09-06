# ==============================================================================
# storage/Storage-Verify.ps1
# 호스트 env($HostVolumes)에 정의된 대로 드라이브가 구성되어 있는지
# 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
param()

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

Load-HostEnv

Log-Info "=== 스토리지 검증 시작: $($script:HostnameShort) ==="

if ($HostVolumes.Count -eq 0) {
    Log-Warn "HostVolumes가 정의되어 있지 않습니다. 검증할 항목이 없습니다."
    exit 0
}

$script:PassCount = 0
$script:FailCount = 0
function Check {
    param([string]$Description, [bool]$Ok)
    if ($Ok) { Log-Success "[PASS] $Description"; $script:PassCount++ }
    else { Log-Error "[FAIL] $Description"; $script:FailCount++ }
}

foreach ($volEntry in $HostVolumes) {
    $parts = $volEntry -split ':'
    if ($parts.Count -lt 3) { continue }
    $driveLetter = $parts[0]
    $sizeGb = [int]$parts[1]
    $label = $parts[2]

    $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
    if ($null -eq $vol) {
        Check "드라이브 '$($driveLetter):' 존재" $false
        continue
    }
    Check "드라이브 '$($driveLetter):' 존재" $true

    $actualSizeGb = [math]::Round($vol.Size / 1GB)
    $minExpected = [math]::Floor($sizeGb * 0.9)
    Check "'$($driveLetter):' 용량 (요청: ${sizeGb}GB, 실제: ${actualSizeGb}GB)" ($actualSizeGb -ge $minExpected)
    Check "'$($driveLetter):' 레이블 일치 (기대: $label, 실제: $($vol.FileSystemLabel))" ($vol.FileSystemLabel -eq $label)
}

Log-Info "=================================================="
Log-Info " 검증 결과: PASS $($script:PassCount) / FAIL $($script:FailCount)"
Log-Info "=================================================="

exit ([int]($script:FailCount -gt 0))
