#!/bin/bash
# ==========================================================
# install_jdk.sh
# 호출 규약: install_jdk.sh <SW_TYPE> <SW_VERSION> <INSTALL_PATH>
#   SW_TYPE     : oracle-jdk | openjdk
#   SW_VERSION  : ex) 8u172, 1.8.0.202, 1.7.0.16, 11.0.x
#   INSTALL_PATH: 설치(또는 relocate) 대상 경로
# ==========================================================

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
log_info "COMMON_ENV==${COMMON_ENV}"

# hostname 대신 hostname -s 사용: FQDN(도메인 포함)으로 설정된 서버에서도
# 매핑 테이블의 짧은 호스트명과 어긋나지 않도록 함
TARGET_HOSTNAME=$(hostname -s)
log_info "CONFIG_DIR = $CONFIG_DIR"
mkdir /usr/java

# ==========================================================
# 2. 호스트 전용 환경설정 로드 (config/env 디렉토리 참조)
#    ※ setup_sw.sh가 이미 로드했더라도 이 모듈은 별도 프로세스로
#      실행되므로(subshell) 변수를 물려받지 못해 다시 로드해야 함
# ==========================================================
HOST_ENV_FILE="$CONFIG_DIR/env/${TARGET_HOSTNAME}.env"

if [ -f "$HOST_ENV_FILE" ]; then
    source "$HOST_ENV_FILE"
    log_info "호스트 전용 환경설정 로드 완료: ${TARGET_HOSTNAME}.env"
else
    log_warn "호스트 전용 환경설정 파일이 없습니다: $HOST_ENV_FILE (경로 변수가 필요한 SW는 실패할 수 있습니다)"
fi

# 호스트 env에 TARGET_JAVA_HOME이 있으면 그 값 사용, 없으면 common.env
# 기본값을 유지 (install_oracle.sh/install_perl.sh와 동일한 규약)
apply_target_override "JAVA_HOME"

# ==========================================================
# 3. 인자값 검증 (첫 번째: 타입, 두 번째: 버전, 세 번째: 경로)
# ==========================================================
SW_TYPE=$1
SW_VER=$2
INSTALL_PATH=$3

if [ -z "$SW_TYPE" ] || [ -z "$SW_VER" ] || [ -z "$INSTALL_PATH" ]; then
    log_error "필수 인자값이 누락되었습니다. (Type: $SW_TYPE, Ver: $SW_VERSION, Path: $INSTALL_PATH)"
    exit 1
fi

log_info "=== JDK 설치 모듈 시작 (타입: $SW_TYPE, 버전: $SW_VER, 경로: $INSTALL_PATH) ==="

DIR_NAME="${SW_TYPE}_${SW_VER}"
log_info "DIR_NAME==${DIR_NAME}"

# ==========================================================
# 4. OS 버전 감지 (RHEL 8 / RHEL 9 호환)
# ==========================================================
if [ -f /etc/redhat-release ]; then
    OS_REL=$(cat /etc/redhat-release)
else
    log_error "/etc/redhat-release 파일을 찾을 수 없습니다."
    exit 1
fi

if [[ "$OS_REL" == *"release 8"* ]]; then
    OS_FAMILY="RHEL8"
    PKG_MANAGER="yum"
elif [[ "$OS_REL" == *"release 9"* ]]; then
    OS_FAMILY="RHEL9"
    PKG_MANAGER="dnf"
else
    log_error "지원하지 않는 OS 버전입니다: $OS_REL"
    exit 1
fi
log_info "감지된 OS: $OS_FAMILY (패키지 관리자: $PKG_MANAGER)"

