#!/bin/bash
# ==============================================================================
# storage/storage_gen.sh
# 호스트 env(HOST_FILESYSTEMS)를 기준으로 LVM 볼륨을 생성하고 마운트한다.
# 디렉터리 소유자/그룹/권한은 여기서 다루지 않는다 - permission/ 모듈이
# 별도로 처리한다(이 프로젝트의 "스토리지 구성"과 "디렉터리 권한"은
# 서로 다른 단계로 분리되어 있다).
#
# 형식: "마운트포인트:크기(GB):VG명"
# 디스크 자동 탐색/배정 로직은 기존 os-setup-main의
# file-system/Linux_filesystem_gen.sh 에서 이미 검증된 방식을 그대로
# 재사용하고, 데이터 소스만 CSV에서 이 env 배열로 바꿨다.
# ==============================================================================
# 사용법: sudo ./storage_gen.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_info "=== 스토리지 구성 시작: ${HOSTNAME_SHORT} ==="

if [ "${#HOST_FILESYSTEMS[@]}" -eq 0 ]; then
    log_warn "HOST_FILESYSTEMS가 정의되어 있지 않습니다. 구성할 스토리지가 없어 종료합니다."
    exit 0
fi

DEFAULT_VG="appvg"

if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(grep -oP 'release \K[0-9.]+' /etc/redhat-release)
else
    OS_VERSION="0"
fi
if [[ "$OS_VERSION" == 8.* || "$OS_VERSION" == 9.* ]]; then
    FS_TYPE="xfs"
else
    FS_TYPE="ext4"
fi
log_info "파일시스템 타입: ${FS_TYPE} (OS 버전: ${OS_VERSION})"

# ==============================================================================
# 1. OS 디스크 자동 식별 (/, /boot, /boot/efi를 구성하는 물리 디스크는
#    새 VG 후보에서 제외)
# ==============================================================================
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
log_info "OS 디스크(신규 VG 후보에서 제외): ${OS_DISKS[*]:-없음}"

# ==============================================================================
# 2. VG별 필요 용량 계산
# ==============================================================================
declare -A VG_REQUIRED_SIZE=()
for entry in "${HOST_FILESYSTEMS[@]}"; do
    IFS=':' read -r mnt size vg <<< "$entry"
    [ -z "$mnt" ] && continue
    [ -z "$vg" ] && vg="$DEFAULT_VG"
    VG_REQUIRED_SIZE["$vg"]=$(( ${VG_REQUIRED_SIZE["$vg"]:-0} + size ))
done

# ==============================================================================
# 3. VG별 디스크 배정 (이미 존재하는 VG는 여유 공간만 확인하고 재사용)
# ==============================================================================
declare -A VG_TARGET_DISK=()
AVAILABLE_DISKS=($(lsblk -dn -o NAME | grep -E '^sd|^nvme|^vd|^xvd'))
USED_DISKS=()

