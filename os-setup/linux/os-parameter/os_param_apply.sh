#!/bin/bash
# ==============================================================================
# os-parameter/os_param_apply.sh
# 호스트 env(HOST_OS_PARAM_PROFILE)가 가리키는 프로파일의 sysctl/limits
# 값을 시스템에 적용한다.
#
# 프로파일은 config/os_param_profiles/<프로파일명>.param.conf 파일 하나에
# sysctl.conf 줄과 limits.conf 줄을 섞어서 담고 있다(네이티브 형식 그대로,
# 커스텀 문법 없음). "=" 포함 여부로 자동 분류한다:
#   - "=" 포함    -> sysctl.conf 형식("key = value")
#   - "=" 미포함  -> limits.conf 형식("domain type item value", 공백 4컬럼)
# ==============================================================================
# 사용법: sudo ./os_param_apply.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_info "=== OS 파라미터 적용 시작: ${HOSTNAME_SHORT} ==="

if [ -z "$HOST_OS_PARAM_PROFILE" ]; then
    log_error "HOST_OS_PARAM_PROFILE이 정의되어 있지 않습니다 (config/os_env/${HOSTNAME_SHORT}.env 확인)"
    exit 1
fi

PROFILE_FILE="${OS_PARAM_PROFILE_DIR}/${HOST_OS_PARAM_PROFILE}.param.conf"
if [ ! -f "$PROFILE_FILE" ]; then
    log_error "프로파일 파일이 없습니다: ${PROFILE_FILE}"
    log_error "config/os_param_profiles/${HOST_OS_PARAM_PROFILE}.param.conf 을 먼저 만들어야 합니다."
    exit 1
fi

log_info "적용할 프로파일: ${HOST_OS_PARAM_PROFILE} (${PROFILE_FILE})"

SYSCTL_LINES=$(extract_sysctl_lines "$PROFILE_FILE")
LIMITS_LINES=$(extract_limits_lines "$PROFILE_FILE")

# 대상 파일이 이미 있으면(예: 이전에 다른 방식으로 수동 설정된 값) rollback을
# 위해 원본을 백업해둔다. 우리가 이전에 이미 백업해둔 파일이 있으면 다시
# 덮어쓰지 않는다(최초 상태를 계속 보존).
backup_if_needed() {
    local target="$1"
    local backup_name="$2"
    local backup_path
    backup_path="$(manifest_dir)/${backup_name}"

    if [ -f "$target" ] && [ ! -f "$backup_path" ]; then
        cp -p "$target" "$backup_path"
        log_info "기존 파일 백업 완료: ${target} -> ${backup_path}"
    fi
}

# ==============================================================================
# 1. sysctl 값 적용
# ==============================================================================
SYSCTL_DST="/etc/sysctl.d/99-migration-${HOST_OS_PARAM_PROFILE}.conf"

if [ -n "$SYSCTL_LINES" ]; then
    backup_if_needed "$SYSCTL_DST" "backup_sysctl_$(basename "$SYSCTL_DST")"

    # 파일(config)만 제거해서는 이미 반영된 "지금 떠있는" 커널 값은
    # 되돌아가지 않는다(sysctl.d 삭제는 "다음 부팅부터 재적용 안 함"만
    # 보장). 그래서 각 키의 "적용 전 실제 런타임 값"을 여기서 미리
    # 기록해두고, rollback에서 sysctl -w로 그 값까지 복원한다.
    # 이미 기록이 있으면(재실행) 최초 값을 덮어쓰지 않는다.
    ORIG_SYSCTL_MANIFEST="original_sysctl_values.txt"
    if [ -z "$(manifest_read "$ORIG_SYSCTL_MANIFEST")" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            key=$(echo "$line" | cut -d'=' -f1 | xargs)
            [ -z "$key" ] && continue
            orig_value=$(sysctl -n "$key" 2>/dev/null)
            manifest_record "$ORIG_SYSCTL_MANIFEST" "${key}=${orig_value}"
        done <<< "$SYSCTL_LINES"
        log_info "적용 전 런타임 sysctl 값 기록 완료 (rollback 시 복원용): $(manifest_dir)/${ORIG_SYSCTL_MANIFEST}"
    fi

    echo "$SYSCTL_LINES" > "$SYSCTL_DST"

    # sysctl --system은 /etc/sysctl.d/ 전체 파일을 다시 적용한다. 이
    # 프로파일과 무관한 다른(기존) 파일이 실패해도 전체 명령의 종료
    # 코드가 실패로 나올 수 있으므로, 종료 코드만으로 성공 여부를
    # 판단하지 않는다. 대신 우리 프로파일에 있는 키들이 실제로 적용
    # 됐는지 하나씩 직접 확인한다.
    sysctl --system >/tmp/sysctl_apply.log 2>&1
    log_info "sysctl --system 실행 완료 (전체 로그: /tmp/sysctl_apply.log, 다른 기존 파일의 오류가 섞여있을 수 있음)"

    apply_fail=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        key=$(echo "$line" | cut -d'=' -f1 | xargs)
        expected=$(echo "$line" | cut -d'=' -f2- | xargs)
        [ -z "$key" ] && continue

        actual=$(sysctl -n "$key" 2>/dev/null | xargs)
        if [ "$actual" = "$expected" ]; then
            log_success "sysctl 적용 확인: ${key} = ${expected}"
        else
            log_error "sysctl 적용 실패: ${key} (기대: '${expected}', 실제: '${actual}')"
            apply_fail=1
        fi
    done <<< "$SYSCTL_LINES"

    if [ "$apply_fail" -ne 0 ]; then
        log_error "이 프로파일의 sysctl 값 중 일부가 적용되지 않았습니다. /tmp/sysctl_apply.log 확인 필요."
        exit 1
    fi

    log_success "sysctl 프로파일 적용 완료: ${SYSCTL_DST}"
    manifest_record "created_os_param_files.txt" "$SYSCTL_DST"
else
    log_warn "프로파일에 sysctl 항목('=' 포함 줄)이 없습니다. 건너뜁니다."
fi

# ==============================================================================
# 2. limits 값 적용
# ==============================================================================
LIMITS_DST="/etc/security/limits.d/99-migration-${HOST_OS_PARAM_PROFILE}.conf"

if [ -n "$LIMITS_LINES" ]; then
    backup_if_needed "$LIMITS_DST" "backup_limits_$(basename "$LIMITS_DST")"
    echo "$LIMITS_LINES" > "$LIMITS_DST"
    log_success "limits 프로파일 적용 완료: ${LIMITS_DST} (다음 로그인부터 적용됨)"
    manifest_record "created_os_param_files.txt" "$LIMITS_DST"
else
    log_warn "프로파일에 limits 항목('=' 미포함 줄)이 없습니다. 건너뜁니다."
fi

log_success "=== OS 파라미터 적용 완료: ${HOSTNAME_SHORT} (프로파일: ${HOST_OS_PARAM_PROFILE}) ==="
