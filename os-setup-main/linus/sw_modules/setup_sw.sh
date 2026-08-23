#!/bin/bash
# ==========================================================
# 1. 스크립트 실행 위치 및 공통 설정 로드
# ==========================================================
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
COMMON_ENV="$CONFIG_DIR/linux_common.env"

if [ ! -f "$COMMON_ENV" ]; then
    echo "[ERROR] linux_common.env 파일이 존재하지 않습니다: $COMMON_ENV" >&2
    exit 1
fi

source "$COMMON_ENV"

# hostname 대신 hostname -s 사용: FQDN(도메인 포함)으로 설정된 서버에서도
# 매핑 테이블의 짧은 호스트명과 어긋나지 않도록 함
TARGET_HOSTNAME=$(hostname -s)

# 파일 로깅 시작 (Transcript/tee)
LOG_FILE="$LOG_DIR/setup_sw_${TARGET_HOSTNAME}_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "========================================================="
log_info " SW 자동 설치 작업을 시작합니다. (Host: $TARGET_HOSTNAME)"
log_info " 로그 파일 저장 위치: $LOG_FILE"
log_info "========================================================="
log_info "CONFIG_DIR = $CONFIG_DIR"
# ==========================================================
# 2. 로컬 설정 파일 로드 (config 디렉토리 참조)
# ==========================================================
MAPPING_FILE="$CONFIG_DIR/sw_mapping_linux.txt"
HOST_ENV_FILE="$CONFIG_DIR/env/${TARGET_HOSTNAME}.env"

if [ ! -f "$MAPPING_FILE" ]; then
    log_error "매핑 테이블 파일이 존재하지 않습니다: $MAPPING_FILE"
    exit 1
fi

if [ -f "$HOST_ENV_FILE" ]; then
    source "$HOST_ENV_FILE"
    log_info "호스트 전용 환경설정 로드 완료: ${TARGET_HOSTNAME}.env"
else
    log_warn "호스트 전용 환경설정 파일이 없습니다: $HOST_ENV_FILE (경로 변수가 필요한 SW는 실패할 수 있습니다)"
fi

# ==========================================================
# 3. 내 서버에 맞는 SW 리스트 추출
# ==========================================================
# 정규식 [[:space:]]* 를 추가하여 호스트명과 기호(:=) 사이의 공백까지 유연하게 허용
SW_LIST=$(grep -E "^[[:space:]]*${TARGET_HOSTNAME}[[:space:]]*[:=]" "$MAPPING_FILE" | awk -F'[:=]' '{print $2}' | xargs)

if [ -z "$SW_LIST" ] || [ "$SW_LIST" = "-" ]; then
    log_info "매핑 테이블에 $TARGET_HOSTNAME 설정 정보가 없거나 설치 대상 SW가 없습니다. (-)"
    log_success "$TARGET_HOSTNAME SW 설치 프로세스를 종료합니다."
    exit 0
fi

log_info "설치 대상 SW 리스트: $SW_LIST"

# ==========================================================
# 3-1. JDK 계열 설치 경로 결정
#   - env 파일에는 JDK_PATH_ORACLE_8, JDK_PATH_OPEN_8, JDK_PATH_OPEN_7 처럼
#     "벤더_메이저버전" 단위로 경로가 정의되어 있음
#   - 특정 item 문자열을 case 에 하드코딩하지 않고, SW_TYPE + 메이저버전으로
#     동적으로 변수명을 조립해 해당 값을 찾는다 (신규 호스트/버전 추가 시
#     이 스크립트를 수정할 필요 없이 env 파일에 변수만 추가하면 됨)
# ==========================================================
get_jdk_major_version() {
    local ver="$1"
    case "$ver" in
        *1.7.*|*7u*|*_7_*) echo "7" ;;
        *1.8.*|*8u*|*_8_*) echo "8" ;;
        *11.*|*11u*|*_11_*) echo "11" ;;
        *17.*|*17u*|*_17_*) echo "17" ;;
        *) echo "" ;;
    esac
}

resolve_jdk_install_path() {
    local sw_type="$1"
    local sw_ver="$2"
    local major varname

    major=$(get_jdk_major_version "$sw_ver")
    if [ -z "$major" ]; then
        echo ""
        return
    fi

    case "$sw_type" in
        oracle_jdk) varname="JDK_PATH_ORACLE_${major}" ;;
        openjdk)    varname="JDK_PATH_OPEN_${major}" ;;
    esac

    echo "${!varname:-}"
}

# ==========================================================
# 4. 동일 디렉토리 내 설치 모듈 직접 호출
# ==========================================================
SUCCESS_LIST=()
FAIL_LIST=()

