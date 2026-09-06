#!/bin/bash
# ==============================================================================
# account/account_rollback.sh
# account_gen.sh가 "실제로 생성한" 계정/그룹만 삭제한다
# (${BACKUP_DIR}/${HOSTNAME}/created_accounts.txt, created_groups.txt 근거).
#
# 중요: HOST_ACCOUNTS/HOST_GROUPS(env 정의)를 직접 순회하며 지우지 않는다.
#   env에는 "이미 존재해야 하는 표준 그룹"(예: wheel)처럼 우리가 만들지
#   않은 항목도 섞여 있어서, env 기준으로 지우면 실서버의 시스템 그룹을
#   삭제해버리는 사고가 날 수 있다(테스트 중 실제로 발견된 문제).
#   반드시 account_gen.sh 실행 시 기록된 manifest만 근거로 삭제한다.
#
# 계정 삭제 시 홈 디렉터리까지 함께 삭제된다(userdel -r) - 되돌릴 수 없다.
# ==============================================================================
# 사용법: sudo ./account_rollback.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_warn "=== 계정/그룹 롤백 시작: ${HOSTNAME_SHORT} ==="

created_accounts=$(manifest_read "created_accounts.txt")
created_groups=$(manifest_read "created_groups.txt")

if [ -z "$created_accounts" ] && [ -z "$created_groups" ]; then
    log_warn "생성 기록(manifest)이 없습니다: $(manifest_dir)/created_accounts.txt / created_groups.txt"
    log_warn "account_gen.sh를 이 호스트에서 실행한 적이 없거나, manifest가 삭제된 것으로 보입니다."
    log_warn "삭제할 대상이 없어 아무 작업도 하지 않고 종료합니다."
    exit 0
fi

log_warn "계정 삭제 시 홈 디렉터리(및 그 안의 모든 파일)가 함께 삭제됩니다. 되돌릴 수 없습니다."
[ -n "$created_accounts" ] && log_warn "삭제 대상 계정 (account_gen.sh가 생성한 것만): $(echo "$created_accounts" | tr '\n' ' ')"
[ -n "$created_groups" ]   && log_warn "삭제 대상 그룹 (account_gen.sh가 생성한 것만): $(echo "$created_groups" | tr '\n' ' ')"
confirm_or_exit "정말로 위 계정/그룹을 삭제하시겠습니까?"

# ==============================================================================
# 1. 계정 삭제 (manifest에 기록된 것만)
# ==============================================================================
if [ -n "$created_accounts" ]; then
    while IFS= read -r uname; do
        [ -z "$uname" ] && continue
        if ! id "$uname" >/dev/null 2>&1; then
            log_info "계정 '${uname}'은 존재하지 않습니다. 건너뜁니다."
            continue
        fi
        if userdel -r "$uname" 2>&1; then
            log_success "계정 삭제 완료: ${uname}"
        else
            log_error "계정 삭제 실패: ${uname} (프로세스가 실행 중이거나 홈 디렉터리 문제일 수 있음)"
        fi
    done <<< "$created_accounts"
fi

# ==============================================================================
# 2. 그룹 삭제 (manifest에 기록된 것만, 아직 남아있는 다른 계정이 1차
#   그룹으로 쓰고 있으면 건너뜀)
# ==============================================================================
if [ -n "$created_groups" ]; then
    while IFS= read -r gname; do
        [ -z "$gname" ] && continue
        if ! getent group "$gname" >/dev/null 2>&1; then
            log_info "그룹 '${gname}'은 존재하지 않습니다. 건너뜁니다."
            continue
        fi

        gid_of_group=$(getent group "$gname" | cut -d: -f3)
        remaining=$(getent passwd | awk -F: -v g="$gid_of_group" '$4==g {print $1}')
        if [ -n "$remaining" ]; then
            log_warn "그룹 '${gname}'을 1차 그룹으로 사용하는 계정이 남아있어 삭제하지 않습니다: ${remaining}"
            continue
        fi

        if groupdel "$gname" 2>&1; then
            log_success "그룹 삭제 완료: ${gname}"
        else
            log_error "그룹 삭제 실패: ${gname}"
        fi
    done <<< "$created_groups"
fi

# manifest 정리 (성공적으로 롤백했으면 기록도 비운다)
rm -f "$(manifest_dir)/created_accounts.txt" "$(manifest_dir)/created_groups.txt"

log_warn "=== 계정/그룹 롤백 완료: ${HOSTNAME_SHORT} ==="
