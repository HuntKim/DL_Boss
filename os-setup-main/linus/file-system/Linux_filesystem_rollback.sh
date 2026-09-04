#!/bin/bash

# ==============================================================================
# LVM 및 파일시스템 동적 초기화 (Dynamic Rollback) 스크립트
# CSV 의존성을 제거하여 CSV 변경 시에도 남아있는 모든 비-OS LVM 자원을 정리합니다.
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Error: Root privilege required"
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. OS 자원(디스크 및 VG) 자동 식별
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

get_os_vgs() {
    local mount_point
    local source

    for mount_point in / /boot /boot/efi; do
        source=$(findmnt -rn -M "$mount_point" -o SOURCE 2>/dev/null) || continue
        lvs --noheadings -o vg_name "$source" 2>/dev/null | tr -d ' '
    done | sort -u
}

mapfile -t OS_DISKS < <(get_os_disks)
mapfile -t OS_VGS < <(get_os_vgs)

echo ">>> Protected OS Disks : ${OS_DISKS[*]}"
echo ">>> Protected OS VGs   : ${OS_VGS[*]}"

# ------------------------------------------------------------------------------
# 2. 롤백 대상 비-OS LVM 자원 동적 수집
# ------------------------------------------------------------------------------
DELETE_LVS=()
DELETE_VGS=()
TARGET_PVS=()

# OS VG를 제외한 삭제 대상 VG 목록 수집
ALL_VGS=$(vgs --noheadings -o vg_name 2>/dev/null | tr -d ' ')

for vg in $ALL_VGS; do
    # OS VG 스킵
    if [[ " ${OS_VGS[*]} " =~ " ${vg} " ]]; then
        continue
    fi
    DELETE_VGS+=("$vg")

    # 해당 VG에 속한 LV 수집
    while read -r lv; do
        [ -n "$lv" ] && DELETE_LVS+=("/dev/$vg/$lv")
    done < <(lvs --noheadings -o lv_name "$vg" 2>/dev/null | tr -d ' ')

    # 해당 VG에 속한 PV 수집
    while read -r pv; do
        [ -n "$pv" ] && TARGET_PVS+=("$pv")
    done < <(pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk -v v="$vg" '$2==v {print $1}')
done

if [ ${#DELETE_VGS[@]} -eq 0 ]; then
    echo "No non-OS LVM resources found to rollback."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. 삭제 대상 확인 및 사용자 승인
# ------------------------------------------------------------------------------
echo -e "\n========================================================================"
echo -e "                [ ⚠️  삭제 예정 LVM 자원 목록 ]"
echo -e "========================================================================"
echo " [삭제 대상 VG] : ${DELETE_VGS[*]}"
echo " [삭제 대상 LV] :"
for lv in "${DELETE_LVS[@]}"; do
    echo "   - $lv"
done
echo " [초기화 대상 PV] : ${TARGET_PVS[*]}"
echo "------------------------------------------------------------------------"
echo " 위 목록의 모든 자원과 데이터가 영구적으로 삭제됩니다."
read -p " Proceed with rollback? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "\n[작업 취소] 원복 프로세스를 중단합니다."
    exit 0
fi

# ------------------------------------------------------------------------------
# 4. 역순 초기화 진행
# ------------------------------------------------------------------------------
echo -e "\n>>> Starting rollback process..."

# [단계 1] 대상 LV와 연결된 모든 마운트 해제 및 fstab 정리
echo ">>> Step 1: Unmounting volumes and cleaning /etc/fstab..."
for lv in "${DELETE_LVS[@]}"; do
    # DM 디바이스 경로 및 심볼릭 링크 처리
    MNT_POINTS=$(findmnt -rn -o TARGET -S "$lv" 2>/dev/null)
    
    if [ -n "$MNT_POINTS" ]; then
        for mnt in $MNT_POINTS; do
            umount -l "$mnt" && echo "    - Unmounted: $mnt"
            sed -i "\|$mnt|d" /etc/fstab && echo "    - Removed from /etc/fstab: $mnt"
        done
    fi
done

# 추가: fstab 내 삭제 대상 VG 관련 남은 잔재 강제 정리
for vg in "${DELETE_VGS[@]}"; do
    sed -i "\|/dev/mapper/${vg}-|d" /etc/fstab
    sed -i "\|/dev/${vg}/|d" /etc/fstab
done

# [단계 2] LV 삭제
echo ">>> Step 2: Removing Logical Volumes..."
for lv in "${DELETE_LVS[@]}"; do
    if [ -b "$lv" ]; then
        lvremove -f "$lv" && echo "    - Removed LV: $lv"
    fi
done

# [단계 3] VG 삭제
echo ">>> Step 3: Removing Volume Groups..."
for vg in "${DELETE_VGS[@]}"; do
    if vgdisplay "$vg" >/dev/null 2>&1; then
        vgremove -f "$vg" && echo "    - Removed VG: $vg"
    fi
done

# [단계 4] PV 삭제 및 wipefs 디스크 시그니처 wipe
echo ">>> Step 4: Clearing PVs and Disk Signatures..."
for pv in "${TARGET_PVS[@]}"; do
    # OS 디스크 안전장치
    if [[ " ${OS_DISKS[*]} " =~ " ${pv} " ]]; then
        echo "    - [SKIP] OS disk protection triggered for $pv"
        continue
    fi

    pvremove -f "$pv" 2>/dev/null
    wipefs -a "$pv" && echo "    - Wiped signature from: $pv"
done

echo "----------------------------------------------------------------------"
echo ">>> Rollback completed successfully."
echo "----------------------------------------------------------------------"
