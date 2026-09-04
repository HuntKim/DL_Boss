#!/bin/bash
# ==============================================================================
# 1. 환경 설정 및 전역 변수
# ==============================================================================

# 현재 실행 중인 스크립트의 절대 경로를 획득
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/Linux_user_gen.csv"
HOSTNAME=$(hostname -s)

DEFAULT_PASS="DSmes123!"
OS_MANAGED_PASS="cotsadm1!"

DRY_RUN=false

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# ------------------------------------------------------------------------------
# [함수] 로그 출력
# ------------------------------------------------------------------------------
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_msg="[$timestamp] [$level] $msg"

    echo -e "$log_msg"
}

# ------------------------------------------------------------------------------
# [함수] 명령어 실행 래퍼
# ------------------------------------------------------------------------------
run_cmd() {
    local cmd="$1"

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# ------------------------------------------------------------------------------
# [함수] 계정별 셸 환경 파일 생성 (개선: 셸 전용 파일만 생성)
# ------------------------------------------------------------------------------
setup_shell_env() {
    local user=$1
    local home=$2
    local uid=$3
    local gid=$4
    local shell=$5

    log "INFO" "  -> Cleaning & setting up environment for shell: $shell"

    # 혹시 복사되었을 수 있는 기존 skel 파일 및 불필요한 dotfile 정리
    run_cmd "rm -f $home/.bashrc $home/.bash_profile $home/.bash_logout $home/.cshrc $home/.tcshrc $home/.login $home/.kshrc $home/.profile $home/.zshrc"

    case "$shell" in
        *bash*)
            run_cmd "touch $home/.bash_profile $home/.bashrc $home/.bash_logout"
            run_cmd "echo 'export PS1=\"[\u@\h \W]\$ \"' > $home/.bash_profile"
            ;;
        *csh* | *tcsh*)
            run_cmd "echo 'set prompt = \"[%n@%m %~]# \"' > $home/.cshrc"
            run_cmd "echo 'set path = (/bin /usr/bin /usr/local/bin)' >> $home/.cshrc"
            run_cmd "touch $home/.login"
            ;;
        *ksh*)
            run_cmd "echo 'export PS1=\"[\$USER@\$(hostname -s) \$PWD]# \"' > $home/.profile"
            run_cmd "touch $home/.kshrc"
            ;;
        *zsh*)
            run_cmd "echo 'PROMPT=\"[%n@%m %~]%# \"' > $home/.zshrc"
            ;;
        *)
            run_cmd "touch $home/.profile"
            ;;
    esac

    run_cmd "chown -R $uid:$gid $home"
    run_cmd "chmod -R 755 $home"
}

# ------------------------------------------------------------------------------
# [함수] 계정 및 그룹 생성
# ------------------------------------------------------------------------------
create_user_full() {
    local user=$1
    local group=$2
    local uid=$3
    local gid=$4
    local home=$5
    local shell=$6

    shift 6
    local secondary_groups=("$@")

    log "INFO" ">>> Processing: $user (UID:$uid, GID:$gid, Home:$home, Shell:$shell)"

    # 1. 기본 그룹 생성 또는 기존 그룹 GID 변경
    if ! getent group "$group" > /dev/null; then
        run_cmd "groupadd -g $gid $group"
        log "INFO" "  -> Group [$group] created with GID $gid"
    else
        current_gid=$(getent group "$group" | cut -d: -f3)

        if [ "$current_gid" != "$gid" ]; then
            run_cmd "groupmod -g $gid $group"
            log "INFO" "  -> Group [$group] GID changed: $current_gid -> $gid"
        else
            log "INFO" "  -> Group [$group] already has GID $gid"
        fi
    fi

    # 2. 계정 생성 및 업데이트 (-k /dev/null 옵션으로 /etc/skel 복사 차단)
    if ! id "$user" > /dev/null 2>&1; then
        run_cmd "useradd -u $uid -g $gid -d $home -s $shell -k /dev/null -m $user"
        log "INFO" "  -> User [$user] created without skeleton files."
    else
        run_cmd "usermod -u $uid -g $gid -d $home -s $shell $user"
        log "INFO" "  -> User [$user] updated."
    fi

    # 2-1. 계정별 비밀번호 설정
    local final_pass=""

    if [ "$user" == "osmanaged" ]; then
        final_pass="$OS_MANAGED_PASS"
        log "INFO" "  -> Using specialized password for osmanaged"
    else
        final_pass="$DEFAULT_PASS"
    fi

    run_cmd "echo $user:$final_pass | chpasswd"
    log "INFO" "  -> Initial password set for [$user]"

    # 2-2. 최초 로그인 시 비밀번호 변경 강제
    # run_cmd "chage -d 0 $user"
    # log "INFO" "  -> Forced password change on first login for [$user]"

    # 3. 셸 전용 환경 설정
    setup_shell_env "$user" "$home" "$uid" "$gid" "$shell"

    # 4. 보조 그룹 추가
    for sgroup in "${secondary_groups[@]}"; do
        if [ -n "$sgroup" ]; then
            if ! getent group "$sgroup" > /dev/null; then
                run_cmd "groupadd $sgroup"
                log "WARN" "  -> Secondary group [$sgroup] created without explicit GID"
            fi

            run_cmd "usermod -aG $sgroup $user"
            log "INFO" "  -> Added to secondary group: $sgroup"
        fi
    done
}

