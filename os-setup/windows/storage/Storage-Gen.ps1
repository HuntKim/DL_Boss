# ==============================================================================
# storage/Storage-Gen.ps1
# 호스트 env($HostVolumes)를 기준으로 RAW(초기화되지 않은) 디스크를
# 순서대로 배정해 드라이브를 생성한다.
#
# 형식: "드라이브문자:크기(GB):볼륨레이블"
# 디렉터리 권한(NTFS ACL)은 여기서 다루지 않는다 - permission/ 모듈이
# 별도로 처리한다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Storage-Gen.ps1 [-Yes]
# ==============================================================================
param(
    [switch]$Yes
)

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path (Split-Path $CurrentDir -Parent) "config"
. (Join-Path $ConfigDir "common.ps1")

$Global:AssumeYes = $Yes.IsPresent
Require-Admin
Load-HostEnv

Log-Info "=== 스토리지 구성 시작: $($script:HostnameShort) ==="

if ($HostVolumes.Count -eq 0) {
    Log-Warn "HostVolumes가 정의되어 있지 않습니다. 구성할 스토리지가 없어 종료합니다."
    exit 0
}

# ==============================================================================
# 1. RAW 디스크 목록 확보 (디스크 번호 순으로 순서대로 배정)
# ==============================================================================
$RawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Sort-Object Number
Log-Info "가용 RAW 디스크: $($RawDisks.Count)개 ($(($RawDisks | ForEach-Object { $_.Number }) -join ', '))"

$Plan = New-Object System.Collections.Generic.List[PSCustomObject]
$Idx = 0

foreach ($volEntry in $HostVolumes) {
    $parts = $volEntry -split ':'
    if ($parts.Count -lt 3) { Log-Warn "형식이 잘못된 항목을 건너뜁니다: '$volEntry'"; continue }
    $driveLetter = $parts[0]
    $sizeGb = [int]$parts[1]
    $label = $parts[2]

    if (Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue) {
        Log-Info "드라이브 '${driveLetter}:'는 이미 존재합니다. 건너뜁니다."
        continue
    }

    if ($Idx -ge $RawDisks.Count) {
        Log-Error "배정할 RAW 디스크가 부족합니다 (필요: $($HostVolumes.Count)개, 가용: $($RawDisks.Count)개)"
        exit 1
    }
    $disk = $RawDisks[$Idx]
    $Idx++
    $Plan.Add([PSCustomObject]@{ DriveLetter = $driveLetter; Label = $label; DiskNumber = $disk.Number; SizeGb = $sizeGb })
}

if ($Plan.Count -eq 0) {
    Log-Info "새로 만들 드라이브가 없습니다(이미 전부 존재)."
    exit 0
}

# ==============================================================================
# 2. 확인 (디스크를 통째로 초기화하므로 반드시 확인)
# ==============================================================================
Log-Warn "아래 디스크를 초기화하고 새 드라이브를 생성합니다 (기존 데이터가 있다면 모두 삭제됩니다):"
foreach ($p in $Plan) {
    Log-Warn "  - 디스크 $($p.DiskNumber) -> $($p.DriveLetter): ($($p.Label), 요청 $($p.SizeGb)GB)"
}
Confirm-OrExit "진행하시겠습니까?"

# ==============================================================================
# 3. 디스크 초기화 + 파티션 + 포맷
# ==============================================================================
foreach ($p in $Plan) {
    try {
        Initialize-Disk -Number $p.DiskNumber -PartitionStyle GPT -ErrorAction Stop
        New-Partition -DiskNumber $p.DiskNumber -DriveLetter $p.DriveLetter -UseMaximumSize -ErrorAction Stop | Out-Null
        Format-Volume -DriveLetter $p.DriveLetter -FileSystem NTFS -NewFileSystemLabel $p.Label -Confirm:$false -ErrorAction Stop | Out-Null

        Add-ManifestRecord -ManifestName "created_volumes.txt" -Value "$($p.DriveLetter)|$($p.DiskNumber)"
        Log-Success "드라이브 생성 완료: $($p.DriveLetter): (디스크 $($p.DiskNumber), 레이블: $($p.Label))"
    } catch {
        Log-Error "드라이브 생성 실패: $($p.DriveLetter): ($($_.Exception.Message))"
        exit 1
    }
}

Log-Success "=== 스토리지 구성 완료: $($script:HostnameShort) ==="