IFS=',' read -ra ADDR <<< "$SW_LIST"
for item in "${ADDR[@]}"; do
    item=$(echo "$item" | xargs)
    [ -z "$item" ] || [ "$item" = "-" ] && continue

    # 접두사 패턴 파싱 -> SW_TYPE을 하이픈(-) 없이 언더바(_)로 통일
    if [[ "$item" == oracle_jdk_* ]]; then
        SW_TYPE="oracle_jdk"
        SW_VER="${item#oracle_jdk_}"
        MODULE_NAME="install_jdk.sh"
    elif [[ "$item" == openjdk_* ]]; then
        SW_TYPE="openjdk"
        SW_VER="${item#openjdk_}"
        MODULE_NAME="install_jdk.sh"
    elif [[ "$item" == oracle_client_* ]]; then
        SW_TYPE="oracle_client"
        SW_VER="${item#oracle_client_}"
        MODULE_NAME="install_oracle.sh"
    # elif [[ "$item" == pkg_perl_* ]]; then
    #     SW_TYPE="perl"
    #     SW_VER="${item#pkg_perl_}"
    #     MODULE_NAME="install_perl.sh"
    elif [[ "$item" == pkg_* ]]; then
        SW_TYPE="pkg"
        SW_VER="${item#pkg_}"
        MODULE_NAME="install_pkg.sh"
    else
        # python, nodejs 등은 이곳을 타고 SW_TYPE과 SW_VER이 분리됨
        SW_TYPE=$(echo "$item" | cut -d'_' -f1)
        SW_VER=$(echo "$item" | cut -d'_' -f2-)
        MODULE_NAME="install_${SW_TYPE}.sh"
    fi

    MODULE_PATH="$CURRENT_DIR/$MODULE_NAME"

    if [ ! -f "$MODULE_PATH" ]; then
        log_error "$MODULE_NAME 모듈 파일을 찾을 수 없습니다: $MODULE_PATH"
        FAIL_LIST+=("$item (모듈 없음)")
        continue
    fi

    chmod +x "$MODULE_PATH"

    log_info "--------------------------------------------------"
    log_info "[PROCESS] $item"
    log_info " TYPE: $SW_TYPE | VER: $SW_VER | MODULE: $MODULE_NAME"
    
    log_info " ▶ [$item] 모듈 호출을 시작합니다."

    RESULT=0
    case "$SW_TYPE" in
        oracle_jdk|openjdk)
            INSTALL_PATH=$(resolve_jdk_install_path "$SW_TYPE" "$SW_VER")
            if [ -z "$INSTALL_PATH" ]; then
                log_error "$item 설치 경로(JDK_PATH_*)를 ${TARGET_HOSTNAME}.env 에서 찾을 수 없습니다."
                FAIL_LIST+=("$item (경로 미정의)")
                continue
            fi
            "$MODULE_PATH" "$SW_TYPE" "$SW_VER" "$INSTALL_PATH"
            RESULT=$?
            ;;
        oracle_client)
            "$MODULE_PATH" "$SW_TYPE" "$SW_VER" "$ORACLE_HOME"
            RESULT=$?
            ;;
        # perl)
        #     "$MODULE_PATH" "$SW_VER" "$PERL_PATH"
        #     RESULT=$?
        #     ;;
        # ======================================================
        # package 및 그외 sw 모듈 (Python, Node.js 등)
        # 환경변수는 스크립트 내부에서 직접 읽으므로 SW_VER만 넘김
        # ======================================================
        pkg|*)
            "$MODULE_PATH" "$SW_VER"
            RESULT=$?
            ;;
    esac

    if [ "$RESULT" -eq 0 ]; then
        log_success " ▷ [$item] 모듈 실행이 완료되었습니다."
        SUCCESS_LIST+=("$item")
    else
        log_error " ▷ [$item] 모듈 실행이 실패했습니다. (exit code: $RESULT)"
        FAIL_LIST+=("$item")
    fi
done

log_info "========================================================="
log_info "설치 결과 요약: 성공 ${#SUCCESS_LIST[@]}건 / 실패 ${#FAIL_LIST[@]}건"
[ ${#SUCCESS_LIST[@]} -gt 0 ] && log_info "성공 목록: ${SUCCESS_LIST[*]}"

if [ ${#FAIL_LIST[@]} -gt 0 ]; then
    log_error "실패 목록: ${FAIL_LIST[*]}"
    log_error "$TARGET_HOSTNAME 일부 SW 설치가 실패했습니다."
    log_info "========================================================="
    exit 1
fi

log_success "$TARGET_HOSTNAME 모든 SW 설치 프로세스가 완료되었습니다."
log_info "========================================================="
