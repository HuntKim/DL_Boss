# ==============================================================================
# os-setup/windows/config/common.ps1
# 공통 로깅 함수 + 호스트별 env 파일 로더 + manifest(생성기록) 헬퍼
# ==============================================================================
# 이 프로젝트는 CSV를 사용하지 않는다. 호스트별 데이터(계정/그룹, 스토리지,
# 디렉터리 권한, OS 파라미터 값)는 모두
#   config/env/<hostname>.ps1
# 파일 안에 PowerShell 변수/배열로 직접 선언한다. 이 파일은 그 env 파일들이
# 공통으로 dot-source 하는 로깅 함수 + 헬퍼 모음이다.
# ==============================================================================

function Get-TimeStamp { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
function Log-Info    ([string]$msg) { $line = "[INFO]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg"; Write-Host $line -ForegroundColor Cyan; Add-Content -Path $Global:LogFile -Value $line -ErrorAction SilentlyContinue }
function Log-Warn    ([string]$msg) { $line = "[WARN]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg"; Write-Host $line -ForegroundColor Yellow; Add-Content -Path $Global:LogFile -Value $line -ErrorAction SilentlyContinue }
function Log-Error   ([string]$msg) { $line = "[ERROR]   $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg"; Write-Host $line -ForegroundColor Red; Add-Content -Path $Global:LogFile -Value $line -ErrorAction SilentlyContinue }
function Log-Success ([string]$msg) { $line = "[SUCCESS] $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg"; Write-Host $line -ForegroundColor Green; Add-Content -Path $Global:LogFile -Value $line -ErrorAction SilentlyContinue }

# ------------------------------------------------------------------------------
# 경로 계산
# ------------------------------------------------------------------------------
$Global:OsSetupWindowsConfigDir = $PSScriptRoot
$Global:OsSetupWindowsDir       = Split-Path $PSScriptRoot -Parent
$Global:EnvDir                  = Join-Path $OsSetupWindowsConfigDir "os_env"
$Global:OsParamProfileDir       = Join-Path $OsSetupWindowsConfigDir "os_param_profiles"
$Global:BackupDir               = "C:\os-setup-backup"   # rollback용 생성 기록(manifest) 저장 위치

# ※ sw_modules\setup_sw.ps1는 별도로 config\env\<hostname>.ps1 를 본다
#   (os-setup-main에서 그대로 가져온 것이라 그 경로를 바꾸지 않음). 처음엔
#   이 프로젝트도 같은 config\env\ 를 썼는데, 계정/스토리지 정의와 SW
#   모듈 오버라이드가 같은 파일(같은 이름)을 가리키게 되어 헷갈린다는
#   지적을 받아 os_env\ 로 분리함.

# ------------------------------------------------------------------------------
# 실행 로그 취합
#   이 호스트에서 어떤 스크립트가 언제 실행됐는지 한 곳(logs\<hostname>.log)
#   에서 이어서 볼 수 있도록, 모든 Log-Info/Log-Warn/Log-Error/Log-Success
#   호출이 화면 출력과 동시에 이 파일에도 누적 기록된다. PowerShell은
#   dot-source된 파일 안에서 "어느 최상위 스크립트가 실행 중인지"를
#   자동으로 알아내는 안전한 방법이 마땅치 않아, 각 최상위 스크립트가
#   dot-source 하기 전에 $Global:ScriptName 을 직접 지정해둔다(각 스크립트
#   상단에 이미 반영됨).
# ------------------------------------------------------------------------------
$Global:LogDir = Join-Path $OsSetupWindowsDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$Global:LogFile = Join-Path $LogDir "$($env:COMPUTERNAME).log"

$_scriptNameForLog = if ($Global:ScriptName) { $Global:ScriptName } else { "(알 수 없는 스크립트)" }
Add-Content -Path $LogFile -Value ""
Add-Content -Path $LogFile -Value "================================================================"
Add-Content -Path $LogFile -Value "[$(Get-TimeStamp)] 실행: $_scriptNameForLog (PID: $PID)"
Add-Content -Path $LogFile -Value "================================================================"

# ------------------------------------------------------------------------------
# 호스트별 env 파일 로드
#   config/os_env/<hostname>.ps1 가 없으면 명확히 에러로 중단한다.
# ------------------------------------------------------------------------------
function Load-HostEnv {
    $script:HostnameShort = $env:COMPUTERNAME
    $hostEnvFile = Join-Path $EnvDir "$($script:HostnameShort).ps1"

    if (-not (Test-Path $hostEnvFile)) {
        Log-Error "호스트 전용 env 파일이 없습니다: $hostEnvFile"
        Log-Error "이 호스트($($script:HostnameShort))에 대한 설정을 config/os_env/$($script:HostnameShort).ps1 에 먼저 정의해야 합니다."
        exit 1
    }

    # 호스트 env 파일이 일부 항목을 정의하지 않아도 이후 스크립트가
    # null 참조 에러 없이 "정의 안 됨"으로 처리할 수 있도록 기본값을
    # 먼저 채워둔다. 호스트 env 파일에 실제 정의가 있으면 아래 dot-source가
    # 덮어쓴다.
    $Global:HostGroups          = @()
    $Global:HostAccounts        = @()
    $Global:HostVolumes         = @()
    $Global:HostDirPermissions  = @()
    $Global:HostOsParamProfile  = ""

    . $hostEnvFile
    Log-Info "호스트 전용 env 로드 완료: $($script:HostnameShort).ps1"
}

# ------------------------------------------------------------------------------
# 공통 사전 점검
# ------------------------------------------------------------------------------
function Require-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (-not $isAdmin) {
        Log-Error "관리자 권한으로 실행해야 합니다."
        exit 1
    }
}

