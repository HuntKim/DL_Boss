#!/bin/bash
# ==============================================================================
# account/account_verify.sh
# 호스트 env(HOST_GROUPS, HOST_ACCOUNTS)에 정의된 대로 실제로 그룹/계정이
# 생성되어 있는지 검증한다. 아무것도 변경하지 않는다(읽기 전용).
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

load_host_env

log_info "=== 계정/그룹 검증 시작: ${HOSTNAME_SHORT} ==="

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
# 1. 그룹 검증
# ==============================================================================
for entry in "${HOST_GROUPS[@]}"; do
    IFS=':' read -r gname ggid <<< "$entry"
    [ -z "$gname" ] && continue

    if ! getent group "$gname" >/dev/null 2>&1; then
        check "그룹 '${gname}' 존재" "false"
        continue
    fi
    check "그룹 '${gname}' 존재" "true"

    if [ -n "$ggid" ]; then
        existing_gid=$(getent group "$gname" | cut -d: -f3)
        if [ "$existing_gid" = "$ggid" ]; then
            check "그룹 '${gname}' GID 일치 (${ggid})" "true"
        else
            check "그룹 '${gname}' GID 일치 (기대: ${ggid}, 실제: ${existing_gid})" "false"
        fi
    fi
done

# ==============================================================================
# 2. 계정 검증
# ==============================================================================
for entry in "${HOST_ACCOUNTS[@]}"; do
    IFS=':' read -r uname pgroup uid home shell secgroups <<< "$entry"
    [ -z "$uname" ] && continue

    if ! id "$uname" >/dev/null 2>&1; then
        check "계정 '${uname}' 존재" "false"
        continue
    fi
    check "계정 '${uname}' 존재" "true"

    actual_uid=$(id -u "$uname")
    [ "$actual_uid" = "$uid" ] \
        && check "계정 '${uname}' UID 일치 (${uid})" "true" \
        || check "계정 '${uname}' UID 일치 (기대: ${uid}, 실제: ${actual_uid})" "false"

    actual_pgroup=$(id -gn "$uname")
    [ "$actual_pgroup" = "$pgroup" ] \
        && check "계정 '${uname}' 1차그룹 일치 (${pgroup})" "true" \
        || check "계정 '${uname}' 1차그룹 일치 (기대: ${pgroup}, 실제: ${actual_pgroup})" "false"

    actual_home=$(getent passwd "$uname" | cut -d: -f6)
    [ "$actual_home" = "$home" ] \
        && check "계정 '${uname}' 홈디렉터리 일치 (${home})" "true" \
        || check "계정 '${uname}' 홈디렉터리 일치 (기대: ${home}, 실제: ${actual_home})" "false"

    if [ ! -d "$actual_home" ]; then
        check "계정 '${uname}' 홈디렉터리 실제 존재 (${actual_home})" "false"
    else
        check "계정 '${uname}' 홈디렉터리 실제 존재 (${actual_home})" "true"
    fi

    actual_shell=$(getent passwd "$uname" | cut -d: -f7)
    [ "$actual_shell" = "$shell" ] \
        && check "계정 '${uname}' 로그인쉘 일치 (${shell})" "true" \
        || check "계정 '${uname}' 로그인쉘 일치 (기대: ${shell}, 실제: ${actual_shell})" "false"

    if [ -n "$secgroups" ]; then
        actual_groups=$(id -Gn "$uname" | tr ' ' ';')
        for want_group in $(echo "$secgroups" | tr ';' ' '); do
            if echo ";${actual_groups};" | grep -q ";${want_group};"; then
                check "계정 '${uname}' 추가그룹 '${want_group}' 소속" "true"
            else
                check "계정 '${uname}' 추가그룹 '${want_group}' 소속" "false"
            fi
        done
    fi
done

log_info "=================================================="
log_info " 검증 결과: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT}"
log_info "=================================================="

[ "$FAIL_COUNT" -eq 0 ]
