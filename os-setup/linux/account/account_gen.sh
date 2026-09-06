#!/bin/bash
# ==============================================================================
# account/account_gen.sh
# 호스트 env(HOST_GROUPS, HOST_ACCOUNTS)를 기준으로 그룹 -> 계정 순으로 생성
# ==============================================================================
# 사용법: sudo ./account_gen.sh [-y|--yes]
# 이미 존재하는 계정/그룹은 건너뛴다(에러 아님). 존재하지만 값이 다른
# 경우는 여기서 강제로 고치지 않고 경고만 남긴다 - 실제 값 검증은
# account_verify.sh가 담당한다.
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/../config" && pwd)"
# shellcheck source=../config/common.env
source "${CONFIG_DIR}/common.env"

parse_common_args "$@"
require_root
load_host_env

log_info "=== 계정/그룹 생성 시작: ${HOSTNAME_SHORT} ==="

if [ "${#HOST_GROUPS[@]}" -eq 0 ]; then
    log_error "HOST_GROUPS가 정의되어 있지 않습니다 (config/env/${HOSTNAME_SHORT}.env 확인)"
    exit 1
fi
if [ "${#HOST_ACCOUNTS[@]}" -eq 0 ]; then
    log_error "HOST_ACCOUNTS가 정의되어 있지 않습니다 (config/env/${HOSTNAME_SHORT}.env 확인)"
    exit 1
fi

# ==============================================================================
# 1. 그룹 생성 (계정보다 먼저)
#   형식: "그룹명:GID" (GID 비워두면 "이미 존재해야 하는 표준 그룹"으로 취급)
# ==============================================================================
GROUP_FAIL=0
for entry in "${HOST_GROUPS[@]}"; do
    IFS=':' read -r gname ggid <<< "$entry"
    [ -z "$gname" ] && { log_warn "빈 그룹 항목을 건너뜁니다: '$entry'"; continue; }

    if getent group "$gname" >/dev/null 2>&1; then
        existing_gid=$(getent group "$gname" | cut -d: -f3)
        if [ -n "$ggid" ] && [ "$existing_gid" != "$ggid" ]; then
            log_warn "그룹 '${gname}'이 이미 존재하지만 GID가 다릅니다 (기존: ${existing_gid}, env 정의: ${ggid}). 기존 값을 유지합니다."
        else
            log_info "그룹 '${gname}'은 이미 존재합니다 (GID: ${existing_gid}). 건너뜁니다."
        fi
        continue
    fi

    if [ -z "$ggid" ]; then
        log_error "그룹 '${gname}'이 존재하지 않고 GID도 지정되지 않았습니다(표준 그룹으로 가정했으나 없음). 생성할 수 없습니다."
        GROUP_FAIL=1
        continue
    fi

    if groupadd -g "$ggid" "$gname"; then
        log_success "그룹 생성 완료: ${gname} (GID: ${ggid})"
        manifest_record "created_groups.txt" "$gname"
    else
        log_error "그룹 생성 실패: ${gname} (GID: ${ggid})"
        GROUP_FAIL=1
    fi
done

if [ "$GROUP_FAIL" -ne 0 ]; then
    log_error "그룹 생성 중 오류가 발생해 계정 생성 단계로 진행하지 않습니다."
    exit 1
fi

# ==============================================================================
# 2. 계정 생성 (모든 신규 계정에 HOST_INITIAL_PASSWORD 하나를 동일하게 적용)
#   형식: "계정명:1차그룹:UID:홈디렉터리:로그인쉘:추가그룹(세미콜론,옵션)"
#   ※ useradd만으로는 계정이 잠긴 상태로 생성되어 비밀번호 로그인이
#     안 된다. chpasswd로 초기 비밀번호를 설정하고, chage -d 0으로
#     "다음 로그인 시 반드시 비밀번호 변경"을 강제한다(Windows의
#     PasswordExpired 설정과 동일한 개념). 담당자가 이 초기 비밀번호로
#     로그인해 바로 자신의 비밀번호로 바꾸는 것을 전제로 한다.
# ==============================================================================
NEEDS_NEW_ACCOUNTS=false
for entry in "${HOST_ACCOUNTS[@]}"; do
    IFS=':' read -r uname _ <<< "$entry"
    [ -z "$uname" ] && continue
    if ! id "$uname" >/dev/null 2>&1; then
        NEEDS_NEW_ACCOUNTS=true
        break
    fi
done

if [ "$NEEDS_NEW_ACCOUNTS" = true ] && [ -z "$HOST_INITIAL_PASSWORD" ]; then
    log_error "HOST_INITIAL_PASSWORD가 정의되어 있지 않습니다 (config/os_env/${HOSTNAME_SHORT}.env 확인)"
    exit 1
fi

ACCOUNT_FAIL=0
created_accounts=()
for entry in "${HOST_ACCOUNTS[@]}"; do
    IFS=':' read -r uname pgroup uid home shell secgroups <<< "$entry"
    [ -z "$uname" ] && { log_warn "빈 계정 항목을 건너뜁니다: '$entry'"; continue; }

    if id "$uname" >/dev/null 2>&1; then
        log_info "계정 '${uname}'은 이미 존재합니다. 건너뜁니다 (필드 일치 여부는 account_verify.sh로 확인하세요)."
        continue
    fi

    if ! getent group "$pgroup" >/dev/null 2>&1; then
        log_error "계정 '${uname}'의 1차 그룹 '${pgroup}'이 존재하지 않습니다. HOST_GROUPS 정의를 확인하세요."
        ACCOUNT_FAIL=1
        continue
    fi

    useradd_cmd=(useradd -u "$uid" -g "$pgroup" -d "$home" -s "$shell" -m)
    if [ -n "$secgroups" ]; then
        # 세미콜론 구분자를 useradd -G가 요구하는 콤마 구분자로 변환
        secgroups_csv=$(echo "$secgroups" | tr ';' ',')
        useradd_cmd+=(-G "$secgroups_csv")
    fi
    useradd_cmd+=("$uname")

    if ! "${useradd_cmd[@]}"; then
        log_error "계정 생성 실패: ${uname}"
        ACCOUNT_FAIL=1
        continue
    fi
    log_success "계정 생성 완료: ${uname} (UID: ${uid}, 1차그룹: ${pgroup}, 홈: ${home}, 쉘: ${shell})"
    manifest_record "created_accounts.txt" "$uname"

    if echo "${uname}:${HOST_INITIAL_PASSWORD}" | chpasswd; then
        chage -d 0 "$uname"
        log_success "초기 비밀번호 설정 완료: ${uname} (다음 로그인 시 변경 필요)"
        created_accounts+=("$uname")
    else
        log_error "초기 비밀번호 설정 실패: ${uname}"
        ACCOUNT_FAIL=1
    fi
done

if [ "${#created_accounts[@]}" -gt 0 ]; then
    log_success "생성된 계정: ${created_accounts[*]} (호스트 env에 지정된 초기 비밀번호 적용됨, 다음 로그인 시 변경 필요)"
fi

if [ "$ACCOUNT_FAIL" -ne 0 ]; then
    log_error "일부 계정 생성에 실패했습니다."
    exit 1
fi

log_success "=== 계정/그룹 생성 완료: ${HOSTNAME_SHORT} ==="
