#!/bin/bash
# ==============================================================================
# permission/permission_rollback.sh
# permission_apply.sh가 변경하기 전에 기록해둔 원래 소유자/그룹/권한으로
# 복원한다 (manifest 기반 - permission_apply.sh를 실행한 적 없는 경로는
# 건드리지 않는다).
# ==============================================================================
# 사용법: sudo ./permission_rollback.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_warn "=== 디렉터리 권한 롤백 시작: ${HOSTNAME_SHORT} ==="

backups=$(manifest_read "original_permissions.txt")
created_dirs=$(manifest_read "created_dirs.txt")

if [ -z "$backups" ] && [ -z "$created_dirs" ]; then
    log_warn "생성 기록(manifest)이 없습니다: $(manifest_dir)/original_permissions.txt / created_dirs.txt"
    log_warn "permission_apply.sh를 이 호스트에서 실행한 적이 없는 것으로 보입니다. 종료합니다."
    exit 0
fi

log_warn "아래 경로들의 권한을 적용 이전 상태로 되돌립니다:"
[ -n "$backups" ] && echo "$backups" | while IFS=: read -r path owner group perm; do
    log_warn "  - ${path} -> ${owner}:${group} ${perm} (권한 복원)"
done
[ -n "$created_dirs" ] && echo "$created_dirs" | while IFS= read -r path; do
    log_warn "  - ${path} -> 삭제 (permission_apply.sh가 새로 만든 디렉터리, 비어있을 때만 삭제)"
done
confirm_or_exit "정말로 진행하시겠습니까?"

# 1. permission_apply.sh가 새로 만든 디렉터리는 삭제한다(비어있을 때만 -
#    안에 뭔가 생겼으면 데이터 손실 방지를 위해 건드리지 않고 경고만 남김)
if [ -n "$created_dirs" ]; then
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        if [ ! -e "$path" ]; then
            log_info "경로 '${path}'가 이미 존재하지 않습니다. 건너뜁니다."
            continue
        fi
        if rmdir "$path" 2>/dev/null; then
            log_success "새로 만든 디렉터리 삭제 완료: ${path}"
        else
            log_warn "디렉터리 '${path}'가 비어있지 않아 삭제하지 않았습니다(데이터 보호). 수동 확인 필요."
        fi
    done <<< "$created_dirs"
fi

# 2. 기존에 있던 경로는 백업해둔 원래 권한으로 복원한다
if [ -n "$backups" ]; then
    while IFS=: read -r path owner group perm; do
        [ -z "$path" ] && continue
        if [ ! -e "$path" ]; then
            log_warn "경로 '${path}'가 존재하지 않습니다. 건너뜁니다."
            continue
        fi
        if chown "${owner}:${group}" "$path" && chmod "$perm" "$path"; then
            log_success "복원 완료: ${path} -> ${owner}:${group} ${perm}"
        else
            log_error "복원 실패: ${path}"
        fi
    done <<< "$backups"
fi

rm -f "$(manifest_dir)/original_permissions.txt" "$(manifest_dir)/created_dirs.txt"

log_warn "=== 디렉터리 권한 롤백 완료: ${HOSTNAME_SHORT} ==="