# ==========================================================
# 4-1. 버전 문자열 정규화 함수 / 아키텍처 접미사 분리 함수
#   - normalize_version: "8u172", "1.8.0.202", "1.8.0_202" 등 표기가
#     제각각인 버전 문자열을 "1.8.0.202" 같은 dot 표기로 통일한다.
#   - strip_arch_suffix: setup_sw.sh -> sw_mapping_linux.txt 경로로
#     넘어오는 SW_VERSION에는 "_32b"/"_64b" 아키텍처 접미사가 붙어
#     있으므로(예: 1.8.0_202_64b) 순수 버전과 아키텍처를 분리한다.
#     접미사가 없는 경우(직접 호출 시)는 64bit로 간주한다.
# ==========================================================
normalize_version() {
    local v="$1"
    # "8u172" 형식(메이저버전+u+업데이트번호) -> "1.8.0.172" 형식으로 변환
    if [[ "$v" =~ ^([0-9]+)u([0-9]+)$ ]]; then
        echo "1.${BASH_REMATCH[1]}.0.${BASH_REMATCH[2]}"
        return
    fi
    # "1.8.0_202" 같은 표기는 '_' 를 '.' 으로 통일
    echo "$v" | tr '_' '.'
}

strip_arch_suffix() {
    local v="$1"
    if [[ "$v" =~ ^(.+)_(32b|64b)$ ]]; then
        CORE_VERSION="${BASH_REMATCH[1]}"
        ARCH_SUFFIX="${BASH_REMATCH[2]}"
    else
        CORE_VERSION="$v"
        ARCH_SUFFIX="64b"
    fi
}

