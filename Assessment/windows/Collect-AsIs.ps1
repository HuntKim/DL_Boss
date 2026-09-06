# ==============================================================================
# AS-IS 서버 정보 수집 스크립트 (Windows Server)
# ==============================================================================
# 목적: B Cloud 베어메탈 -> A Cloud VM 마이그레이션 "단계 1" 수집 스크립트.
#   AS-IS 서버에서 읽기 전용으로 실행하며, 아무 것도 변경/설치하지 않는다.
#   수집 항목:
#     1) 계정/그룹 정보 (※ 비밀번호는 절대 수집/저장하지 않음)
#     2) OS 파라미터, 예약 작업(스케줄러) 등 서버 설정 값
#     3) Storage 정보 (볼륨/파티션 구성)
#     4) SW 설치 정보/버전
#
# 사용법:
#   powershell -ExecutionPolicy Bypass -File .\Collect-AsIs.ps1 [-OutputDir <경로>]
#   기본 출력 경로: C:\assessment_output
#   관리자 권한 권장(예약 작업/방화벽 등 일부 항목은 권한이 있어야 조회됨).
#
# 출력물은 os-setup/windows 쪽 TO-BE 자동화(계정 생성, SW 매핑
# sw_mapping_window.txt 등)에서 참고/병합할 수 있도록 draft 파일을 같이
# 생성한다. draft는 초안일 뿐이며 반드시 사람이 검토 후 반영해야 한다.
#
# ※ 보안: windows_user_gen.txt 예전 버전에 평문 비밀번호가 커밋되어 있던
#   문제가 있었음(별도 삭제 및 회전 조치됨). 이 스크립트는 그 문제를
#   반복하지 않도록 계정의 비밀번호는 어떤 형태로도 조회/저장하지 않는다.
#   TO-BE 계정 생성 시에는 반드시 새 임시 비밀번호를 별도 채널로 발급할 것.
# ==============================================================================

param(
    [string]$OutputDir = "C:\assessment_output"
)

