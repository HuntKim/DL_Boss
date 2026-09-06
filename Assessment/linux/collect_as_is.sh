#!/bin/bash
# ==============================================================================
# AS-IS 서버 정보 수집 스크립트 (Linux: RHEL / Ubuntu 공용)
# ==============================================================================
# 목적: B Cloud 베어메탈 -> A Cloud VM 마이그레이션 "단계 1" 수집 스크립트.
#   AS-IS 서버에서 읽기 전용으로 실행하며, 아무 것도 변경/설치하지 않는다.
#   수집 항목:
#     1) 계정/그룹 정보
#     2) OS 파라미터(sysctl, limits 등), 크론탭 등 서버 설정 값
#     3) Storage 정보 (볼륨/파티션 구성)
#     4) SW 설치 정보/버전
#
# 사용법:
#   sudo ./collect_as_is.sh [출력_디렉토리]
#   (기본 출력_디렉토리: /tmp/as_is_assessment)
#   root 권한 없이도 실행은 가능하지만, 다른 계정의 crontab 조회 등
#   일부 항목은 권한이 있어야 정상적으로 수집된다.
#
# 출력물은 os-setup-main 쪽 TO-BE 자동화(계정 생성 Linux_user_gen.txt,
# SW 매핑 sw_mapping_linux.txt 등)에서 그대로 참고/병합할 수 있도록
# 최대한 같은 컬럼/구분자 규칙으로 draft 파일을 같이 생성한다.
# 단, draft는 초안일 뿐이며 반드시 사람이 검토 후 실제 설정 파일에
# 반영해야 한다(자동 반영 아님).
# ==============================================================================

set -u

OUTPUT_DIR="${1:-/tmp/as_is_assessment}"
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_OUT_DIR="${OUTPUT_DIR}/${HOSTNAME_SHORT}"
mkdir -p "$HOST_OUT_DIR"