# ==========================================================
# 5. 타입별 설치 로직 분기
# ==========================================================
case "$SW_TYPE" in
    "oracle_jdk")
        log_info "Oracle JDK 설치 진행..."

        # ----------------------------------------------------
        # 5-1. 설치 여부 사전 확인
        #   ※ 예전엔 Oracle JDK 배포 디렉토리 명명 규칙(jdk<버전>-<arch>)을
        #     추측해서 그 경로에 java 실행 파일이 있는지로 판단했으나,
        #     이 명명 규칙 자체가 업데이트 버전마다 계속 바뀌어왔다.
        #       - ~8u161      : jdk1.8.0_161          (접미사 없음)
        #       - 8u171~      : jdk1.8.0_171-amd64     (아키텍처 접미사 추가)
        #       - 8u421~      : jdk-1.8.0_421-oracle-x64 (패키지명 자체가 jdk-1.8로 변경)
        #     그래서 경로를 미리 계산해 존재 여부를 판단하면 오탐(설치돼
        #     있는데 없다고 판단)이 발생할 수 있다(실제 사례: 8u102는
        #     접미사가 없는데 "-amd64"가 있다고 가정해 재설치를 시도하다
        #     rpm이 "이미 설치되어 있음"으로 실패).
        #     대신 openjdk 분기와 동일하게, 경로와 무관한 RPM 패키지 DB로
        #     직접 설치 여부를 확인한다. 이 시기의 Oracle JDK 8 RPM은
        #     패키지명 자체에 버전이 포함되어 있어(예: jdk1.8.0_102) 여러
        #     버전이 별도 패키지로 공존 가능하며, 정확히 이 버전의 패키지가
        #     설치돼 있는지만 확인하면 충분하다.
        # ----------------------------------------------------
        strip_arch_suffix "$SW_VER"

        NORM_REQUEST_VER=$(normalize_version "$CORE_VERSION")
        # "1.8.0.102" -> "1.8.0_102" (Oracle RPM 패키지명 규칙)
        ORACLE_DIR_VER="${NORM_REQUEST_VER%.*}_${NORM_REQUEST_VER##*.}"
        RPM_PKG_NAME="jdk_${ORACLE_DIR_VER}"
        log_info "=======NORM_REQUEST_VER=${NORM_REQUEST_VER},ORACLE_DIR_VER=${ORACLE_DIR_VER}==========="
        # 참고용 예상 실행 경로 (설치 후 안내 로그용. 위 사유로 100% 정확하다고
        # 보장할 수 없어 존재 여부 "판단"에는 쓰지 않는다)
        JAVA_BIN_HINT="$INSTALL_PATH/${RPM_PKG_NAME}/bin/java"

        log_info "버전 파싱 결과: SW_VERSION=$SW_VER -> CORE_VERSION=$CORE_VERSION / ARCH_SUFFIX=$ARCH_SUFFIX"
        log_info "설치 여부 확인 (RPM 패키지 기준): $RPM_PKG_NAME"

        if rpm -qa | grep $ORACLE_DIR_VER  &>/dev/null; then
            INSTALLED_PKG_INFO=$(rpm -qa | grep "$ORACLE_DIR_VER")
            log_success "요청 버전($SW_VER)이 이미 RPM으로 설치되어 있습니다. 설치를 건너뜁니다: $INSTALLED_PKG_INFO"
            exit 0
        else
            log_info "기존 RPM 설치 이력이 없습니다. 신규 설치를 진행합니다. (예상 실행 경로: $JAVA_BIN_HINT)"
        fi

        DOWNLOAD_URL_DIR="${FILE_URL}/${DIR_NAME}/"
        mkdir -p "$TEMP_DIR"
        log_info "타겟 RPM 탐색 URL: $DOWNLOAD_URL_DIR"

        # 디렉토리 리스팅에서 .rpm 파일명을 추출 (와일드카드로 직접 GET 불가하므로 목록을 먼저 받아 grep)
        TAR_FILE=$(curl -s -k -L "$DOWNLOAD_URL_DIR" | grep -ioE 'href="[^"]+\.rpm(\.[a-z0-9]+)?"' | cut -d'"' -f2 | grep -v "/" | head -n 1)
        log_info "TAR_FILE 탐색 : ${TAR_FILE}"
        if [ -z "$TAR_FILE" ]; then
            log_error "해당 디렉토리에서 RPM 파일을 찾을 수 없습니다: $DOWNLOAD_URL_DIR"
            exit 1
        fi

        log_info "대상 파일 확인: ${TAR_FILE}"

        DOWNLOAD_URL="${DOWNLOAD_URL_DIR}${TAR_FILE}"
        SOURCE_FILE="$TEMP_DIR/$TAR_FILE"

        log_info "설치 파일을 다운로드합니다: $DOWNLOAD_URL"
        if ! curl -f -s -k -L --retry 3 --retry-delay 3 "$DOWNLOAD_URL" -o "$SOURCE_FILE"; then
            log_error "파일 다운로드 실패: $DOWNLOAD_URL"
            exit 1
        fi

        if [ ! -f "$SOURCE_FILE" ]; then
            log_error "파일 다운로드 실패: $TAR_FILE"
            exit 1
        fi

        # Oracle 공식 RPM relocate 설치 처리
        log_info "RPM 패키지 설치 진행 중 (relocate: $INSTALL_PATH)..."
        mkdir -p "$JAVA_HOME"
        mkdir -p "$INSTALL_PATH"
        if sudo rpm -ivh --relocate "$JAVA_HOME"="$INSTALL_PATH" "$SOURCE_FILE"; then
            log_success "Oracle JDK RPM 설치 완료."
            rm -f "$SOURCE_FILEE"
        else
            log_error "RPM 설치 실패."
            rm -f "$SOURCE_FILE"
            exit 1
        fi
        ;;

    "openjdk")
        log_info "OpenJDK 설치 진행 ($OS_FAMILY 패키지 방식: $PKG_MANAGER)..."

        case "$SW_VER" in
            *1.8.0*|*8*)
                PKG_NAME="java-1.8.0-openjdk-devel"
                ;;
            *1.7.0*|*7*)
                PKG_NAME="java-1.7.0-openjdk-devel"
                ;;
            *11*)
                PKG_NAME="java-11-openjdk-devel"
                ;;
            *)
                log_error "지원하지 않는 OpenJDK 버전입니다: $SW_VERSION"
                exit 1
                ;;
        esac

        # ----------------------------------------------------
        # 5-2. 설치 여부 사전 확인 (rpm 패키지 DB 기준)
        # ----------------------------------------------------
        if rpm -q "$PKG_NAME" &>/dev/null; then
            log_success "$PKG_NAME 는 이미 설치되어 있습니다. 설치를 건너뜁니다."
        elif sudo "$PKG_MANAGER" install -y "$PKG_NAME"; then
            log_success "$PKG_NAME 패키지 설치 완료"
        else
            log_error "$PKG_NAME 패키지 설치 실패"
            exit 1
        fi

        ;;

    *)
        log_error "알 수 없는 Java 타입입니다: $SW_TYPE"
        exit 1
        ;;
esac

# ==========================================================
# 6. 완료 메시지 출력
# ==========================================================
log_success "JDK ($SW_TYPE - $SW_VERSION)가 성공적으로 설치되었습니다: $INSTALL_PATH"