# ==============================================================================
# 2. 실행 단계
# ==============================================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found."
    exit 1
fi

echo -e "\n===================================================="

if [ "$DRY_RUN" = true ]; then
    echo -e "\x1b[33m           [ !!! DRY-RUN MODE ACTIVE !!! ]\x1b[0m"
else
    echo "           [ 계정 생성 대상 서버 검증 ]"
fi

echo "===================================================="
echo " 현재 호스트명: $HOSTNAME"
echo "----------------------------------------------------"

if grep -q "^$HOSTNAME," "$CONFIG_FILE"; then
    echo -e "\x1b[32m[결과] CSV 파일에 $HOSTNAME 설정이 존재합니다.\x1b[0m"
else
    echo -e "\x1b[31m[결과] CSV 파일에 해당 호스트 정보가 없습니다.\x1b[0m"
    echo "===================================================="
    exit 1
fi

echo "===================================================="

read -p "진행하시겠습니까? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "작업을 취소했습니다."
    exit 0
fi

log "INFO" "Starting account deployment for $HOSTNAME... (DRY_RUN=$DRY_RUN)"

log "INFO" "Performing pre-deployment shell checks..."

USED_SHELLS=$(tail -n +2 "$CONFIG_FILE" | cut -d',' -f7 | sort -u)

for sh_path in $USED_SHELLS; do
    if [[ -n "$sh_path" && "$sh_path" == /* ]]; then
        if [ ! -x "$sh_path" ]; then
            log "WARN" "Shell $sh_path not found. Attempting to install..."

            if [ "$DRY_RUN" = false ]; then
                if command -v yum &> /dev/null; then
                    yum install -y tcsh zsh ksh &> /dev/null
                elif command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y tcsh zsh ksh &> /dev/null
                fi
            else
                log "DRY-RUN" "Would install required shells (tcsh, zsh, ksh)"
            fi
        fi
    fi
done

# CSV 순서:
# hostname,user,group,uid,gid,home,shell,sec_group(rest)
tail -n +2 "$CONFIG_FILE" | while IFS=',' read -r server user group uid gid home shell rest
do
    if [[ -z "$server" ]]; then
        continue
    fi

    if [ "$server" == "$HOSTNAME" ]; then
        IFS=',' read -ra SEC_GROUPS <<< "$rest"

        create_user_full \
            "$user" "$group" "$uid" "$gid" "$home" "$shell" \
            "${SEC_GROUPS[@]}"
    fi
done

# ------------------------------------------------------------------------------
# osmanaged 계정 후처리 설정 (DRY_RUN 지원)
# ------------------------------------------------------------------------------
if id "osmanaged" > /dev/null 2>&1 || [ "$DRY_RUN" = true ]; then
    log "INFO" "Applying post-configuration for osmanaged..."

    if ! grep -q "^osmanaged " /etc/sudoers 2>/dev/null; then
        run_cmd "echo 'osmanaged ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"
    else
        log "INFO" "  -> sudoers entry for osmanaged already exists."
    fi

    # 비밀번호 만료 기간 무제한 설정
    run_cmd "chage -M -1 osmanaged"
    # 최초 로그인 시 비밀번호 변경 강제 해제
    run_cmd "chage -d $(date +%Y-%m-%d) osmanaged"

    run_cmd "sudo -u osmanaged bash -c 'echo \"umask 037\" >> ~/.bash_profile'"
    run_cmd "sudo -u osmanaged bash -c 'echo \"umask 037\" >> ~/.bashrc'"
    run_cmd "sudo -u osmanaged bash -lc 'source ~/.bash_profile || source ~/.bashrc 2>/dev/null || true'"
fi

echo "--------------------------------------------------"
log "INFO" "Account deployment process finished for $HOSTNAME."
