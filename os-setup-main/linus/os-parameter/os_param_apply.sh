#!/bin/bash

# ==============================================================================    
# 1. 환경 설정 및 공통 함수    
# ==============================================================================    
DRY_RUN=false               # true: 모의 실행, false: 실제 적용            

# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/os_param_apply.csv"  

# ------------------------------------------------------------------------------  
# [추가] 실행 전 설정 파일 백업 로직  
# ------------------------------------------------------------------------------  
BACKUP_DIR="/tmp/os-setup/backups/$(date +%Y%m%d_%H%M%S)"

# 백업할 대상 파일 리스트  
FILES_TO_BACKUP=(  
    "/etc/sysctl.conf"  
    "/etc/security/limits.conf"  
    "/etc/NetworkManager/dispatcher.d/99-nic-buffer"  
)

# Root 권한 체크 후 백업 수행  
if [[ $EUID -ne 0 ]]; then echo "Error: Root privilege required"; exit 1; fi

echo ">>> Performing pre-deployment backup..."  
mkdir -p "$BACKUP_DIR"  
for file in "${FILES_TO_BACKUP[@]}"; do  
    if [ -f "$file" ]; then  
        cp -p "$file" "$BACKUP_DIR/$(basename "$file")"  
        echo "    - Backed up $file to $BACKUP_DIR"  
    fi  
done  
echo ">>> Backup completed. Backup location: $BACKUP_DIR"  
echo "----------------------------------------------------------------------"  
# ------------------------------------------------------------------------------

DEFAULT_VG="appvg"

# [기존 코드 시작 - 여기서부터는 수정 없이 그대로 유지]  
execute() {            
    if [ "$DRY_RUN" = true ]; then            
        echo "[DRY-RUN] Would execute: $*"            
    else            
        "$@"    
    fi            
}

# sysctl 파라미터 설정 함수            
set_sysctl() {            
    local param=$1            
    local value=$2            
    echo "Setting sysctl $param = $value"            
        
    execute sysctl -w "$param=$value"            
    if grep -q "^$param" /etc/sysctl.conf; then            
        [ "$DRY_RUN" = false ] && sed -i "s/^$param.*/$param = $value/" /etc/sysctl.conf            
    else            
        [ "$DRY_RUN" = false ] && echo "$param = $value" >> /etc/sysctl.conf            
    fi            
}

# limits.conf 설정 함수            
set_limit() {            
    local user=$1            
    local type=$2            
    local item=$3            
    local value=$4            
    echo "Setting limit $user $type $item = $value"            
    local line="$user $type $item $value"            
    if grep -q "^$user $type $item" /etc/security/limits.conf; then            
        [ "$DRY_RUN" = false ] && sed -i "s/^$user $type $item.*/$line/" /etc/security/limits.conf            
    else            
        [ "$DRY_RUN" = false ] && echo "$line" >> /etc/security/limits.conf            
    fi            
}

# ==============================================================================            
# 2. 그룹별 설정 정의            
# ==============================================================================

# [공통] TIBCO RV UDP Buffer Tuning 함수    
apply_udp_tuning() {        
    set_sysctl "net.core.rmem_max" "16777216"            
    set_sysctl "net.core.wmem_max" "16777216"            
    set_sysctl "net.core.rmem_default" "16777216"            
    set_sysctl "net.core.wmem_default" "16777216"        
}

apply_EES_PHOTO() {            
    echo ">>> Applying EES-PHOTO settings..."            
    apply_udp_tuning        
}

apply_TC() {            
    echo ">>> Applying TC settings..."            
    set_sysctl "vm.overcommit_memory" "0"            
    set_sysctl "net.core.rmem_max" "16777216"            
    set_sysctl "net.core.wmem_max" "16777216"            
                
    local NM_FILE="/etc/NetworkManager/dispatcher.d/99-nic-buffer"            
    if [ "$DRY_RUN" = false ]; then            
        cat <<EOF > $NM_FILE
#!/bin/bash
INTERFACE=\$1
ACTION=\$2
if [ "\$ACTION" = "up" ]; then
    /usr/sbin/ethtool -G \$INTERFACE rx 512 tx 512
fi
EOF
        chmod +x $NM_FILE            
    else            
        echo "[DRY-RUN] Would create $NM_FILE and chmod +x"            
    fi            
}

apply_MOS() {            
    echo ">>> Applying MOS settings..."            
    apply_udp_tuning        
                
    set_limit "*" "soft" "stack" "81920"            
    set_limit "*" "hard" "stack" "81920"            
    set_limit "*" "soft" "nofile" "8192"            
    set_limit "*" "hard" "nofile" "8192"            
}

apply_AR_FPA() {            
    echo ">>> Applying AR_FPA settings..."            
    apply_udp_tuning        
}

apply_RMS() {            
    echo ">>> Applying RMS settings..."            
    set_limit "*" "soft" "stack" "81920"            
    set_limit "*" "hard" "stack" "81920"            
}

# ==============================================================================            
# 3. 실행 메인 로직            
# ==============================================================================            
HOSTNAME=$(hostname -s)            
if [ ! -f "$CONFIG_FILE" ]; then echo "Error: $CONFIG_FILE not found"; exit 1; fi            
GROUP=$(grep "^$HOSTNAME," "$CONFIG_FILE" | cut -d',' -f2)

if [ -z "$GROUP" ]; then            
    echo "No group defined for $HOSTNAME. Skipping."            
    exit 0            
fi

case $GROUP in            
    "EES-PHOTO") apply_EES_PHOTO ;;            
    "TC")        apply_TC ;;            
    "MOS")       apply_MOS ;;            
    "AR_FPA")    apply_AR_FPA ;;            
    "RMS")       apply_RMS ;;            
    *)           echo "Unknown group $GROUP"; exit 1 ;;            
esac

if [ "$DRY_RUN" = false ]; then            
    sysctl -p > /dev/null            
    echo ">>> All settings applied successfully."            
else            
    echo ">>> DRY-RUN completed. No changes made."            
fi 
