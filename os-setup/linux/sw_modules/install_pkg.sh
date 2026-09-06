#!/bin/bash
# ==========================================================
# 패키지 자동 설치 모듈 (install_pkg.sh)
#
# [기능]
#   - sw_mapping_linux.txt의 pkg_ 항목을 분석하여 dnf 패키지 설치
#   - 아키텍처 표기(_32b, _64b)를 dnf 표준 접미사(.i686, .x86_64)로 변환
#   - noarch 패키지 대응을 위한 2단계 설치 시도 로직 적용
#   - 설치 실패 시 해당 패키지를 기록하고 다음 패키지 설치를 계속 진행
#
# [호출 규약]
#   install_pkg.sh <SW_VERSION>
#   (예: pkg_apr_64b -> "apr_64b" 전달)
# ==========================================================

# ==========================================================
# 1. 공통 환경 변수 및 로깅 함수 로드
# ==========================================================
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
COMMON_ENV="$CONFIG_DIR/linux_common.env"

if [ -f "$COMMON_ENV" ]; then
    source "$COMMON_ENV"
else
    echo "[ERROR] 공통 설정 파일($COMMON_ENV)을 찾을 수 없습니다."
    exit 1
fi

# ==========================================================
# 2. 호스트별 환경설정 로드
# ==========================================================
TARGET_HOSTNAME=$(hostname -s)
HOST_ENV_FILE="$CONFIG_DIR/env/${TARGET_HOSTNAME}.env"

if [ -f "$HOST_ENV_FILE" ]; then
    source "$HOST_ENV_FILE"
else
    log_warn "호스트 설정 파일($HOST_ENV_FILE)이 존재하지 않아 기본 설정으로 진행합니다."
fi

# ==========================================================
# 3. 입력 파라미터 검증
# ==========================================================
SW_VER="$1"
if [ -z "$SW_VER" ]; then
    log_error "필수 파라미터(SW_VERSION)가 누락되었습니다."
    exit 1
fi

log_info ">>> [패키지 설치 시작] 대상: $SW_VER"

# ==========================================================
# 4. OS 버전 감지
# ==========================================================
if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(cat /etc/redhat-release)
    OS_MAJOR=$(echo "$OS_VERSION" | grep -oE '[0-9]+' | head -n 1)
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_VERSION="$VERSION_ID"
    OS_MAJOR=$(echo "$VERSION_ID" | cut -d'.' -f1)
else
    log_error "OS 버전을 확인할 수 없습니다."
    exit 1
fi
log_info "감지된 OS 환경: RHEL ${OS_MAJOR} 계열 (${OS_VERSION})"

# ==============================================================================
# 5. 패키지 명 추출 및 아키텍처 접미사 매핑
# ==============================================================================
ARCH_SUFFIX=""
if [[ "$SW_VER" == *"_64b" ]]; then
    ARCH_SUFFIX=".x86_64"
elif [[ "$SW_VER" == *"_32b" ]]; then
    ARCH_SUFFIX=".i686"
fi

# 문자열 끝의 아키텍처 구분자(_32b, _64b) 제거하여 순수 패키지 명 추출
CLEAN_PKG_NAME=$(echo "$SW_VER" | sed -E 's/(_32b|_64b)$//')

TARGET_PKGS=()
if [[ "$CLEAN_PKG_NAME" == *".x86_64"* ]] || [[ "$CLEAN_PKG_NAME" == *".i686"* ]]; then
    TARGET_PKGS+=("$CLEAN_PKG_NAME")
else
    TARGET_PKGS+=("${CLEAN_PKG_NAME}${ARCH_SUFFIX}")
fi

log_info "#################### 설치 대상 정보 ####################"
log_info "  - 입력 버전     : $SW_VER"
log_info "  - 추출 패키지명 : $CLEAN_PKG_NAME"
log_info "  - 아키텍처 접미사: ${ARCH_SUFFIX:-[없음]}"
log_info "  - 최종 설치 대상 : ${TARGET_PKGS[*]}"
log_info "######################################################"

# ==========================================================
# 6. dnf Repository 패키지 설치 (재시도 로직 적용)
# ==========================================================
log_info "[단계] dnf 설치 프로세스 진행 중..."

FAILED_PKGS=()
INSTALLED_PKGS=() # 실제로 설치된 정확한 패키지명을 저장

for pkg in "${TARGET_PKGS[@]}"; do
    log_info "설치 시도: $pkg"

    DNI_LOG=$(mktemp)
    # 1차 시도: 아키텍처 접미사가 포함된 이름으로 설치
    if sudo dnf install -y "$pkg" > "$DNI_LOG" 2>&1; then
        log_success " -> [성공] $pkg 설치 완료"
        INSTALLED_PKGS+=("$pkg")
    else
        # 2차 시도: 접미사를 제거한 순수 패키지명으로 재시도 (noarch 패키지 대응)
        PURE_NAME=$(echo "$pkg" | sed -E 's/(\.x86_64|\.i686)//')
        log_info "   - $pkg 찾지 못함. 순수 패키지명($PURE_NAME)으로 재시도..."

        if sudo dnf install -y "$PURE_NAME" > "$DNI_LOG" 2>&1; then
            log_success " -> [성공] $PURE_NAME (noarch 등) 설치 완료"
            INSTALLED_PKGS+=("$PURE_NAME")
        else
            log_error " -> [실패] $pkg 및 $PURE_NAME 모두 설치 불가"
            FAILED_PKGS+=("$pkg")
        fi
    fi
    rm "$DNI_LOG"
done

# ==========================================================
# 7. 모듈 내 설치 결과 검증 및 보고
# ==========================================================
log_info "--------------------------------------------------"
log_info " [모듈 검증] $SW_VER 설치 확인 결과"
log_info "--------------------------------------------------"

for pkg in "${INSTALLED_PKGS[@]}"; do
    # 설치된 패키지의 실제 아키텍처 정보 추출
    ACTUAL_ARCH=$(rpm -q --queryformat '%{ARCH}' "$pkg" 2>/dev/null)

    if [ $? -eq 0 ]; then
        # 요청한 비트와 실제 설치된 아키텍처 매칭 로그 생성
        if [[ "$SW_VER" == *"_64b"* ]] && [[ "$ACTUAL_ARCH" == "x86_64" ]]; then
            RESULT_TAG="[ OK ] (64bit 확인)"
        elif [[ "$SW_VER" == *"_32b"* ]] && [[ "$ACTUAL_ARCH" == "i686" ]]; then
            RESULT_TAG="[ OK ] (32bit 확인)"
        elif [[ "$ACTUAL_ARCH" == "noarch" ]]; then
            RESULT_TAG="[ OK ] (noarch 설치됨)"
        else
            RESULT_TAG="[ OK ] (아키텍처: $ACTUAL_ARCH)"
        fi
        log_info "  $RESULT_TAG 설치 확인됨 : $pkg"
    else
        log_error "  [FAIL] 미설치 확인됨 : $pkg"
    fi
done
log_info "--------------------------------------------------"

# 실패 목록이 있을 경우 해당 모듈의 실패 리스트 출력
if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
    echo ""
    log_error "  [모듈 에러] $SW_VER 설치 실패 항목"
    echo "--------------------------------------------------"
    for fail_pkg in "${FAILED_PKGS[@]}"; do
        echo "  - $fail_pkg"
    done
    echo "--------------------------------------------------"
    log_error "해당 모듈($SW_VER)의 일부 패키지 설치에 실패하였습니다."
    exit 1
fi

log_info ">>> [모듈 완료] $SW_VER 패키지 설치 프로세스가 정상 종료되었습니다."
exit 0
