#!/bin/bash
# ==============================================================================
# storage/storage_verify.sh
# 호스트 env(HOST_FILESYSTEMS)에 정의된 대로 마운트/용량이 구성되어
# 있는지 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

load_host_env

log_info "=== 스토리지 검증 시작: ${HOSTNAME_SHORT} ==="

if [ "${#HOST_FILESYSTEMS[@]}" -eq 0 ]; then
    log_warn "HOST_FILESYSTEMS가 정의되어 있지 않습니다. 검증할 항목이 없습니다."
    exit 0
fi

PASS_COUNT=0
FAIL_COUNT=0

check() {
    local description="$1"
    local ok="$2"
    if [ "$ok" = "true" ]; then
        log_success "[PASS] ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_error "[FAIL] ${description}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

for entry in "${HOST_FILESYSTEMS[@]}"; do
    IFS=':' read -r mnt size vg <<< "$entry"
    [ -z "$mnt" ] && continue
    [ -z "$vg" ] && vg="appvg"

    if ! findmnt -rn -M "$mnt" >/dev/null 2>&1; then
        check "마운트포인트 '${mnt}' 마운트 상태" "false"
        continue
    fi
    check "마운트포인트 '${mnt}' 마운트 상태" "true"

    src=$(findmnt -rn -M "$mnt" -o SOURCE)
    actual_vg=""
    if command -v lvs >/dev/null 2>&1; then
        actual_vg=$(lvs --noheadings -o vg_name "$src" 2>/dev/null | tr -d ' ')
    fi
    if [ -n "$actual_vg" ]; then
        [ "$actual_vg" = "$vg" ] \
            && check "'${mnt}' VG 일치 (${vg})" "true" \
            || check "'${mnt}' VG 일치 (기대: ${vg}, 실제: ${actual_vg})" "false"
    fi

    # 실제 크기는 파일시스템 오버헤드로 요청 용량과 정확히 같지 않을 수
    # 있어 "요청한 크기의 90% 이상"인지로 검증한다.
    size_gb=$(df -BG --output=size "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
    min_expected=$(( size * 90 / 100 ))
    if [ -n "$size_gb" ] && [ "$size_gb" -ge "$min_expected" ]; then
        check "'${mnt}' 용량 (요청: ${size}GB, 실제: ${size_gb}GB)" "true"
    else
        check "'${mnt}' 용량 (요청: ${size}GB, 실제: ${size_gb:-확인불가}GB)" "false"
    fi
done

log_info "=================================================="
log_info " 검증 결과: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT}"
log_info "=================================================="

[ "$FAIL_COUNT" -eq 0 ]