# 실행 확인 프롬프트 (-Yes 스위치로 건너뛸 수 있음)
function Confirm-OrExit {
    param([string]$Message)
    if ($Global:AssumeYes) { return }
    $confirm = Read-Host "$Message (y/n)"
    if ($confirm -ne "y") {
        Log-Warn "사용자가 취소했습니다."
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 생성 기록(manifest) 헬퍼
#   rollback 스크립트는 절대 HostGroups/HostAccounts(env 정의)를 직접
#   순회하며 되돌리면 안 된다 - env에는 "이미 존재해야 하는 내장 그룹"
#   (Administrators 등)처럼 우리가 만들지 않은 항목도 섞여 있어서, 그걸
#   그대로 삭제하면 시스템 내장 계정/그룹을 건드리는 사고가 날 수 있다
#   (Linux 쪽 개발 중 실제로 wheel 그룹이 삭제되는 사고를 테스트로 발견
#   해서 이 프로젝트 전체에 이 규칙을 적용함). 각 *-Gen.ps1 / *-Apply.ps1은
#   "실제로 자신이 생성/변경한 것"만 아래 manifest 파일에 기록하고,
#   rollback은 반드시 이 manifest만 근거로 되돌린다.
# ------------------------------------------------------------------------------
function Get-ManifestDir {
    $dir = Join-Path $BackupDir $script:HostnameShort
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    return $dir
}

function Add-ManifestRecord {
    param([string]$ManifestName, [string]$Value)
    $path = Join-Path (Get-ManifestDir) $ManifestName
    Add-Content -Path $path -Value $Value
}

function Get-ManifestRecords {
    param([string]$ManifestName)
    $path = Join-Path (Get-ManifestDir) $ManifestName
    if (Test-Path $path) {
        return Get-Content -Path $path | Where-Object { $_ -ne "" }
    }
    return @()
}

function Remove-Manifest {
    param([string]$ManifestName)
    $path = Join-Path (Get-ManifestDir) $ManifestName
    Remove-Item -Path $path -ErrorAction SilentlyContinue
}
