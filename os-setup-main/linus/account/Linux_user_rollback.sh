#!/bin/bash

# ==============================================================================  
# 계정 생성 원복(Rollback) 스크립트 - 확인 단계 추가 버전  
# ==============================================================================

# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/Linux_user_gen.csv"  
HOSTNAME=$(hostname -s)

if [[ $EUID -ne 0 ]]; then  
    echo "Error: This script must be run as root"  
    exit 1  
fi

log() {  
    local level=$1  
    local msg=$2  
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")  
    echo -e "[$timestamp] [$level] $msg"  
}

# ------------------------------------------------------------------------------  
# 1. 설정값 추출 및 삭제 대상 리스트 작성  
# ------------------------------------------------------------------------------  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo "Error: Config file $CONFIG_FILE not found."  
    exit 1  
fi

if ! grep -q "^$HOSTNAME," "$CONFIG_FILE"; then  
    echo "No config for $HOSTNAME found in CSV. Nothing to rollback."  
    exit 0  
fi

# 삭제 대상 리스트를 저장할 배열  
DELETE_LIST=()

# CSV에서 현재 서버의 사용자 정보만 추출하여 리스트 생성  
while IFS=',' read -r server user group uid gid home shell rest  
do  
    if [[ "$server" == "$HOSTNAME" ]]; then  
        # 실제 시스템에 계정이 존재하는지 확인하여 리스트에 추가  
        if id "$user" > /dev/null 2>&1; then  
            DELETE_LIST+=("$user|$group|$home")  
        fi  
    fi  
done < <(tail -n +2 "$CONFIG_FILE")

if [ ${#DELETE_LIST[@]} -eq 0 ]; then  
    echo "No existing accounts found to rollback for $HOSTNAME."  
    exit 0  
fi

# ------------------------------------------------------------------------------  
# 2. 삭제 예정 목록 표시 및 사용자 확인 (Confirmation)  
# ------------------------------------------------------------------------------  
echo -e "\n========================================================================"  
echo -e "                [ ⚠️  계정 삭제 예정 목록 확인 ]"  
echo -e "========================================================================"  
printf "%-15s | %-15s | %-25s\n" "사용자명" "그룹명" "홈 디렉토리"  
echo "------------------------------------------------------------------------"

for item in "${DELETE_LIST[@]}"; do  
    IFS='|' read -r u g h <<< "$item"  
    printf "%-15s | %-15s | %-25s\n" "$u" "$g" "$h"  
done

echo "------------------------------------------------------------------------"  
echo " 위 목록의 모든 계정과 홈 디렉토리가 영구적으로 삭제됩니다."  
echo " 이 작업을 계속 진행하시겠습니까? (y/n): "  
read -r CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then  
    echo -e "\n[작업 취소] 원복 프로세스를 중단합니다."  
    exit 0  
fi

# ------------------------------------------------------------------------------  
# 3. 실제 원복 프로세스 수행  
# ------------------------------------------------------------------------------  
echo -e "\n>>> 원복 프로세스를 시작합니다..."

for item in "${DELETE_LIST[@]}"; do  
    IFS='|' read -r user group home <<< "$item"  
      
    log "INFO" ">>> Processing rollback for: $user"

    # 1. 사용자 및 홈 디렉토리 삭제  
    if id "$user" > /dev/null 2>&1; then  
        # 로그인 중인 프로세스 강제 종료  
        pkill -u "$user" 2>/dev/null  
          
        userdel -r "$user" 2>/dev/null  
        if [ $? -eq 0 ]; then  
            log "INFO" "  -> User [$user] and home directory deleted."  
        else  
            userdel -f -r "$user" && log "INFO" "  -> User [$user] force deleted."  
        fi  
    fi

    # 2. 기본 그룹 삭제 (다른 멤버가 없을 때만)  
    if getent group "$group" > /dev/null; then  
        group_members=$(getent group "$group" | cut -d: -f4)  
        if [ -z "$group_members" ]; then  
            groupdel "$group" && log "INFO" "  -> Group [$group] deleted."  
        else  
            log "INFO" "  -> Group [$group] kept (other members exist)."  
        fi  
    fi  
done

echo "========================================================================"  
log "INFO" "Rollback process finished for $HOSTNAME."  
echo "========================================================================"
