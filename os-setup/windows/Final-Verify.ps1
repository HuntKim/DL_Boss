# ==============================================================================
# os-setup/windows/Final-Verify.ps1
# 계정/그룹, OS 파라미터, 스토리지, 디렉터리 권한, SW 설치까지 os-setup으로
# 적용한 전체 내용을 실제 PowerShell 명령 결과 그대로 캡처해서 리포트
# 파일 하나로 남긴다.
#
# ※ Account-Verify.ps1 등의 [PASS]/[FAIL] 판정 스크립트와는 성격이 다르다 -
#   그쪽은 "값이 맞는지 자동 판정"이 목적이고, 이 스크립트는 "사람이
#   PowerShell에서 직접 확인하는 화면 그대로"를 최종 기록으로 남기는 것이
#   목적이다(예: 감사/인수인계용 증적). 각 항목 앞에 실제로 입력한 명령을
#   "PS> ..." 형태로 같이 남긴다.
# ==============================================================================
# 사용법: powershell -ExecutionPolicy Bypass -File .\Final-Verify.ps1
# ==============================================================================
param()

$Global:ScriptName = $MyInvocation.MyCommand.Name

$CurrentDir = $PSScriptRoot
$ConfigDir = Join-Path $CurrentDir "config"
. (Join-Path $ConfigDir "common.ps1")

Load-HostEnv

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportFile = Join-Path $LogDir "$($script:HostnameShort)_final_report_$Timestamp.txt"

$Report = New-Object System.Collections.Generic.List[string]
function Add-Report { param([string]$Line = "") $Report.Add($Line) }

Add-Report "================================================================"
Add-Report " os-setup 최종 확인 리포트 - $($script:HostnameShort)"
Add-Report " 생성 시각: $(Get-TimeStamp)"
Add-Report "================================================================"

# ==============================================================================
# 1. 계정/그룹 정보
#   ※ Windows 로컬 계정은 /etc/passwd 같은 순서가 있는 평문 파일이 아니라
#     SAM에 저장되므로 "tail"에 대응하는 개념이 없다. 대신 이번에 실제로
#     정의된 계정/그룹만 이름으로 콕 집어서 조회한다(가장 직접적인 대응).
# ==============================================================================
Add-Report ""
Add-Report "################################################################"
Add-Report "# 1. 계정/그룹 정보"
Add-Report "################################################################"

if ($HostAccounts.Count -gt 0) {
    $userNames = $HostAccounts | ForEach-Object { $_.User }
    Add-Report ""
    Add-Report "PS> Get-LocalUser -Name $($userNames -join ',')"
    Add-Report (Get-LocalUser -Name $userNames -ErrorAction SilentlyContinue | Format-Table Name, Enabled, Description -AutoSize | Out-String -Width 200).TrimEnd()
} else {
    Add-Report ""
    Add-Report "(HostAccounts 없음)"
}

if ($HostGroups.Count -gt 0) {
    Add-Report ""
    Add-Report "PS> Get-LocalGroup -Name $($HostGroups -join ',')"
    Add-Report (Get-LocalGroup -Name $HostGroups -ErrorAction SilentlyContinue | Format-Table Name, Description -AutoSize | Out-String -Width 200).TrimEnd()
}

foreach ($acct in $HostAccounts) {
    $uname = $acct.User
    Add-Report ""
    Add-Report "PS> Get-LocalGroupMember -Group <각 그룹> | Where Name -like '*\$uname'  (${uname}의 소속 그룹)"
    foreach ($grp in $acct.Groups) {
        try {
            $isMember = Get-LocalGroupMember -Group $grp -ErrorAction Stop | Where-Object { $_.Name -like "*\$uname" }
            if ($isMember) { Add-Report "  - $grp" }
        } catch { }
    }
}

# ==============================================================================
# 2. OS 파라미터 (레지스트리)
# ==============================================================================
Add-Report ""
Add-Report "################################################################"
Add-Report "# 2. OS 파라미터 (프로파일: $(if ($HostOsParamProfile) { $HostOsParamProfile } else { '미지정' }))"
Add-Report "################################################################"

