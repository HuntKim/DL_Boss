#!/bin/bash
# ==============================================================================
# os-parameter/os_param_rollback.sh
# os_param_apply.sh가 생성한 sysctl/limits drop-in 파일을 제거하고,
# 적용 전에 백업해둔 원본이 있으면 복원한다.
# ==============================================================================
# 사용법: sudo ./os_param_rollback.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_warn "=== OS 파라미터 롤백 시작: ${HOSTNAME_SHORT} ==="

created_files=$(manifest_read "created_os_param_files.txt")
if [ -z "$created_files" ]; then
    log_warn "생성 기록(manifest)이 없습니다: $(manifest_dir)/created_os_param_files.txt"
    log_warn "os_param_apply.sh를 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
fi

log_warn "제거 대상 파일: $(echo "$created_files" | tr '\n' ' ')"
confirm_or_exit "정말로 위 파일을 제거하고 OS 파라미터를 되돌리시겠습니까?"

while IFS= read -r target; do
    [ -z "$target" ] && continue

    # os_param_apply.sh가 만든 백업 파일명 규칙과 반드시 일치해야 한다.
    # sysctl.d와 limits.d 모두 "99-migration-<프로파일>.conf"라는 동일한
    # basename을 쓰므로, 접두사 없이 basename만 쓰면 두 백업이 같은
    # 이름으로 충돌한다 - 원본 경로에 따라 분기한다.
    case "$target" in
        /etc/sysctl.d/*)        backup_path="$(manifest_dir)/backup_sysctl_$(basename "$target")" ;;
        /etc/security/limits.d/*) backup_path="$(manifest_dir)/backup_limits_$(basename "$target")" ;;
        *)                      backup_path="$(manifest_dir)/backup_$(basename "$target")" ;;
    esac

    rm -f "$target"
    log_success "제거 완료: ${target}"

    if [ -f "$backup_path" ]; then
        cp -p "$backup_path" "$target"
        log_success "적용 전 원본 복원 완료: ${target}"
    fi
done <<< "$created_files"

if sysctl --system >/tmp/sysctl_rollback.log 2>&1; then
    log_success "sysctl --system 재적용 완료"
else
    log_warn "sysctl --system 재적용 중 일부 오류가 있었습니다(이 프로파일과 무관한 다른 파일 문제일 수 있음). /tmp/sysctl_rollback.log 확인 필요."
fi

# 파일 제거만으로는 "지금 떠있는" 커널 값이 되돌아가지 않으므로,
# apply 시점에 기록해둔 원래 런타임 값을 sysctl -w로 직접 복원한다.
orig_values=$(manifest_read "original_sysctl_values.txt")
if [ -n "$orig_values" ]; then
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
            log_success "런타임 값 복원 완료: ${key} = ${value}"
        else
            log_warn "런타임 값 복원 실패(부팅 시점에만 설정 가능한 파라미터일 수 있음): ${key} = ${value}"
        fi
    done <<< "$orig_values"
    rm -f "$(manifest_dir)/original_sysctl_values.txt"
fi

rm -f "$(manifest_dir)/created_os_param_files.txt"

log_warn "=== OS 파라미터 롤백 완료: ${HOSTNAME_SHORT} ==="
