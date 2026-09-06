#!/bin/bash
# ==============================================================================
# permission/permission_verify.sh
# 호스트 env(HOST_DIR_PERMISSIONS)에 정의된 대로 실제 소유자/그룹/권한이
# 설정되어 있는지 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

load_host_env

log_info "=== 디렉터리 권한 검증 시작: ${HOSTNAME_SHORT} ==="

if [ "${#HOST_DIR_PERMISSIONS[@]}" -eq 0 ]; then
    log_warn "HOST_DIR_PERMISSIONS가 정의되어 있지 않습니다. 검증할 항목이 없습니다."
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

for entry in "${HOST_DIR_PERMISSIONS[@]}"; do
    IFS=':' read -r path owner group perm <<< "$entry"
    [ -z "$path" ] && continue

    if [ ! -e "$path" ]; then
        check "경로 '${path}' 존재" "false"
        continue
    fi
    check "경로 '${path}' 존재" "true"

    actual_owner=$(stat -c '%U' "$path")
    actual_group=$(stat -c '%G' "$path")
    actual_perm=$(stat -c '%a' "$path")

    [ "$actual_owner" = "$owner" ] \
        && check "'${path}' 소유자 일치 (${owner})" "true" \
        || check "'${path}' 소유자 일치 (기대: ${owner}, 실제: ${actual_owner})" "false"

    [ "$actual_group" = "$group" ] \
        && check "'${path}' 그룹 일치 (${group})" "true" \
        || check "'${path}' 그룹 일치 (기대: ${group}, 실제: ${actual_group})" "false"

    [ "$actual_perm" = "$perm" ] \
        && check "'${path}' 권한 일치 (${perm})" "true" \
        || check "'${path}' 권한 일치 (기대: ${perm}, 실제: ${actual_perm})" "false"
done

log_info "=================================================="
log_info " 검증 결과: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT}"
log_info "=================================================="

[ "$FAIL_COUNT" -eq 0 ]