function ConvertTo-PsRegPath {
    param([string]$KeyPath)
    return ($KeyPath `
        -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' `
        -replace '^HKEY_CURRENT_USER', 'HKCU:' `
        -replace '^HKEY_CLASSES_ROOT', 'HKCR:' `
        -replace '^HKEY_USERS', 'HKU:' `
        -replace '^HKEY_CURRENT_CONFIG', 'HKCC:')
}
function Get-RegFileEntries {
    param([string]$Path)
    $entries = New-Object System.Collections.Generic.List[PSCustomObject]
    $currentKey = $null
    foreach ($rawLine in Get-Content -Path $Path) {
        $line = $rawLine.Trim()
        if ($line -eq "" -or $line.StartsWith(";") -or $line -like "Windows Registry Editor*") { continue }
        if ($line -match '^\[(.+)\]$') { $currentKey = $matches[1]; continue }
        if ($null -eq $currentKey) { continue }
        if ($line -match '^"([^"]+)"=dword:([0-9a-fA-F]+)$') {
            $entries.Add([PSCustomObject]@{ KeyPath = $currentKey; ValueName = $matches[1] })
        } elseif ($line -match '^"([^"]+)"="(.*)"$') {
            $entries.Add([PSCustomObject]@{ KeyPath = $currentKey; ValueName = $matches[1] })
        }
    }
    return $entries
}

if ($HostOsParamProfile) {
    $ProfileFile = Join-Path (Join-Path $OsParamProfileDir $HostOsParamProfile) "registry.reg"
    if (Test-Path $ProfileFile) {
        $entries = Get-RegFileEntries -Path $ProfileFile
        foreach ($e in $entries) {
            $psPath = ConvertTo-PsRegPath -KeyPath $e.KeyPath
            Add-Report ""
            Add-Report "PS> Get-ItemProperty -Path '$psPath' -Name '$($e.ValueName)'"
            try {
                $val = (Get-ItemProperty -Path $psPath -Name $e.ValueName -ErrorAction Stop).($e.ValueName)
                Add-Report "$($e.ValueName) : $val"
            } catch {
                Add-Report "(값 없음 또는 조회 실패: $($_.Exception.Message))"
            }
        }
    } else {
        Add-Report ""
        Add-Report "(프로파일 파일 없음: $ProfileFile)"
    }
} else {
    Add-Report ""
    Add-Report "(HostOsParamProfile 미지정)"
}

# ==============================================================================
# 3. Storage
# ==============================================================================
Add-Report ""
Add-Report "################################################################"
Add-Report "# 3. Storage"
Add-Report "################################################################"

if ($HostVolumes.Count -gt 0) {
    foreach ($volEntry in $HostVolumes) {
        $parts = $volEntry -split ':'
        if ($parts.Count -lt 1) { continue }
        $driveLetter = $parts[0]
        Add-Report ""
        Add-Report "PS> Get-Volume -DriveLetter $driveLetter"
        try {
            Add-Report (Get-Volume -DriveLetter $driveLetter -ErrorAction Stop | Format-Table DriveLetter, FileSystemLabel, FileSystem, SizeRemaining, Size -AutoSize | Out-String -Width 200).TrimEnd()
        } catch {
            Add-Report "(조회 실패: $($_.Exception.Message))"
        }
    }
} else {
    Add-Report ""
    Add-Report "(HostVolumes 없음)"
}

# ==============================================================================
# 4. 디렉터리 권한
# ==============================================================================
Add-Report ""
Add-Report "################################################################"
Add-Report "# 4. 디렉터리 권한"
Add-Report "################################################################"

if ($HostDirPermissions.Count -gt 0) {
    foreach ($entry in $HostDirPermissions) {
        $parts = $entry -split ':'
        if ($parts.Count -lt 3) { continue }
        $path = ($parts[0..($parts.Count - 3)]) -join ':'
        Add-Report ""
        Add-Report "PS> Get-Acl '$path' | Format-List"
        if (Test-Path $path) {
            try {
                Add-Report (Get-Acl -Path $path -ErrorAction Stop | Format-List Path, Owner, Access | Out-String -Width 200).TrimEnd()
            } catch {
                Add-Report "(조회 실패: $($_.Exception.Message))"
            }
        } else {
            Add-Report "(경로 없음: $path)"
        }
    }
} else {
    Add-Report ""
    Add-Report "(HostDirPermissions 없음)"
}

# ==============================================================================
# 5. SW 설치 정보 (참고용 - sw_mapping_window.txt에 이 호스트가 있으면 그
#    항목만 보여준다. setup_sw.ps1/install_*.ps1 자체는 os-setup-main에서
#    그대로 가져온 부분이라 이 스크립트가 상세히 검증하지 않는다)
# ==============================================================================
Add-Report ""
Add-Report "################################################################"
Add-Report "# 5. SW 설치 정보"
Add-Report "################################################################"

$SwMappingFile = Join-Path $OsSetupWindowsConfigDir "sw_mapping_window.txt"
$SwLine = $null
if (Test-Path $SwMappingFile) {
    $SwLine = Get-Content $SwMappingFile | Where-Object { $_ -match "^$([regex]::Escape($script:HostnameShort)):" } | Select-Object -First 1
}
if ($SwLine) {
    Add-Report ""
    Add-Report "PS> Select-String '^$($script:HostnameShort):' sw_mapping_window.txt"
    Add-Report $SwLine
} else {
    Add-Report ""
    Add-Report "(sw_mapping_window.txt에 $($script:HostnameShort) 항목 없음)"
}

$JavaHome = [System.Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if ($JavaHome -and (Test-Path "$JavaHome\bin\java.exe")) {
    Add-Report ""
    Add-Report "PS> & '$JavaHome\bin\java.exe' -version"
    Add-Report ((& "$JavaHome\bin\java.exe" -version 2>&1) -join "`n")
}

$OracleHomeEnv = [System.Environment]::GetEnvironmentVariable('ORACLE_HOME', 'Machine')
if ($OracleHomeEnv -and (Test-Path "$OracleHomeEnv\bin\sqlplus.exe")) {
    Add-Report ""
    Add-Report "PS> & '$OracleHomeEnv\bin\sqlplus.exe' -v"
    Add-Report ((& "$OracleHomeEnv\bin\sqlplus.exe" -v 2>&1) -join "`n")
}

Add-Report ""
Add-Report "================================================================"
Add-Report " 리포트 종료: $ReportFile"
Add-Report "================================================================"

$Report | Out-File -FilePath $ReportFile -Encoding UTF8
$Report | ForEach-Object { Write-Host $_ }

Log-Success "최종 확인 리포트 생성 완료: $ReportFile"