for vg in "${!VG_REQUIRED_SIZE[@]}"; do
    required=${VG_REQUIRED_SIZE[$vg]}

    if vgs "$vg" >/dev/null 2>&1; then
        vg_free_gb=$(vgs --noheadings --units g --nosuffix -o vg_free "$vg" 2>/dev/null | tr -d ' ' | cut -d'.' -f1)
        if [ -z "$vg_free_gb" ] || [ "$vg_free_gb" -lt "$required" ]; then
            log_error "기존 VG '${vg}'의 여유 공간(${vg_free_gb:-0}GB)이 필요한 용량(${required}GB)보다 부족합니다."
            exit 1
        fi
        log_info "기존 VG '${vg}' 재사용 (여유: ${vg_free_gb}GB, 필요: ${required}GB)"
        continue
    fi

    best_disk=""
    best_size=0
    for dev in "${AVAILABLE_DISKS[@]}"; do
        full_path="/dev/${dev}"
        [[ " ${OS_DISKS[*]:-} " =~ " ${full_path} " ]] && continue
        [[ " ${USED_DISKS[*]:-} " =~ " ${full_path} " ]] && continue
        pvs "$full_path" >/dev/null 2>&1 && continue   # 이미 다른 VG의 PV로 쓰이는 디스크는 제외

        size_gb=$(lsblk -dn -b -o SIZE "$full_path" 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
        [ -z "$size_gb" ] && continue

        if [ "$size_gb" -ge "$required" ]; then
            if [ "$best_size" -eq 0 ] || [ "$size_gb" -lt "$best_size" ]; then
                best_disk="$full_path"
                best_size="$size_gb"
            fi
        fi
    done

    if [ -z "$best_disk" ]; then
        log_error "VG '${vg}'에 배정할 적합한 디스크를 찾지 못했습니다 (필요: ${required}GB)."
        exit 1
    fi

    VG_TARGET_DISK["$vg"]="$best_disk"
    USED_DISKS+=("$best_disk")
    log_info "VG '${vg}' -> 디스크 ${best_disk} 배정 예정 (필요: ${required}GB, 디스크 크기: ${best_size}GB)"
done

# ==============================================================================
# 4. 신규 VG 생성 확인 (디스크를 통째로 지우므로 반드시 확인)
# ==============================================================================
if [ "${#VG_TARGET_DISK[@]}" -gt 0 ]; then
    log_warn "아래 디스크 전체를 지우고 새 볼륨그룹을 생성합니다:"
    for vg in "${!VG_TARGET_DISK[@]}"; do
        log_warn "  - VG ${vg} <- ${VG_TARGET_DISK[$vg]} (기존 데이터가 있다면 모두 삭제됨)"
    done
    confirm_or_exit "진행하시겠습니까?"
fi

for vg in "${!VG_TARGET_DISK[@]}"; do
    disk="${VG_TARGET_DISK[$vg]}"
    wipefs -a "$disk"
    pvcreate -f "$disk"
    vgcreate "$vg" "$disk"
    manifest_record "created_vgs.txt" "${vg}:${disk}"
    log_success "VG 생성 완료: ${vg} (디스크: ${disk})"
done

# ==============================================================================
# 5. LV 생성, 포맷, 마운트, fstab 등록
# ==============================================================================
for entry in "${HOST_FILESYSTEMS[@]}"; do
    IFS=':' read -r mnt size vg <<< "$entry"
    [ -z "$mnt" ] && continue
    [ -z "$vg" ] && vg="$DEFAULT_VG"

    if findmnt -rn -M "$mnt" >/dev/null 2>&1; then
        log_info "마운트포인트 '${mnt}'는 이미 마운트되어 있습니다. 건너뜁니다."
        continue
    fi

    clean_name=$(echo "$mnt" | sed 's/^\///' | sed 's/\//_/g')
    lv_name="${clean_name}_lv"
    dev_path="/dev/mapper/${vg}-${lv_name}"

    if lvs "${vg}/${lv_name}" >/dev/null 2>&1; then
        log_info "LV '${vg}/${lv_name}'는 이미 존재합니다. 재사용합니다."
    else
        lvcreate -y --wipesignatures y -L "${size}G" -n "$lv_name" "$vg"
        udevadm settle 2>/dev/null
        # mkfs.xfs는 소문자 -f 가 강제 옵션이지만, mkfs.ext2/3/4는 대문자
        # -F 를 써야 한다(소문자 -f는 "invalid option"으로 실패함 - 실제
        # 테스트 중 발견). 파일시스템 종류별로 분기한다.
        case "$FS_TYPE" in
            xfs) mkfs.xfs -f "$dev_path" ;;
            ext2|ext3|ext4) mkfs."${FS_TYPE}" -F "$dev_path" ;;
            *) mkfs."${FS_TYPE}" "$dev_path" ;;
        esac
        manifest_record "created_lvs.txt" "${vg}/${lv_name}"
        log_success "LV 생성 및 포맷 완료: ${vg}/${lv_name} (${size}GB, ${FS_TYPE})"
    fi

    mkdir -p "$mnt"
    if mount "$dev_path" "$mnt"; then
        log_success "마운트 완료: ${dev_path} -> ${mnt}"
    else
        log_error "마운트 실패: ${dev_path} -> ${mnt}"
        exit 1
    fi

    if ! grep -qF " ${mnt} " /etc/fstab; then
        echo "${dev_path} ${mnt} ${FS_TYPE} defaults 0 0" >> /etc/fstab
        manifest_record "created_fstab_mounts.txt" "$mnt"
        log_success "fstab 등록 완료: ${mnt}"
    fi
done

log_success "=== 스토리지 구성 완료: ${HOSTNAME_SHORT} ==="
