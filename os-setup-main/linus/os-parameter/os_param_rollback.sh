#!/bin/bash

# ==============================================================================  
# 백업 파일을 이용한 안전한 원복 스크립트 (네트워크 삭제 로직 강화 버전)  
# ==============================================================================

BACKUP_ROOT="/tmp/os-setup/backups"

if [[ $EUID -ne 0 ]]; then echo "Error: Root privilege required"; exit 1; fi

# 1. 가장 최근의 백업 폴더 찾기  
LATEST_BACKUP=$(ls -td ${BACKUP_ROOT}/*/ 2>/dev/null | head -1)

# 백업 폴더가 없더라도 네트워크 스크립트는 지워야 하므로 에러로 종료하지 않고 진행합니다.  
if [ -z "$LATEST_BACKUP" ]; then  
    echo "WARN: No backup folder found. Only custom files will be removed."  
else  
    echo ">>> Found latest backup: $LATEST_BACKUP"  
fi

echo -e "\n========================================================================"  
echo -e "                [ ⚠️  시스템 설정 원복 확인 ]"  
echo -e "========================================================================"  
echo " [ 복구/삭제 대상 목록 ]"  
echo "------------------------------------------------------------------------"

# 복구 및 삭제 대상 확인  
TARGET_FILES=()  
# 1. sysctl.conf 확인  
if [ -f "$LATEST_BACKUP/sysctl.conf" ]; then echo "  - /etc/sysctl.conf (Restore)"; TARGET_FILES+=("sysctl.conf"); fi  
# 2. limits.conf 확인  
if [ -f "$LATEST_BACKUP/limits.conf" ]; then echo "  - /etc/security/limits.conf (Restore)"; TARGET_FILES+=("limits.conf"); fi  
# 3. 네트워크 스크립트 확인 (존재하면 삭제 대상)  
if [ -f "/etc/NetworkManager/dispatcher.d/99-nic-buffer" ]; then  
    echo "  - /etc/NetworkManager/dispatcher.d/99-nic-buffer (Delete)"  
    TARGET_FILES+=("99-nic-buffer")  
fi

if [ ${#TARGET_FILES[@]} -eq 0 ]; then  
    echo " 복구하거나 삭제할 대상이 없습니다."  
    exit 0  
fi

echo "------------------------------------------------------------------------"  
echo " 위 설정들을 원복/삭제하시겠습니까? (y/n): "  
read -r CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then  
    echo -e "\n[작업 취소] 원복 프로세스를 중단합니다."  
    exit 0  
fi

# ------------------------------------------------------------------------------  
# 2. 실제 원복 및 삭제 수행  
# ------------------------------------------------------------------------------  
echo -e "\n>>> 원복을 시작합니다..."

for filename in "${TARGET_FILES[@]}"; do  
    case "$filename" in  
        "sysctl.conf")  
            if [ -f "$LATEST_BACKUP/sysctl.conf" ]; then  
                cp -p "$LATEST_BACKUP/sysctl.conf" /etc/sysctl.conf  
                echo "  - Restored /etc/sysctl.conf"  
            fi  
            ;;  
        "limits.conf")  
            if [ -f "$LATEST_BACKUP/limits.conf" ]; then  
                cp -p "$LATEST_BACKUP/limits.conf" /etc/security/limits.conf  
                echo "  - Restored /etc/security/limits.conf"  
            fi  
            ;;  
        "99-nic-buffer")  
            # [핵심] 백업본이 있다면 복구하고, 없다면 새로 생성된 파일이므로 삭제함  
            if [ -f "$LATEST_BACKUP/99-nic-buffer" ]; then  
                cp -p "$LATEST_BACKUP/99-nic-buffer" /etc/NetworkManager/dispatcher.d/99-nic-buffer  
                echo "  - Restored NetworkManager dispatcher script"  
            else  
                rm -f /etc/NetworkManager/dispatcher.d/99-nic-buffer  
                echo "  - Deleted custom NetworkManager dispatcher script"  
            fi  
            ;;  
    esac  
done

# 최종 설정 반영  
if [ -f "/etc/sysctl.conf" ]; then  
    sysctl -p > /dev/null  
    echo ">>> sysctl configuration reloaded."  
fi

echo "----------------------------------------------------------------------"  
echo ">>> System restored to original state."  
echo "----------------------------------------------------------------------" 
