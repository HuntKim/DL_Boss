#!/bin/bash

# ==============================================================================
# 1. 환경 설정 및 검증 모드
# ==============================================================================
DRY_RUN=false

# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/Linux_filesystem_gen.csv"
DEFAULT_VG="appvg"

OS_VERSION=$(grep -oP 'release \K[0-9.]+' /etc/redhat-release)

if [[ "$OS_VERSION" == 8.* || "$OS_VERSION" == 9.* ]]; then
    FS_TYPE="xfs"
else
    FS_TYPE="ext4"
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: Root privilege required"
    exit 1
fi

execute() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $1"
    else
        eval "$1" || {
            echo "Error executing: $1"
            exit 1
        }
    fi
}

# ==============================================================================
# 2. 설정값 추출
# ==============================================================================
HOSTNAME=$(hostname -s)

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found"
    exit 1
fi

CONFIG_LINE=$(grep "^$HOSTNAME," "$CONFIG_FILE")

if [ -z "$CONFIG_LINE" ]; then
    echo "Error: No config for $HOSTNAME"
    exit 1
fi

IFS=',' read -ra ADDR <<< "$CONFIG_LINE"
RAW_DATA=("${ADDR[@]:1}")

# ==============================================================================
# 3. VG별 필요 용량 계산 및 디스크 자동 탐색
# ==============================================================================
declare -A VG_REQUIRED_SIZE
declare -A VG_TARGET_DISK

# ------------------------------------------------------------------------------
# 추가: OS 디스크 자동 식별
# /, /boot, /boot/efi를 구성하는 물리 디스크를 반환
# ------------------------------------------------------------------------------
get_os_disks() {
    local mount_point
    local source

    for mount_point in / /boot /boot/efi; do
        source=$(findmnt -rn -M "$mount_point" -o SOURCE 2>/dev/null) || continue

        lsblk -s -n -o NAME "$source" 2>/dev/null |
            grep -E '^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|xvd[a-z]+)$' |
            sed 's|^|/dev/|'
    done | sort -u
}

mapfile -t OS_DISKS < <(get_os_disks)

echo ">>> OS disks excluded: ${OS_DISKS[*]}"

# 1) VG별 전체 필요 용량 계산
for (( i=0; i<${#RAW_DATA[@]}; i+=4 )); do
    ITEM=${RAW_DATA[$i]}

    MNT_POINT=$(echo "$ITEM" | cut -d':' -f1)
    SIZE=$(echo "$ITEM" | cut -d':' -f2)
    VG=$(echo "$ITEM" | cut -d':' -f3)

    [ -z "$VG" ] && VG=$DEFAULT_VG

    VG_REQUIRED_SIZE[$VG]=$(( ${VG_REQUIRED_SIZE[$VG]:-0} + SIZE ))
done

# 2) VG에 맞는 최적 디스크 탐색
AVAILABLE_DISKS=($(lsblk -dn -o NAME | grep -E '^sd|^nvme'))
USED_DISKS=()

for VG in "${!VG_REQUIRED_SIZE[@]}"; do
    REQUIRED=${VG_REQUIRED_SIZE[$VG]}
    BEST_DISK=""
    BEST_SIZE=0

    for DEV in "${AVAILABLE_DISKS[@]}"; do
        FULL_PATH="/dev/$DEV"

        # 추가: OS 디스크는 후보에서 제외
        if [[ " ${OS_DISKS[*]} " =~ " ${FULL_PATH} " ]]; then
            echo ">>> Skipping $FULL_PATH: OS disk."
            continue
        fi

        if [[ " ${USED_DISKS[*]} " =~ " ${FULL_PATH} " ]]; then
            continue
        fi

        SIZE_GB=$(lsblk -dn -b -o SIZE "$FULL_PATH" |
            awk '{print int($1/1024/1024/1024)}')

        if [ "$SIZE_GB" -ge "$REQUIRED" ]; then
            if [ "$BEST_SIZE" -eq 0 ] || [ "$SIZE_GB" -lt "$BEST_SIZE" ]; then
                BEST_DISK="$FULL_PATH"
                BEST_SIZE=$SIZE_GB
            fi
        fi
    done

    if [ -z "$BEST_DISK" ]; then
        echo "Error: No suitable disk found for VG $VG (Needs ${REQUIRED}GB)."
        exit 1
    fi

    VG_TARGET_DISK[$VG]=$BEST_DISK
    USED_DISKS+=("$BEST_DISK")

    echo ">>> Assigned $BEST_DISK to $VG (Required: ${REQUIRED}GB, Disk Size: ${BEST_SIZE}GB)"
done

# 실행 전 확인
if [ "$DRY_RUN" = false ]; then
    echo "----------------------------------------------------------------------"

    for VG in "${!VG_TARGET_DISK[@]}"; do
        echo "    - VG $VG will be created on ${VG_TARGET_DISK[$VG]}"
    done

    read -p "Proceed with the disk setup? (y/n): " CONFIRM
    [ "$CONFIRM" != "y" ] && exit 1
fi

# ==============================================================================
# 4. LVM 구성, 마운트 및 권한 설정
# ==============================================================================
echo ">>> Step 1: Initializing PVs and creating VGs..."

for VG in "${!VG_TARGET_DISK[@]}"; do
    DISK=${VG_TARGET_DISK[$VG]}

    execute "wipefs -a $DISK"
    execute "pvcreate -f $DISK"
    execute "vgcreate $VG $DISK"

    echo "    - VG $VG created on $DISK"
done

echo ">>> Step 2: Creating LVs, Mounting and Setting Permissions..."

for (( i=0; i<${#RAW_DATA[@]}; i+=4 )); do
    ITEM=${RAW_DATA[$i]}
    OWNER=${RAW_DATA[$i+1]}
    GROUP=${RAW_DATA[$i+2]}
    PERM=${RAW_DATA[$i+3]}

    MNT_POINT=$(echo "$ITEM" | cut -d':' -f1)
    SIZE=$(echo "$ITEM" | cut -d':' -f2)
    VG=$(echo "$ITEM" | cut -d':' -f3)

    [ -z "$VG" ] && VG=$DEFAULT_VG

    CLEAN_NAME=$(echo "$MNT_POINT" | sed 's/^\///' | sed 's/\//_/g')
    LV_NAME="${CLEAN_NAME}_lv"

    execute "lvcreate -y --wipesignatures y -L ${SIZE}G -n $LV_NAME $VG"
    execute "udevadm settle"   # udevd의 블록 장치 스캔이 완료될 때까지 대기

    DEV_PATH="/dev/mapper/${VG}-${LV_NAME}"

    execute "mkfs.${FS_TYPE} -f $DEV_PATH"
    execute "mkdir -p $MNT_POINT"
    execute "mount $DEV_PATH $MNT_POINT"

    execute "chown $OWNER:$GROUP $MNT_POINT"
    execute "chmod $PERM $MNT_POINT"

    if ! grep -q "$MNT_POINT" /etc/fstab; then
        execute "echo '$DEV_PATH $MNT_POINT $FS_TYPE defaults 0 0' >> /etc/fstab"
    fi
done

echo ">>> Deployment completed successfully."
