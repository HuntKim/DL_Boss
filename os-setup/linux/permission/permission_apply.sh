#!/bin/bash
# ==============================================================================
# permission/permission_apply.sh
# 호스트 env(HOST_DIR_PERMISSIONS)에 정의된 디렉터리의 소유자/그룹/권한을
# 적용한다. 스토리지(볼륨 생성)와 별개의 단계로, 이미 존재하는 디렉터리의
# 권한만 재설정하는 경우에도 쓰인다.
#
# 형식: "경로:소유자:그룹:권한(octal)"
# ==============================================================================
# 사용법: sudo ./permission_apply.sh [-y|--yes]
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_info "=== 디렉터리 권한 적용 시작: ${HOSTNAME_SHORT} ==="

if [ "${#HOST_DIR_PERMISSIONS[@]}" -eq 0 ]; then
    log_warn "HOST_DIR_PERMISSIONS가 정의되어 있지 않습니다. 적용할 항목이 없어 종료합니다."
    exit 0
fi

BACKUP_MANIFEST="original_permissions.txt"
FAIL=0

for entry in "${HOST_DIR_PERMISSIONS[@]}"; do
    IFS=':' read -r path owner group perm <<< "$entry"
    [ -z "$path" ] && { log_warn "빈 항목을 건너뜁니다: '$entry'"; continue; }

    is_new_dir=false
    if [ ! -e "$path" ]; then
        mkdir -p "$path"
        manifest_record "created_dirs.txt" "$path"
        is_new_dir=true
        log_info "디렉터리가 없어 새로 생성했습니다: ${path} (rollback 시 삭제 대상으로 기록)"
    fi

    if ! getent passwd "$owner" >/dev/null 2>&1; then
        log_error "'${path}'의 소유자로 지정된 계정 '${owner}'이 존재하지 않습니다. account_gen.sh를 먼저 실행했는지 확인하세요."
        FAIL=1
        continue
    fi
    if ! getent group "$group" >/dev/null 2>&1; then
        log_error "'${path}'의 그룹으로 지정된 '${group}'이 존재하지 않습니다."
        FAIL=1
        continue
    fi

    # 새로 만든 디렉터리는 rollback에서 통째로 삭제되므로(위 created_dirs.txt),
    # "적용 전 권한"을 따로 백업할 필요가 없다 - 오히려 두 기록이 겹치면
    # rollback이 "삭제"와 "권한 복원"을 동시에 시도해 혼란스러워진다.
    # 기존에 있던 경로만 백업 대상이다.
    if [ "$is_new_dir" = false ]; then
        # 이번이 처음 건드리는 경로라면(= 아직 백업이 없으면) 변경 전
        # 상태를 기록해둔다. 재실행 시에는 "최초 상태"를 계속 보존하기
        # 위해 다시 백업하지 않는다.
        already_backed_up=$(manifest_read "$BACKUP_MANIFEST" | awk -F: -v p="$path" '$1==p {print "yes"; exit}')
        if [ "$already_backed_up" != "yes" ]; then
            orig_owner=$(stat -c '%U' "$path")
            orig_group=$(stat -c '%G' "$path")
            orig_perm=$(stat -c '%a' "$path")
            manifest_record "$BACKUP_MANIFEST" "${path}:${orig_owner}:${orig_group}:${orig_perm}"
        fi
    fi

    if chown "${owner}:${group}" "$path" && chmod "$perm" "$path"; then
        log_success "권한 적용 완료: ${path} (${owner}:${group}, ${perm})"
    else
        log_error "권한 적용 실패: ${path}"
        FAIL=1
    fi
done

if [ "$FAIL" -ne 0 ]; then
    log_error "일부 디렉터리 권한 적용에 실패했습니다."
    exit 1
fi

log_success "=== 디렉터리 권한 적용 완료: ${HOSTNAME_SHORT} ==="
