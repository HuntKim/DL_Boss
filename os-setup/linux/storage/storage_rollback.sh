#!/bin/bash
# ==============================================================================
# storage/storage_rollback.sh
# storage_gen.sh가 "실제로 생성한" 마운트/LV/VG만 순서대로 되돌린다
# (manifest 기반 - HOST_FILESYSTEMS를 직접 순회하지 않는다. 이미 존재해서
# 재사용만 한 VG/LV까지 지워버리는 사고를 막기 위함).
#
# 순서: 마운트 해제/fstab 정리 -> LV 삭제 -> VG 삭제 -> PV/디스크 초기화
# ==============================================================================
# 사용법: sudo ./storage_rollback.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_warn "=== 스토리지 롤백 시작: ${HOSTNAME_SHORT} ==="

created_mounts=$(manifest_read "created_fstab_mounts.txt")
created_lvs=$(manifest_read "created_lvs.txt")
created_vgs=$(manifest_read "created_vgs.txt")

if [ -z "$created_mounts" ] && [ -z "$created_lvs" ] && [ -z "$created_vgs" ]; then
    log_warn "생성 기록(manifest)이 없습니다: $(manifest_dir)/created_fstab_mounts.txt 등"
    log_warn "storage_gen.sh를 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
fi

log_warn "이 작업은 마운트/LV/VG/디스크의 모든 데이터를 삭제합니다. 되돌릴 수 없습니다."
[ -n "$created_mounts" ] && log_warn "해제할 마운트: $(echo "$created_mounts" | tr '\n' ' ')"
[ -n "$created_lvs" ]    && log_warn "삭제할 LV: $(echo "$created_lvs" | tr '\n' ' ')"
[ -n "$created_vgs" ]    && log_warn "삭제할 VG(및 디스크 초기화): $(echo "$created_vgs" | cut -d: -f1 | tr '\n' ' ')"
confirm_or_exit "정말로 진행하시겠습니까?"

# ==============================================================================
# 1. 마운트 해제 + fstab 항목 제거 (LV 삭제보다 반드시 먼저)
# ==============================================================================
if [ -n "$created_mounts" ]; then
    while IFS= read -r mnt; do
        [ -z "$mnt" ] && continue
        if findmnt -rn -M "$mnt" >/dev/null 2>&1; then
            umount "$mnt" && log_success "마운트 해제 완료: ${mnt}" || log_error "마운트 해제 실패: ${mnt} (사용 중인 프로세스가 있는지 확인)"
        fi
        sed -i "\#[[:space:]]${mnt}[[:space:]]#d" /etc/fstab
        log_success "fstab 항목 제거 완료: ${mnt}"
    done <<< "$created_mounts"
fi

# ==============================================================================
# 2. LV 삭제
# ==============================================================================
if [ -n "$created_lvs" ]; then
    while IFS= read -r lv; do
        [ -z "$lv" ] && continue
        if lvs "$lv" >/dev/null 2>&1; then
            lvremove -f "$lv" && log_success "LV 삭제 완료: ${lv}" || log_error "LV 삭제 실패: ${lv}"
        else
            log_info "LV '${lv}'는 이미 존재하지 않습니다. 건너뜁니다."
        fi
    done <<< "$created_lvs"
fi

# ==============================================================================
# 3. VG 삭제 + PV/디스크 초기화
# ==============================================================================
if [ -n "$created_vgs" ]; then
    while IFS=: read -r vg disk; do
        [ -z "$vg" ] && continue

        if vgs "$vg" >/dev/null 2>&1; then
            vgremove -f "$vg" && log_success "VG 삭제 완료: ${vg}" || log_error "VG 삭제 실패: ${vg}"
        else
            log_info "VG '${vg}'는 이미 존재하지 않습니다. 건너뜁니다."
        fi

        if [ -n "$disk" ] && [ -b "$disk" ]; then
            pvremove -ff -y "$disk" 2>/dev/null
            wipefs -a "$disk" 2>/dev/null
            log_success "디스크 초기화 완료: ${disk}"
        fi
    done <<< "$created_vgs"
fi

rm -f "$(manifest_dir)/created_fstab_mounts.txt" "$(manifest_dir)/created_lvs.txt" "$(manifest_dir)/created_vgs.txt"

log_warn "=== 스토리지 롤백 완료: ${HOSTNAME_SHORT} ==="
