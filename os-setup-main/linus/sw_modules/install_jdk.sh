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

        strip_arch_suffix "$SW_VER"

        NORM_REQUEST_VER=$(normalize_version "$CORE_VERSION")

        # ----------------------------------------------------
        # 5-1-1. JDK 메이저 버전 판단 / 신·구 패키지 구조 구분
        #   - JDK 17부터(25 포함) Oracle RPM 패키지 구조가 바뀌어:
        #       a) --relocate 옵션이 동작하지 않고
        #       b) 패키지명이 "jdk_<버전>_<빌드>"(예: jdk_1.8.0_102)가
        #          아니라 "jdk-<메이저버전>"(예: jdk-25)로 고정되며,
        #          실제 설치 위치도 항상 /usr/java/jdk-<메이저버전>
        #          심볼릭 링크로 고정된다(요청한 INSTALL_PATH 무시).
        #     실측: rpm -qa jdk_25.0_2 로는 못 찾고, rpm -qa jdk-25 로
        #     조회해야 "jdk-25-25.0.2-10.x86_64" 로 확인됨.
        #   - "1.8.0.102"(9 미만 구표기)와 "17.0.2"/"25"(9 이상 신표기)를
        #     모두 처리하기 위해 두 패턴을 확인한다.
        # ----------------------------------------------------
        get_oracle_jdk_major_version() {
            local v="$1"
            if [[ "$v" =~ ^1\.([0-9]+)\. ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$v" =~ ^([0-9]+) ]]; then
                echo "${BASH_REMATCH[1]}"
            else
                echo ""
            fi
        }

        JDK_MAJOR=$(get_oracle_jdk_major_version "$NORM_REQUEST_VER")
        USE_RELOCATE=true
        if [ -n "$JDK_MAJOR" ] && [ "$JDK_MAJOR" -ge 17 ]; then
            USE_RELOCATE=false
        fi
        log_info "버전 파싱 결과: SW_VERSION=$SW_VER -> CORE_VERSION=$CORE_VERSION / ARCH_SUFFIX=$ARCH_SUFFIX / NORM_REQUEST_VER=$NORM_REQUEST_VER / JDK_MAJOR=${JDK_MAJOR:-미상} / relocate 지원=$USE_RELOCATE"

        # ----------------------------------------------------
        # 5-1-2. 설치 여부 사전 확인
        #   ※ 예전엔 Oracle JDK 배포 디렉토리 명명 규칙(jdk<버전>-<arch>)을
        #     추측해서 그 경로에 java 실행 파일이 있는지로 판단했으나,
        #     이 명명 규칙 자체가 업데이트 버전마다 계속 바뀌어왔다.
        #       - ~8u161      : jdk1.8.0_161          (접미사 없음)
        #       - 8u171~      : jdk1.8.0_171-amd64     (아키텍처 접미사 추가)
        #       - 8u421~      : jdk-1.8.0_421-oracle-x64 (패키지명 자체가 jdk-1.8로 변경)
        #       - 17/25(신규구조) : jdk-<메이저버전> (위 5-1-1 참고)
        #     그래서 경로를 미리 계산해 존재 여부를 판단하면 오탐(설치돼
        #     있는데 없다고 판단)이 발생할 수 있다(실제 사례: 8u102는
        #     접미사가 없는데 "-amd64"가 있다고 가정해 재설치를 시도하다
        #     rpm이 "이미 설치되어 있음"으로 실패).
        #     대신 openjdk 분기와 동일하게, 경로와 무관한 RPM 패키지 DB로
        #     직접 설치 여부를 확인한다.
        # ----------------------------------------------------
        if [ "$USE_RELOCATE" = false ]; then
            # 신규 구조(17+): 패키지명이 "jdk-<메이저버전>"으로 고정되고
            # 실제 설치 경로도 항상 /usr/java/jdk-<메이저버전> 고정.
            RPM_PKG_NAME="jdk-${JDK_MAJOR}"
            JAVA_BIN_HINT="/usr/java/jdk-${JDK_MAJOR}/bin/java"
            log_info "설치 여부 확인 (신규 패키지 구조, RPM 패키지명: $RPM_PKG_NAME, 요청 버전: $NORM_REQUEST_VER)"

            if INSTALLED_NVR=$(rpm -q "$RPM_PKG_NAME" 2>/dev/null) && [[ "$INSTALLED_NVR" == *"$NORM_REQUEST_VER"* ]] && [ -f "$JAVA_BIN_HINT" ]; then
                log_success "요청 버전($SW_VER)이 RPM으로 설치되어 있고 실행 파일이 확인되었습니다. 건너뜁니다: $INSTALLED_NVR"
                exit 0
            else
                log_info "패키지($RPM_PKG_NAME)가 없거나 요청 버전과 다르거나 실행 파일이 없습니다${INSTALLED_NVR:+ (현재 설치: $INSTALLED_NVR)}. 설치를 진행합니다."
            fi
        else
            # 기존 구조(~16): 패키지명 자체에 버전이 포함(jdk1.8.0_102 등)
            ORACLE_DIR_VER="${NORM_REQUEST_VER%.*}_${NORM_REQUEST_VER##*.}"
            RPM_PKG_NAME="jdk_${ORACLE_DIR_VER}"
            JAVA_BIN_HINT="$INSTALL_PATH/${RPM_PKG_NAME}/bin/java"
            log_info "설치 여부 확인 (RPM 패키지 기준): $RPM_PKG_NAME"

            if rpm -qa | grep -q "$ORACLE_DIR_VER" && [ -f "$JAVA_BIN_HINT" ]; then
                INSTALLED_PKG_INFO=$(rpm -qa | grep "$ORACLE_DIR_VER")
                log_success "요청 버전($SW_VER)이 RPM으로 설치되어 있고 실행 파일이 확인되었습니다. 건너뜁니다: $INSTALLED_PKG_INFO"
                exit 0
            else
                log_info "RPM 패키지가 없거나 실행 파일($JAVA_BIN_HINT)이 존재하지 않습니다. 재설치를 진행합니다."
            fi
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

        # Oracle 공식 RPM 설치 처리 (지원되는 버전만 relocate 적용)
        mkdir -p "$JAVA_HOME"
        mkdir -p "$INSTALL_PATH"

        if [ "$USE_RELOCATE" = true ]; then
            log_info "RPM 패키지 설치 진행 중 (relocate: $INSTALL_PATH)..."
            INSTALL_CMD=(sudo rpm -ivh --relocate "${JAVA_HOME}=${INSTALL_PATH}" "$SOURCE_FILE")
        else
            log_info "RPM 패키지 설치 진행 중 (기본 설치, relocate 미사용)..."
            INSTALL_CMD=(sudo rpm -ivh "$SOURCE_FILE")
        fi

        if "${INSTALL_CMD[@]}"; then
            log_success "Oracle JDK RPM 설치 완료."
            rm -f "$SOURCE_FILE"
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
        # 5-1-1. 1.8 마이너(업데이트) 버전 고정 설치
        #   - 리포지토리에 여러 1.8.0 업데이트 버전 RPM이 공존하므로,
        #     $SW_VER 에 담긴 마이너 버전이 아래 목록에 있으면 해당
        #     버전을 NEVR(name-epoch:version-release)로 정확히 지정해
        #     설치한다. (oracle_jdk 분기와 동일하게 strip_arch_suffix /
        #     normalize_version 을 재사용해 "1.8.0_232_64b", "8u232",
        #     "1.8.0.232" 등 표기가 달라도 동일하게 처리)
        #   - 마이너 버전이 없거나(예: "8", "1.8") 목록에 없으면 기존
        #     동작대로 최신 버전을 설치한다.
        #   - EVR 값은 RHEL8/RHEL9 리포지토리별로 각각 확인된 값만 등록되어
        #     있다. RHEL9에는 232 버전 RPM이 없어 목록에서 제외했다 —
        #     RHEL9에서 232가 요청되면 경고 후 최신 버전을 설치한다.
        #     그 외 OS_FAMILY(RHEL8/9가 아닌 경우)는 항상 최신 버전을 설치.
        # ----------------------------------------------------
        OPENJDK_PINNED_EVR=""
        if [ "$PKG_NAME" == "java-1.8.0-openjdk-devel" ]; then
            strip_arch_suffix "$SW_VER"
            NORM_SW_VER=$(normalize_version "$CORE_VERSION")
            UPDATE_NUM="${NORM_SW_VER##*.}"

            case "$OS_FAMILY" in
                RHEL8)
                    case "$UPDATE_NUM" in
                        432) OPENJDK_PINNED_EVR="1:1.8.0.432.b06-2.el8" ;;
                        402) OPENJDK_PINNED_EVR="1:1.8.0.402.b06-2.el8" ;;
                        322) OPENJDK_PINNED_EVR="1:1.8.0.322.b06-11.el8" ;;
                        232) OPENJDK_PINNED_EVR="1:1.8.0.232.b09-2.el8_1" ;;
                        *) OPENJDK_PINNED_EVR="" ;;
                    esac
                    ;;
                RHEL9)
                    case "$UPDATE_NUM" in
                        432) OPENJDK_PINNED_EVR="1:1.8.0.432.b06-3.el9" ;;
                        402) OPENJDK_PINNED_EVR="1:1.8.0.402.b06-2.el9" ;;
                        322) OPENJDK_PINNED_EVR="1:1.8.0.322.b06-9.el9" ;;
                        232)
                            log_warn "마이너 버전 232는 RHEL9용 고정 목록에 없어 최신 버전을 설치합니다. (요청 버전: $SW_VER)"
                            OPENJDK_PINNED_EVR=""
                            ;;
                        *) OPENJDK_PINNED_EVR="" ;;
                    esac
                    ;;
                *)
                    if [[ "$UPDATE_NUM" =~ ^(432|402|322|232)$ ]]; then
                        log_warn "마이너 버전 고정 목록은 RHEL8/RHEL9 기준으로만 등록되어 있어 $OS_FAMILY 에서는 적용하지 않습니다. 최신 버전을 설치합니다. (요청 버전: $SW_VER)"
                    fi
                    ;;
            esac
        fi

        if [ -n "$OPENJDK_PINNED_EVR" ]; then
            INSTALL_TARGET="${PKG_NAME}-${OPENJDK_PINNED_EVR}"
            # rpm -qa 출력은 기본적으로 epoch(1:) 없이 name-version-release.arch 로
            # 표기되므로, 설치 여부 확인 시에는 epoch를 제외한 문자열로 비교한다.
            CHECK_STRING="${PKG_NAME}-${OPENJDK_PINNED_EVR#*:}"
            log_info "마이너 버전 확인됨 ($SW_VER -> update $UPDATE_NUM). 고정 버전으로 설치합니다: $INSTALL_TARGET"
        else
            INSTALL_TARGET="$PKG_NAME"
            CHECK_STRING=""
            log_info "마이너 버전이 지정되지 않았거나 지원 목록에 없어 최신 버전을 설치합니다: $PKG_NAME"
        fi

        # ----------------------------------------------------
        # 5-2. 설치 여부 사전 확인 (rpm 패키지 DB 기준)
        # ----------------------------------------------------
        if [ -n "$CHECK_STRING" ]; then
            IS_INSTALLED=$(rpm -qa | grep -F "$CHECK_STRING")
        else
            IS_INSTALLED=$(rpm -q "$PKG_NAME" 2>/dev/null)
        fi

        # ----------------------------------------------------
        # 5-2-1. 마이너 버전 고정 설치 시 기존 버전과 나란히 유지
        #   - dnf/yum은 기본적으로 java-1.8.0-openjdk* 를 "같은 패키지의
        #     새 버전"으로 보고 자동 업그레이드(기존 마이너 버전 제거)
        #     한다. 그래서 232를 설치한 뒤 322를 설치하면 232가 지워진다.
        #   - dnf의 installonlypkgs 옵션(커널 패키지가 여러 버전 유지되는
        #     것과 동일한 메커니즘)에 이 패키지 계열을 넣으면 업그레이드
        #     대신 나란히 설치된다. /etc/dnf/dnf.conf를 영구 수정하는 대신
        #     이 설치 1회에만 --setopt으로 적용한다(다른 패키지에 영향 없음).
        #   - 마이너 버전을 지정하지 않은 "최신 설치" 요청은 기존과 동일하게
        #     단일 최신 버전만 유지한다(installonlypkgs 미적용).
        #   - installonly_limit 기본값은 3이라 동시 보관 버전이 4개를
        #     넘어가면 가장 오래된 버전이 자동 정리된다. 필요 시
        #     --setopt=installonly_limit=0(무제한)을 추가로 고려할 것.
        # ----------------------------------------------------
        INSTALL_CMD=(sudo "$PKG_MANAGER" install -y)
        if [ -n "$OPENJDK_PINNED_EVR" ]; then
            PKG_BASE="${PKG_NAME%-devel}"
            INSTALL_CMD+=("--setopt=installonlypkgs=${PKG_BASE},${PKG_BASE}-headless,${PKG_BASE}-devel")
            log_info "마이너 버전 고정 설치이므로 installonlypkgs 적용 (기존 설치된 다른 마이너 버전 유지): ${PKG_BASE}*"
        fi
        INSTALL_CMD+=("$INSTALL_TARGET")

        if [ -n "$IS_INSTALLED" ]; then
            log_success "$INSTALL_TARGET 는 이미 설치되어 있습니다. 설치를 건너뜁니다: $IS_INSTALLED"
        elif "${INSTALL_CMD[@]}"; then
            log_success "$INSTALL_TARGET 패키지 설치 완료"
        else
            log_error "$INSTALL_TARGET 패키지 설치 실패"
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