# ------------------------------------------------------------------------------
# 로그 함수 (os-setup-main/linus/config/linux_common.env 의 log_info 등과
# 동일한 스타일로 통일 - 이 스크립트는 AS-IS 서버에 독립 실행되므로
# 해당 env 파일을 source하지 않고 자체 정의한다)
# ------------------------------------------------------------------------------
log_info()    { echo "[INFO]    $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn()    { echo "[WARN]    $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error()   { echo "[ERROR]   $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

if [ "$(id -u)" -ne 0 ]; then
    log_warn "root 권한이 아닙니다. 다른 계정의 crontab, 일부 storage 정보 등은 조회가 제한될 수 있습니다."
fi

log_info "=== AS-IS 서버 정보 수집 시작: ${HOSTNAME_SHORT} ==="
log_info "출력 경로: ${HOST_OUT_DIR}"

# ==============================================================================
# 0. OS 계열 감지 (RHEL 계열 vs Ubuntu/Debian 계열)
# ==============================================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="${NAME:-Unknown}"
    OS_VERSION="${VERSION_ID:-Unknown}"
elif [ -f /etc/redhat-release ]; then
    OS_NAME=$(cat /etc/redhat-release)
    OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
else
    OS_NAME="Unknown"
    OS_VERSION="Unknown"
fi

if command -v rpm >/dev/null 2>&1; then
    PKG_FAMILY="rpm"
elif command -v dpkg >/dev/null 2>&1; then
    PKG_FAMILY="deb"
else
    PKG_FAMILY="unknown"
fi

log_info "감지된 OS: ${OS_NAME} ${OS_VERSION} (패키지 계열: ${PKG_FAMILY})"

# ==============================================================================
# 1. 계정/그룹 정보 수집
#   (a) accounts_raw_*.txt   : getent passwd/group 전체 원본 (감사/참고용)
#   (b) accounts_gen_draft.env : os-setup/linux/config/os_env/<hostname>.env가
#       그대로 기대하는 HOST_GROUPS/HOST_ACCOUNTS bash 배열 형식으로 생성한
#       "실제 사용자/서비스 계정으로 추정되는" 계정만 추린 draft (CSV 아님 -
#       그대로 os_env/<hostname>.env에 복사해 붙여넣을 수 있게 함).
#       판별 기준: 로그인 쉘이 nologin류가 아닌 "실사용 쉘"인 계정만 포함하고
#       root는 제외한다 (TO-BE 서버에도 root는 기본 존재하므로).
#       표준 시스템 계정(bin, daemon, sshd 등)은 보통 쉘이 nologin이라
#       이 기준으로 자연히 걸러진다.
# ==============================================================================
log_info "[1/4] 계정/그룹 정보 수집 중..."

getent passwd > "${HOST_OUT_DIR}/accounts_raw_passwd.txt"
getent group  > "${HOST_OUT_DIR}/accounts_raw_group.txt"

ACCOUNTS_ENV_DRAFT="${HOST_OUT_DIR}/accounts_gen_draft.env"
REAL_SHELLS_REGEX='^/(usr/)?(bin|sbin)/(bash|sh|csh|ksh|tcsh|zsh|dash)$'

declare -A seen_groups=()
group_lines=()
account_lines=()

while IFS=: read -r uname _ uid gid _ home shell; do
    [ "$uname" = "root" ] && continue
    echo "$shell" | grep -qE "$REAL_SHELLS_REGEX" || continue

    primary_group=$(getent group "$gid" 2>/dev/null | cut -d: -f1)
    [ -z "$primary_group" ] && primary_group="$gid"

    if [ -z "${seen_groups[$primary_group]:-}" ]; then
        group_lines+=("    \"${primary_group}:${gid}\"")
        seen_groups["$primary_group"]=1
    fi

    # 1차 그룹을 제외한 나머지 소속 그룹을 ';' 로 연결 (os-setup의
    # HOST_ACCOUNTS 추가그룹 필드 규칙과 동일한 구분자)
    sec_groups=$(id -Gn "$uname" 2>/dev/null | tr ' ' '\n' | grep -vx "$primary_group")
    sec_groups_semicolon=$(echo "$sec_groups" | paste -sd';' - 2>/dev/null)

    while IFS= read -r sg; do
        [ -z "$sg" ] && continue
        if [ -z "${seen_groups[$sg]:-}" ]; then
            sg_gid=$(getent group "$sg" 2>/dev/null | cut -d: -f3)
            group_lines+=("    \"${sg}:${sg_gid}\"")
            seen_groups["$sg"]=1
        fi
    done <<< "$sec_groups"

    account_lines+=("    \"${uname}:${primary_group}:${uid}:${home}:${shell}:${sec_groups_semicolon}\"")
done < "${HOST_OUT_DIR}/accounts_raw_passwd.txt"

{
    echo "# os-setup/linux/config/os_env/${HOSTNAME_SHORT}.env 에 그대로 붙여넣을 draft"
    echo "# 형식: \"그룹명:GID\""
    echo "HOST_GROUPS=("
    if [ "${#group_lines[@]}" -gt 0 ]; then printf '%s\n' "${group_lines[@]}"; fi
    echo ")"
    echo
    echo "# 형식: \"계정명:1차그룹:UID:홈디렉터리:로그인쉘:추가그룹(세미콜론구분,옵션)\""
    echo "HOST_ACCOUNTS=("
    if [ "${#account_lines[@]}" -gt 0 ]; then printf '%s\n' "${account_lines[@]}"; fi
    echo ")"
} > "$ACCOUNTS_ENV_DRAFT"

log_success "계정/그룹 수집 완료: ${ACCOUNTS_ENV_DRAFT} (참고 원본: accounts_raw_passwd.txt/accounts_raw_group.txt)"

# ==============================================================================
# 2. OS 파라미터 / 크론탭 등 서버 설정 값 수집
# ==============================================================================
log_info "[2/4] OS 파라미터 / 크론탭 수집 중..."

OS_PARAM_FILE="${HOST_OUT_DIR}/os_parameters.txt"
{
    echo "===== hostnamectl / uname ====="
    hostnamectl 2>/dev/null || { hostname; uname -a; }
    echo
    echo "===== Timezone ====="
    timedatectl 2>/dev/null || { cat /etc/timezone 2>/dev/null; date +%Z; }
    echo
    echo "===== SELinux 상태 ====="
    getenforce 2>/dev/null || echo "(getenforce 없음: SELinux 미설치 또는 Ubuntu 등)"
    echo
    echo "===== sysctl -a (커널 파라미터 전체) ====="
    sysctl -a 2>/dev/null
    echo
    echo "===== /etc/security/limits.conf ====="
    cat /etc/security/limits.conf 2>/dev/null
    echo "----- /etc/security/limits.d/*.conf -----"
    cat /etc/security/limits.d/*.conf 2>/dev/null
    echo
    echo "===== 네트워크 인터페이스 (ip addr) ====="
    ip addr show 2>/dev/null
    echo
    echo "===== 기본 라우트 ====="
    ip route show default 2>/dev/null
    echo
    echo "===== /etc/resolv.conf ====="
    cat /etc/resolv.conf 2>/dev/null
    echo
    echo "===== /etc/hosts ====="
    cat /etc/hosts 2>/dev/null
} > "$OS_PARAM_FILE" 2>&1

CRON_FILE="${HOST_OUT_DIR}/crontabs.txt"
{
    echo "===== /etc/crontab ====="
    cat /etc/crontab 2>/dev/null
    echo
    echo "===== /etc/cron.d/* ====="
    cat /etc/cron.d/* 2>/dev/null
    echo
    echo "===== 계정별 crontab (내용이 있는 계정만 표시) ====="
    while IFS=: read -r uname _; do
        c=$(crontab -u "$uname" -l 2>/dev/null)
        if [ -n "$c" ]; then
            echo "--- $uname ---"
            echo "$c"
            echo
        fi
    done < "${HOST_OUT_DIR}/accounts_raw_passwd.txt"
} > "$CRON_FILE" 2>&1

log_success "OS 파라미터/크론탭 수집 완료: ${OS_PARAM_FILE}, ${CRON_FILE}"

# ==============================================================================
# 3. Storage 정보 수집 (볼륨/파티션 구성)
#   (a) storage.txt : df/lsblk/blkid/fstab/LVM 원본
#   (b) filesystem_gen_draft.env : os-setup/linux/config/os_env/<hostname>.env가
#       그대로 기대하는 HOST_FILESYSTEMS(스토리지)/HOST_DIR_PERMISSIONS
#       (디렉터리 권한) bash 배열 형식으로 생성한 draft (CSV 아님). os-setup은
#       스토리지 구성과 디렉터리 권한을 별개 모듈로 다루므로 이 둘을
#       나눠서 출력한다.
#       기본 OS 마운트(/, /boot, /var, /tmp, /home 등)는 제외하고
#       "업무용으로 별도 구성된" 마운트포인트만 추출한다.
#       VG명은 LVM 조회로 추정하며, LVM이 아니거나 추정 실패 시 appvg로
#       표시하니 반드시 사람이 검토 후 사용할 것.
# ==============================================================================
log_info "[3/4] Storage 정보 수집 중..."

STORAGE_FILE="${HOST_OUT_DIR}/storage.txt"
{
    echo "===== df -hT ====="
    df -hT 2>/dev/null
    echo
    echo "===== lsblk -f ====="
    lsblk -f 2>/dev/null
    echo
    echo "===== blkid ====="
    blkid 2>/dev/null
    echo
    echo "===== /etc/fstab ====="
    cat /etc/fstab 2>/dev/null
    echo
    if command -v pvs >/dev/null 2>&1; then
        echo "===== LVM: pvs ====="; pvs 2>/dev/null
        echo "===== LVM: vgs ====="; vgs 2>/dev/null
        echo "===== LVM: lvs ====="; lvs 2>/dev/null
    else
        echo "(LVM 도구(pvs/vgs/lvs) 없음)"
    fi
} > "$STORAGE_FILE" 2>&1

STORAGE_DRAFT="${HOST_OUT_DIR}/filesystem_gen_draft.env"
DEFAULT_MOUNTS_REGEX='^(/|/boot|/boot/efi|/var|/var/log|/var/log/audit|/var/tmp|/tmp|/home|/usr|/opt)$'
DEFAULT_VG="appvg"

fs_lines=()
perm_lines=()

while read -r mnt; do
    [ -z "$mnt" ] && continue
    echo "$mnt" | grep -qE "$DEFAULT_MOUNTS_REGEX" && continue

    size_gb=$(df -BG --output=size "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
    [ -z "$size_gb" ] && size_gb=0
    owner=$(stat -c '%U' "$mnt" 2>/dev/null)
    group=$(stat -c '%G' "$mnt" 2>/dev/null)
    perm=$(stat -c '%a' "$mnt" 2>/dev/null)

    vg="$DEFAULT_VG"
    if command -v lvs >/dev/null 2>&1; then
        src=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null)
        if [ -n "$src" ]; then
            actual_vg=$(lvs --noheadings -o vg_name "$src" 2>/dev/null | tr -d ' ')
            [ -n "$actual_vg" ] && vg="$actual_vg"
        fi
    fi

    fs_lines+=("    \"${mnt}:${size_gb}:${vg}\"")
    perm_lines+=("    \"${mnt}:${owner}:${group}:${perm}\"")
done < <(findmnt -rn -o TARGET -t xfs,ext4,ext3,ext2,btrfs 2>/dev/null)

{
    echo "# os-setup/linux/config/os_env/${HOSTNAME_SHORT}.env 에 그대로 붙여넣을 draft"
    echo "# 형식: \"마운트포인트:크기(GB):VG명\""
    echo "HOST_FILESYSTEMS=("
    if [ "${#fs_lines[@]}" -gt 0 ]; then printf '%s\n' "${fs_lines[@]}"; fi
    echo ")"
    echo
    echo "# 형식: \"경로:소유자:그룹:권한(octal)\""
    echo "HOST_DIR_PERMISSIONS=("
    if [ "${#perm_lines[@]}" -gt 0 ]; then printf '%s\n' "${perm_lines[@]}"; fi
    echo ")"
    if [ "${#fs_lines[@]}" -eq 0 ]; then
        echo
        echo "# 기본 OS 마운트 외 별도 구성된 마운트포인트가 발견되지 않았습니다."
    fi
} > "$STORAGE_DRAFT"

log_success "Storage 정보 수집 완료: ${STORAGE_FILE}, ${STORAGE_DRAFT}"

# ==============================================================================
# 4. SW 설치 정보 / 버전 수집
#   (a) sw_packages_raw.txt : 설치된 패키지 전체 목록 (감사/수동 확인용)
#   (b) sw_mapping_draft.txt : sw_mapping_linux.txt 와 동일한
#       "hostname:sw종류_버전_비트,..." 형식으로, 이 프로젝트가 이미
#       자동화 대상으로 다루는 JDK(OpenJDK/Oracle JDK)와 Oracle Client만
#       자동 인식해서 채운다. 그 외 일반 패키지(pkg_ 접두사 대상)는
#       AS-IS에 뭐가 깔려 있는지와 TO-BE에 실제로 뭐가 필요한지가 다를 수
#       있어 자동으로 옮기지 않는다 - sw_packages_raw.txt를 참고해
#       사람이 직접 pkg_* 항목을 판단/추가해야 한다.
# ==============================================================================
log_info "[4/4] SW 설치 정보 / 버전 수집 중..."

SW_RAW_FILE="${HOST_OUT_DIR}/sw_packages_raw.txt"
if [ "$PKG_FAMILY" = "rpm" ]; then
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' 2>/dev/null | sort > "$SW_RAW_FILE"
elif [ "$PKG_FAMILY" = "deb" ]; then
    dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null | sort > "$SW_RAW_FILE"
else
    echo "(패키지 목록 조회 불가: 알 수 없는 패키지 계열)" > "$SW_RAW_FILE"
fi

sw_entries=()

# --- OpenJDK 탐지 (RHEL: rpm 패키지명 기준) ---
if [ "$PKG_FAMILY" = "rpm" ]; then
    while read -r pkgname; do
        [ -z "$pkgname" ] && continue
        full_ver=$(rpm -q --qf '%{VERSION}\n' "$pkgname" 2>/dev/null)
        arch=$(rpm -q --qf '%{ARCH}\n' "$pkgname" 2>/dev/null)
        bits="64b"; [ "$arch" = "i686" ] && bits="32b"
        [ -n "$full_ver" ] && sw_entries+=("openjdk_${full_ver}_${bits}")
    done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null | grep -E '^java-.*-openjdk$')
fi

# --- Oracle JDK 탐지 (/usr/java 하위 실행파일 기준, 구/신 패키지 구조 모두 대응) ---
if [ -d /usr/java ]; then
    for d in /usr/java/*/; do
        [ -d "$d" ] || continue
        base=$(basename "$d")
        [ "$base" = "default" ] && continue
        if [ -x "${d}bin/java" ]; then
            ver_str=$("${d}bin/java" -version 2>&1 | head -1 | grep -oE '"[0-9._]+"' | tr -d '"')
            [ -n "$ver_str" ] && sw_entries+=("oracle_jdk_${ver_str}_64b")
        fi
    done
fi

# --- Oracle Client 탐지 (oracle 계정의 ORACLE_HOME 기준) ---
if id oracle >/dev/null 2>&1; then
    oracle_home=$(su - oracle -c 'echo $ORACLE_HOME' 2>/dev/null | tail -1)
    if [ -n "$oracle_home" ] && [ -x "${oracle_home}/bin/sqlplus" ]; then
        cver=$("${oracle_home}/bin/sqlplus" -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$cver" ] && sw_entries+=("oracle_client_${cver}")
    fi
fi

SW_MAPPING_DRAFT="${HOST_OUT_DIR}/sw_mapping_draft.txt"
if [ ${#sw_entries[@]} -gt 0 ]; then
    (IFS=','; echo "${HOSTNAME_SHORT}:${sw_entries[*]}") > "$SW_MAPPING_DRAFT"
else
    echo "# 자동 인식된 JDK/Oracle Client가 없습니다. ${SW_RAW_FILE} 를 참고해 수동으로 확인하세요." > "$SW_MAPPING_DRAFT"
fi

log_success "SW 정보 수집 완료: ${SW_RAW_FILE}, ${SW_MAPPING_DRAFT}"

# ==============================================================================
# 5. 전송 편의를 위한 압축
# ==============================================================================
ARCHIVE_PATH="${OUTPUT_DIR}/${HOSTNAME_SHORT}_assessment_${TIMESTAMP}.tar.gz"
tar -czf "$ARCHIVE_PATH" -C "$OUTPUT_DIR" "$HOSTNAME_SHORT" 2>/dev/null

log_info "=================================================="
log_info " ★ AS-IS 정보 수집 완료: ${HOSTNAME_SHORT}"
log_info "  - 출력 디렉토리 : ${HOST_OUT_DIR}"
log_info "  - 압축 파일     : ${ARCHIVE_PATH}"
log_info "=================================================="
log_warn "draft 파일(accounts_gen_draft.env, filesystem_gen_draft.env, sw_mapping_draft.txt)은"
log_warn "반드시 검토 후 os-setup 쪽 설정 파일(config/os_env/, config/os_param_profiles/ 등)에 반영하세요."
