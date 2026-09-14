#!/bin/bash
# ==========================================================
# SVN(Apache Subversion) 자동 설치 모듈 (install_svn.sh)
#
# [특이사항]
#   - 다른 SW 모듈(소스 컴파일 방식)과 달리, OS 패키지 저장소(dnf/apt)에
#     등록된 최신 버전을 그대로 설치한다. (버전 지정 다운로드 없음)
#   - 지원 OS: RHEL 8/9 계열(dnf), Ubuntu 22.04(apt)
#
# [호출 규약]
#   install_svn.sh [SW_VERSION]
#   - SW_VERSION은 로그 기록용 파라미터이며, 실제 설치 버전은 저장소의
#     최신 버전을 따른다. 파라미터 없이 호출해도 정상 동작한다.
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
    echo "[ERROR] $COMMON_ENV 파일이 없습니다. (로깅 불가)"
    exit 1
fi

# ==========================================================
# 2. 호스트별 환경설정 로드
# ==========================================================
TARGET_HOSTNAME=$(hostname -s)
HOST_ENV_FILE="$CONFIG_DIR/env/${TARGET_HOSTNAME}.env"

if [ -f "$HOST_ENV_FILE" ]; then
    source "$HOST_ENV_FILE"
fi

START_TIME=$(date +%s)
START_TIME_STR=$(date "+%Y-%m-%d %H:%M:%S")

# ==========================================================
# 3. 파라미터 확인
#    (버전 고정 설치가 아니므로 파라미터는 로그 표기용으로만 사용)
# ==========================================================
SW_VER="${1:-latest}"
log_info "[SVN 설치 시작 ($START_TIME_STR)] 요청 버전: $SW_VER (저장소 최신 버전으로 설치됩니다)"

# ==========================================================
# 4. OS 배포판 및 버전 감지 (RHEL 8/9, Ubuntu 22.04 지원)
# ==========================================================
OS_ID=""
OS_VERSION_ID=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_VERSION_ID="$VERSION_ID"
elif [ -f /etc/redhat-release ]; then
    OS_ID="rhel"
    OS_VERSION_ID=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -n 1)
else
    log_error "OS 배포판 정보를 확인할 수 없습니다. (/etc/os-release 없음)"
    exit 1
fi

OS_MAJOR=$(echo "$OS_VERSION_ID" | cut -d'.' -f1)
log_info "감지된 OS: ID=$OS_ID, VERSION=$OS_VERSION_ID (major: $OS_MAJOR)"

PKG_MGR=""
case "$OS_ID" in
    rhel|rocky|almalinux|centos)
        if [ "$OS_MAJOR" != "8" ] && [ "$OS_MAJOR" != "9" ]; then
            log_warn "RHEL 계열이지만 검증된 버전(8, 9)이 아닙니다. (감지값: $OS_VERSION_ID) 계속 진행합니다."
        fi
        PKG_MGR="dnf"
        ;;
    ubuntu)
        if [ "$OS_VERSION_ID" != "22.04" ]; then
            log_warn "Ubuntu 계열이지만 검증된 버전(22.04)이 아닙니다. (감지값: $OS_VERSION_ID) 계속 진행합니다."
        fi
        PKG_MGR="apt"
        ;;
    *)
        log_error "지원하지 않는 OS입니다: $OS_ID $OS_VERSION_ID (지원: RHEL 8/9, Ubuntu 22.04)"
        exit 1
        ;;
esac

log_info "사용할 패키지 매니저: $PKG_MGR"

# ==========================================================
# 5. 기존 설치 여부 확인 (멱등성 - 이미 있어도 최신화 시도)
# ==========================================================
if command -v svn >/dev/null 2>&1; then
    CURRENT_VER=$(svn --version --quiet 2>/dev/null)
    log_info "SVN이(가) 이미 설치되어 있습니다. (현재 버전: ${CURRENT_VER:-확인불가}) 최신 버전으로 갱신을 시도합니다."
else
    log_info "SVN이(가) 설치되어 있지 않습니다. 신규 설치를 진행합니다."
fi

# ==========================================================
# 6. 패키지 매니저별 SVN 최신 버전 설치
# ==========================================================
INSTALL_LOG=$(mktemp)

case "$PKG_MGR" in
    dnf)
        log_info "dnf를 통해 subversion 최신 버전을 설치합니다..."
        if dnf install -y subversion > "$INSTALL_LOG" 2>&1; then
            log_success "dnf install 완료."
        else
            log_error "dnf install 실패했습니다. dnf 레포지토리를 확인하세요."
            cat "$INSTALL_LOG"
            rm -f "$INSTALL_LOG"
            exit 1
        fi
        ;;
    apt)
        log_info "apt 패키지 목록을 갱신합니다 (apt-get update)..."
        # 서버에 등록된 무관한 서드파티 저장소 하나가 실패해도 apt-get update는
        # 논제로로 종료될 수 있다. 여기서 즉시 중단하지 않고 경고만 남긴 뒤,
        # 실제 설치(apt-get install) 성공 여부로 최종 성패를 판단한다.
        if ! apt-get update -y > "$INSTALL_LOG" 2>&1; then
            log_warn "apt-get update가 일부 저장소 오류와 함께 종료되었습니다. (아래 로그 참고) 설치를 계속 시도합니다."
            cat "$INSTALL_LOG"
        fi

        log_info "apt를 통해 subversion 최신 버전을 설치합니다..."
        if DEBIAN_FRONTEND=noninteractive apt-get install -y subversion > "$INSTALL_LOG" 2>&1; then
            log_success "apt install 완료."
        else
            log_error "apt install 실패했습니다. 로그를 확인하세요."
            cat "$INSTALL_LOG"
            rm -f "$INSTALL_LOG"
            exit 1
        fi
        ;;
esac

rm -f "$INSTALL_LOG"

# ==========================================================
# 7. 설치 결과 검증
# ==========================================================
if ! command -v svn >/dev/null 2>&1; then
    log_error "설치 명령은 성공했으나 svn 실행 파일을 찾을 수 없습니다. (PATH 확인 필요)"
    exit 1
fi

INSTALLED_VER=$(svn --version --quiet 2>/dev/null)
if [ -z "$INSTALLED_VER" ]; then
    log_error "svn 실행 파일은 존재하지만 버전 확인에 실패했습니다."
    exit 1
fi

log_success "SVN(Subversion) 설치 확인 완료. 설치된 버전: $INSTALLED_VER"

# ==========================================================
# 8. 설치 완료 및 정리
# ==========================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "SVN($INSTALLED_VER) 총 설치 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

exit 0