function Get-TimeStamp { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
function Log-Info    ([string]$msg) { Write-Host "[INFO]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Cyan }
function Log-Warn    ([string]$msg) { Write-Host "[WARN]    $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Yellow }
function Log-Error   ([string]$msg) { Write-Host "[ERROR]   $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Red }
function Log-Success ([string]$msg) { Write-Host "[SUCCESS] $(Get-TimeStamp) - [$env:COMPUTERNAME] $msg" -ForegroundColor Green }

$Hostname   = $env:COMPUTERNAME
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$HostOutDir = Join-Path $OutputDir $Hostname
New-Item -ItemType Directory -Force -Path $HostOutDir | Out-Null

Log-Info "=== AS-IS 서버 정보 수집 시작: $Hostname ==="
Log-Info "출력 경로: $HostOutDir"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $IsAdmin) {
    Log-Warn "관리자 권한으로 실행되지 않았습니다. 예약 작업/방화벽 등 일부 항목 조회가 제한될 수 있습니다."
}

# ==============================================================================
# 1. 계정/그룹 정보 (비밀번호는 절대 수집하지 않음)
#   accounts_raw.txt : Get-LocalUser/Get-LocalGroup 원본 (감사/참고용)
#   $HostGroups/$HostAccounts 배열은 이 단계에서 만들어서 마지막에
#   os_env_draft.ps1 하나로 (스토리지/권한 배열과 함께) 합쳐서 출력한다.
#   활성화된 "실제 업무용" 계정만 추린다.
#   기본 내장 계정(Administrator/Guest/DefaultAccount/WDAGUtilityAccount)과
#   비활성화된 계정은 제외한다. 그룹도 내장(Administrators/Users 등)은
#   제외하고 커스텀 그룹만 $HostGroups에 담는다(내장 그룹은 SID가
#   S-1-5-32-* 패턴이라는 점으로 판별 - 그룹명은 로캘에 따라 달라질 수
#   있어 이름 대신 SID로 구분함). 비밀번호 필드는 두지 않는다 - TO-BE
#   생성 시 Account-Gen.ps1이 임시 비밀번호를 자동 생성한다.
# ==============================================================================
Log-Info "[1/4] 로컬 계정/그룹 정보 수집 중..."

$AccountsRaw = Join-Path $HostOutDir "accounts_raw.txt"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("===== Get-LocalUser =====")
Get-LocalUser | Format-Table Name, Enabled, Description, PasswordExpires, LastLogon -AutoSize | Out-String | ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine("===== Get-LocalGroup =====")
Get-LocalGroup | Format-Table Name, Description -AutoSize | Out-String | ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine("===== 그룹별 멤버 =====")
foreach ($grp in Get-LocalGroup) {
    [void]$sb.AppendLine("--- $($grp.Name) ---")
    try {
        $members = Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop | Select-Object -ExpandProperty Name
        if ($members) { $members | ForEach-Object { [void]$sb.AppendLine($_) } }
        else { [void]$sb.AppendLine("(멤버 없음)") }
    } catch {
        [void]$sb.AppendLine("(조회 실패: $($_.Exception.Message))")
    }
}
$sb.ToString() | Out-File -FilePath $AccountsRaw -Encoding UTF8

$builtinNames = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')

# 내장 로컬 그룹은 SID가 S-1-5-32-* 패턴(BUILTIN 도메인)을 따른다.
$customGroups = Get-LocalGroup | Where-Object { $_.SID.Value -notlike "S-1-5-32-*" }
$groupLines = New-Object System.Collections.Generic.List[string]
foreach ($g in $customGroups) {
    $groupLines.Add("    `"$($g.Name)`"")
}

$accountLines = New-Object System.Collections.Generic.List[string]
foreach ($u in (Get-LocalUser | Where-Object { $builtinNames -notcontains $_.Name -and $_.Enabled })) {
    $memberOf = @()
    foreach ($grp in Get-LocalGroup) {
        try {
            $isMember = Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop |
                Where-Object { $_.Name -like "*\$($u.Name)" }
            if ($isMember) { $memberOf += $grp.Name }
        } catch { }
    }
    $groupsFormatted = ($memberOf | ForEach-Object { "`"$_`"" }) -join ', '
    $accountLines.Add("    @{ User = `"$($u.Name)`"; Groups = @($groupsFormatted) }")
}

Log-Success "계정/그룹 수집 완료 (계정 $($accountLines.Count)건, 그룹 $($groupLines.Count)건 - 원본: $AccountsRaw)"

# ==============================================================================
# 2. OS 파라미터 / 예약 작업 등 서버 설정 값
# ==============================================================================
Log-Info "[2/4] OS 파라미터 / 예약 작업 수집 중..."

$OsParamFile = Join-Path $HostOutDir "os_parameters.txt"
$sb2 = New-Object System.Text.StringBuilder
[void]$sb2.AppendLine("===== systeminfo =====")
[void]$sb2.AppendLine((systeminfo | Out-String))
[void]$sb2.AppendLine("===== 시간대 (Get-TimeZone) =====")
[void]$sb2.AppendLine((Get-TimeZone | Format-List | Out-String))
[void]$sb2.AppendLine("===== 시스템 환경 변수 =====")
[void]$sb2.AppendLine((Get-ChildItem Env: | Format-Table -AutoSize | Out-String))
[void]$sb2.AppendLine("===== 방화벽 프로파일 상태 =====")
try { [void]$sb2.AppendLine((Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize | Out-String)) } catch { [void]$sb2.AppendLine("(조회 실패: $($_.Exception.Message))") }
[void]$sb2.AppendLine("===== 네트워크 어댑터 구성 =====")
try { [void]$sb2.AppendLine((Get-NetIPConfiguration | Format-List | Out-String)) } catch { [void]$sb2.AppendLine("(조회 실패: $($_.Exception.Message))") }
$sb2.ToString() | Out-File -FilePath $OsParamFile -Encoding UTF8

$TaskFile = Join-Path $HostOutDir "scheduled_tasks.txt"
try {
    Get-ScheduledTask | Where-Object { $_.TaskPath -notlike "\Microsoft*" } |
        Select-Object TaskName, TaskPath, State |
        Format-Table -AutoSize | Out-String | Out-File -FilePath $TaskFile -Encoding UTF8
} catch {
    "예약 작업 조회 실패: $($_.Exception.Message)" | Out-File -FilePath $TaskFile -Encoding UTF8
}

Log-Success "OS 파라미터/예약작업 수집 완료: $OsParamFile, $TaskFile"

# ==============================================================================
# 3. Storage 정보 수집 (볼륨/파티션 구성)
#   storage.txt : Get-Volume/Get-Partition/Get-Disk 원본
#   $HostVolumes 배열은 이 단계에서 만들어서 마지막에 os_env_draft.ps1
#   하나로 (계정 배열과 함께) 합쳐서 출력한다. OS가 설치된 시스템 드라이브
#   (보통 C:)와 이름 없는 특수 볼륨(예약/복구 파티션 등)은 제외한다.
# ==============================================================================
Log-Info "[3/4] Storage 정보 수집 중..."

$StorageFile = Join-Path $HostOutDir "storage.txt"
$sb3 = New-Object System.Text.StringBuilder
[void]$sb3.AppendLine("===== Get-Volume =====")
[void]$sb3.AppendLine((Get-Volume | Format-Table -AutoSize | Out-String))
[void]$sb3.AppendLine("===== Get-Partition =====")
try { [void]$sb3.AppendLine((Get-Partition | Format-Table -AutoSize | Out-String)) } catch { [void]$sb3.AppendLine("(조회 실패: $($_.Exception.Message))") }
[void]$sb3.AppendLine("===== Get-Disk =====")
try { [void]$sb3.AppendLine((Get-Disk | Format-Table -AutoSize | Out-String)) } catch { [void]$sb3.AppendLine("(조회 실패: $($_.Exception.Message))") }
[void]$sb3.AppendLine("===== Get-PSDrive (파일시스템) =====")
[void]$sb3.AppendLine((Get-PSDrive -PSProvider FileSystem | Format-Table -AutoSize | Out-String))
$sb3.ToString() | Out-File -FilePath $StorageFile -Encoding UTF8

$systemDriveLetter = $env:SystemDrive.TrimEnd(':')
$volumeLines = New-Object System.Collections.Generic.List[string]
$dataVolumes = Get-Volume | Where-Object {
    $_.DriveLetter -and $_.DriveLetter -ne $systemDriveLetter -and $_.DriveType -eq 'Fixed'
}
foreach ($v in $dataVolumes) {
    $sizeGb = [math]::Round($v.Size / 1GB)
    $label = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { "DATA" }
    $volumeLines.Add("    `"$($v.DriveLetter):$($sizeGb):$($label)`"")
}

Log-Success "Storage 정보 수집 완료 (커스텀 드라이브 $($volumeLines.Count)건 - 원본: $StorageFile)"

# ==============================================================================
# 4. SW 설치 정보 / 버전 수집
#   (a) sw_packages_raw.txt : 레지스트리 Uninstall 키 기준 설치 SW 전체 목록
#   (b) sw_mapping_draft.txt : sw_mapping_window.txt 형식으로, IIS/JDK/
#       Oracle Client 등 이 프로젝트가 이미 자동화 대상으로 다루는 SW만
#       자동 인식해서 채운다. .NET Framework는 레지스트리 Release 번호만
#       확인 가능해 정확한 버전 문자열은 사람이 최종 확인해야 한다.
# ==============================================================================
Log-Info "[4/4] SW 설치 정보 / 버전 수집 중..."

$SwRawFile = Join-Path $HostOutDir "sw_packages_raw.txt"
$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher |
    Sort-Object DisplayName |
    Format-Table -AutoSize | Out-String | Out-File -FilePath $SwRawFile -Encoding UTF8

$swEntries = New-Object System.Collections.Generic.List[string]

# --- IIS ---
try {
    $iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction Stop
    if ($iisFeature.Installed) { $swEntries.Add("iis") }
} catch { }

# --- .NET Framework 4.x (레지스트리 Release 값만 확인, 정확한 버전은 수동 확인 필요) ---
try {
    $netFx4 = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop
    if ($netFx4.Release) {
        $swEntries.Add("Net_Framework_4.x_64b(Release=$($netFx4.Release)__수동확인필요)")
    }
} catch { }

# --- Oracle JDK / OpenJDK (JAVA_HOME 기준) ---
$javaHome = [System.Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if ($javaHome -and (Test-Path "$javaHome\bin\java.exe")) {
    try {
        $verOutput = (& "$javaHome\bin\java.exe" -version 2>&1 | Select-Object -First 1).ToString()
        $swEntries.Add("java_detected($verOutput,JAVA_HOME=$javaHome)__수동확인필요")
    } catch { }
}

# --- Oracle Client (ORACLE_HOME 기준) ---
$oracleHome = [System.Environment]::GetEnvironmentVariable('ORACLE_HOME', 'Machine')
if ($oracleHome -and (Test-Path "$oracleHome\bin\sqlplus.exe")) {
    $swEntries.Add("oracle_client_detected(ORACLE_HOME=$oracleHome)__버전은sqlplus_-v로수동확인")
}

$SwMappingDraft = Join-Path $HostOutDir "sw_mapping_draft.txt"
if ($swEntries.Count -gt 0) {
    "$($Hostname):$($swEntries -join ',')" | Out-File -FilePath $SwMappingDraft -Encoding UTF8
} else {
    "# 자동 인식된 SW가 없습니다. $SwRawFile 를 참고해 수동으로 확인하세요." | Out-File -FilePath $SwMappingDraft -Encoding UTF8
}

Log-Success "SW 정보 수집 완료: $SwRawFile, $SwMappingDraft"

# ==============================================================================
# 5. 계정/스토리지 draft를 하나의 os_env_draft.ps1 로 합쳐서 출력
#   os-setup/windows/config/os_env/<hostname>.ps1 이 그대로 기대하는
#   $HostGroups/$HostAccounts/$HostVolumes/$HostDirPermissions 배열을
#   전부 담은 단일 파일로 만든다 (CSV 아님). 검토 후 파일명을
#   <hostname>.ps1 로 바꿔서 config/os_env/ 아래에 그대로 두면 된다.
#   $HostDirPermissions(NTFS ACL)와 $HostOsParamProfile은 AS-IS 값만으로
#   자동 판단하기 어려워(권한 조합이 복잡하거나, 여러 호스트를 묶어
#   프로파일명을 정하는 건 사람의 판단 영역) 빈 배열/값으로 남겨둔다.
# ==============================================================================
$OsEnvDraft = Join-Path $HostOutDir "os_env_draft.ps1"
$draftContent = New-Object System.Collections.Generic.List[string]
$draftContent.Add("# os-setup/windows/config/os_env/$Hostname.ps1 후보 - 검토 후")
$draftContent.Add("# 이 파일명을 $Hostname.ps1 로 바꿔서 config/os_env/ 아래에 두면 된다.")
$draftContent.Add("# 비밀번호는 채워져 있지 않음 - 새로 생성되는 모든 계정에 공통 적용할")
$draftContent.Add("# 초기 비밀번호를 아래 HostInitialPassword에 직접 입력해야 함")
$draftContent.Add("")
$draftContent.Add("`$HostGroups = @(")
$draftContent.AddRange($groupLines)
$draftContent.Add(")")
$draftContent.Add("")
$draftContent.Add("`$HostAccounts = @(")
$draftContent.AddRange($accountLines)
$draftContent.Add(")")
$draftContent.Add("")
$draftContent.Add("# TODO: 새로 생성되는 모든 계정에 적용할 초기 비밀번호를 채우세요")
$draftContent.Add("# (Windows 계정 정책의 복잡도 요건을 만족해야 함, 다음 로그온 시 담당자가")
$draftContent.Add("#  즉시 변경하는 일회성 값 - config/os_env/ 는 git에 커밋되는 파일이므로")
$draftContent.Add("#  실제로 재사용하는 비밀번호를 넣으면 안 됨)")
$draftContent.Add("`$HostInitialPassword = `"`"")
$draftContent.Add("")
$draftContent.Add("`$HostVolumes = @(")
$draftContent.AddRange($volumeLines)
$draftContent.Add(")")
if ($volumeLines.Count -eq 0) {
    $draftContent.Add("# (시스템 드라이브 외 별도 구성된 드라이브가 발견되지 않았습니다)")
}
$draftContent.Add("")
$draftContent.Add("# TODO: NTFS 권한은 자동 판단하기 어려워 비워둠 - 형식: `"경로:계정또는그룹:권한수준`"")
$draftContent.Add("# (FullControl/Modify/ReadAndExecute 중 하나)")
$draftContent.Add("`$HostDirPermissions = @(")
$draftContent.Add(")")
$draftContent.Add("")
$draftContent.Add("# TODO: config/os_param_profiles/ 아래 적절한 프로파일명을 정해서 채우세요")
$draftContent.Add("# (AS-IS 값만으로는 자동 판단할 수 없음 - os_parameters.txt 참고)")
$draftContent.Add("`$HostOsParamProfile = `"`"")
$draftContent | Out-File -FilePath $OsEnvDraft -Encoding UTF8

Log-Success "os_env_draft.ps1 생성 완료: $OsEnvDraft"

# ==============================================================================
# 6. 전송 편의를 위한 압축
# ==============================================================================
$ZipPath = Join-Path $OutputDir "$($Hostname)_assessment_$Timestamp.zip"
Compress-Archive -Path $HostOutDir -DestinationPath $ZipPath -Force

Log-Info "=================================================="
Log-Info " AS-IS 정보 수집 완료: $Hostname"
Log-Info "  - 출력 디렉토리 : $HostOutDir"
Log-Info "  - 압축 파일     : $ZipPath"
Log-Info "=================================================="
Log-Warn "os_env_draft.ps1 / sw_mapping_draft.txt 는 초안입니다."
Log-Warn "반드시 검토 후(특히 HostInitialPassword, HostDirPermissions, HostOsParamProfile 채우기) os-setup 쪽 설정 파일에 반영하세요."
