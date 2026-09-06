#!/bin/bash
# ==============================================================================
# os-parameter/os_param_verify.sh
# 호스트에 지정된 프로파일의 sysctl 값이 실제로 적용됐는지, limits.d 파일
# 내용이 프로파일과 일치하는지 검증한다. 아무것도 변경하지 않는다.
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

load_host_env

log_info "=== OS 파라미터 검증 시작: ${HOSTNAME_SHORT} ==="

if [ -z "$HOST_OS_PARAM_PROFILE" ]; then
    log_error "HOST_OS_PARAM_PROFILE이 정의되어 있지 않습니다."
    exit 1
fi

PROFILE_SRC_DIR="${OS_PARAM_PROFILE_DIR}/${HOST_OS_PARAM_PROFILE}"
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

# ==============================================================================
# 1. sysctl 값 검증 (프로파일 파일의 "key = value" 줄을 그대로 읽어
#   실제 커널 값(sysctl -n key)과 비교한다)
# ==============================================================================
SYSCTL_SRC="${PROFILE_SRC_DIR}/sysctl.conf"
if [ -f "$SYSCTL_SRC" ]; then
    while IFS= read -r line; do
        # 주석/빈 줄 제외
        case "$line" in
            \#*|"") continue ;;
        esac
        key=$(echo "$line" | cut -d'=' -f1 | xargs)
        expected=$(echo "$line" | cut -d'=' -f2- | xargs)
        [ -z "$key" ] && continue

        actual=$(sysctl -n "$key" 2>/dev/null | xargs)
        if [ "$actual" = "$expected" ]; then
            check "sysctl ${key} = ${expected}" "true"
        else
            check "sysctl ${key} (기대: '${expected}', 실제: '${actual}')" "false"
        fi
    done < "$SYSCTL_SRC"
else
    log_warn "프로파일에 sysctl.conf가 없어 sysctl 검증을 건너뜁니다."
fi

# ==============================================================================
# 2. limits.d 파일 검증 (프로파일 파일과 시스템에 적용된 파일이 동일한지)
# ==============================================================================
LIMITS_SRC="${PROFILE_SRC_DIR}/limits.conf"
LIMITS_DST="/etc/security/limits.d/99-migration-${HOST_OS_PARAM_PROFILE}.conf"
if [ -f "$LIMITS_SRC" ]; then
    if [ ! -f "$LIMITS_DST" ]; then
        check "limits.d 파일 존재 (${LIMITS_DST})" "false"
    elif diff -q "$LIMITS_SRC" "$LIMITS_DST" >/dev/null 2>&1; then
        check "limits.d 파일 내용이 프로파일과 일치 (${LIMITS_DST})" "true"
    else
        check "limits.d 파일 내용이 프로파일과 일치 (${LIMITS_DST}, 내용 다름)" "false"
    fi
else
    log_warn "프로파일에 limits.conf가 없어 limits 검증을 건너뜁니다."
fi

log_info "=================================================="
log_info " 검증 결과: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT}"
log_info "=================================================="

[ "$FAIL_COUNT" -eq 0 ]
