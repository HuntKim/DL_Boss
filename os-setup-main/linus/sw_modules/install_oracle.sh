#!/bin/bash
# ==========================================================
# Oracle 자동 설치 모듈 (install_oracle.sh)
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
    log_info "호스트 전용 환경설정 로드 완료: ${TARGET_HOSTNAME}.env"
else
    log_warn "호스트 전용 환경설정 파일이 없습니다: $HOST_ENV_FILE (경로 변수가 필요한 SW는 실패할 수 있습니다)"
fi

# 설치 시작 시간 측정 (타임스탬프)
START_TIME=$(date +%s)
START_TIME_STR=$(date "+%Y-%m-%d %H:%M:%S")

# ==========================================================
# 3. 파라미터 확인 및 변수 파싱 (하드코딩 파일명 제거)
# ==========================================================
SW_TYPE=$1
SW_VER=$2
ORACLE_HOME=$3

if [ -z "$SW_TYPE" ] || [ -z "$SW_VER" ] || [ -z "$ORACLE_HOME" ]; then
    log_error "필수 인자값이 누락되었습니다. (TYPE: $SW_TYPE, Ver: $SW_VER, ORACLE_HOME: $ORACLE_HOME)"
    exit 1
fi

log_info "=== Oracle Client 설치 모듈 시작 (TYPE: $SW_TYPE, 버전: $SW_VER, ORACLE_HOME: $ORACLE_HOME) ==="
DIR_NAME="${SW_TYPE}_${SW_VER}"
log_info "DIR_NAME==${DIR_NAME}"
# ==========================================================
# TODO: 실제 Oracle Client 설치 로직 구현
#
# 예시 1) RPM 저장소에서 받아 설치하는 경우 (install_jdk.sh 의 oracle-jdk 분기 참고)
#   DIR_URL="${SOFTWARE_REPO_URL}/oracle_${SW_VERSION}"
#   RPM_FILE=$(curl -sf "$DIR_URL/" | grep -oE '[^"]+\.rpm' | head -n 1)
#   ... 다운로드 후 rpm -ivh 또는 yum/dnf localinstall ...
#
# 예시 2) zip 아카이브를 받아 압축 해제하는 경우
#   DIR_URL="${SOFTWARE_REPO_URL}/oracle_${SW_VERSION}"
#   ZIP_FILE=$(curl -sf "$DIR_URL/" | grep -oE '[^"]+\.zip' | head -n 1)
#   ... 다운로드 후 unzip -o "$ZIP_FILE" -d "$INSTALL_PATH" ...
#
# 설치 후에는 반드시 정상 종료(exit 0) / 실패 시 exit 1 로 결과를 알려주세요.
# ==========================================================

# ==============================================================================
# 1-1. 호스트 전용(TARGET_*) Oracle 환경변수 우선 적용
#   test.env(호스트별 env)에 TARGET_ORACLE_HOME 처럼 TARGET_ 접두사가 붙은
# 1-1. 호스트 전용(TARGET_*) Oracle 환경변수 우선 적용
#   test.env(호스트별 env)에 TARGET_ORACLE_HOME 처럼 TARGET_ 접두사가 붙은
#   값이 있으면 그 값을 사용하고, 없으면 linux_common.env의 공통 값을
#   그대로 사용한다. apply_target_override 함수는 linux_common.env에
#   정의되어 있음(스크립트 상단에서 이미 로드됨).
# ==============================================================================
for _v in ORACLE_HOME ORACLE_BASE STAGE_DIR UNIX_GROUP_NAME INVENTORY_LOCATION; do
    apply_target_override "$_v"
done
unset _v

# ==============================================================================
# 1-2. 설치 여부 사전 확인
#   ORACLE_HOME 하위에 sqlplus가 이미 존재하면 이미 설치된 것으로 간주하고
#   이후 단계(패키지 설치/다운로드/runInstaller)를 모두 건너뛴다.
#   ※ Oracle Client는 sqlplus -v 출력이 세부 패치 버전(예: 19.3 vs 19.25)을
#     정확히 구분해 보여주지 않는 경우가 많아, 여기서는 "설치 여부"만
#     판단한다. 패치 버전까지 엄격히 맞춰야 한다면 INVENTORY_LOCATION의
#     inventory.xml을 함께 확인하는 로직 추가를 검토해야 한다.
# ==============================================================================
if [ -x "${ORACLE_HOME}/bin/sqlplus" ]; then
    INSTALLED_INFO=$("${ORACLE_HOME}/bin/sqlplus" -v 2>&1 | grep -i "Release" | head -n 1)
    log_info "기존 설치 감지: ${ORACLE_HOME}/bin/sqlplus"
    [ -n "$INSTALLED_INFO" ] && log_info "설치된 버전 정보: $INSTALLED_INFO"
    log_success "Oracle Client가 이미 설치되어 있습니다 (${ORACLE_HOME}). 설치를 건너뜁니다."
    exit 0
else
    log_info "기존 설치 파일이 없습니다 (${ORACLE_HOME}/bin/sqlplus). 신규 설치를 진행합니다."
fi


# ==============================================================================
# 2. OS 버전 별 필수 패키지 설치 및 정상 설치 검증 (최대 3회 재시도)
# ==============================================================================
log_info "필수 dnf 패키지 설치 검증을 시작합니다."

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
log_info "OS_VERSION 원본 문자열: ${OS_VERSION}"
log_info "감지된 메이저 버전: ${OS_MAJOR}"

TARGET_PKGS=()

# ※ 기존 코드는 RHEL9에서도 실수로 RL8_ORA_PKG를 사용하고 있었고,
#   [[ "$OS_VERSION" =~ "^8" ]] 처럼 패턴을 따옴표로 감싸면 bash가
#   정규식이 아닌 리터럴 문자열 "^8"을 찾아버려 사실상 죽은 코드였음.
#   OS_MAJOR(숫자만 추출)를 기준으로 한 case문으로 교체.
case "$OS_MAJOR" in
    8)
        log_info "감지된 OS: RHEL 8 계열 (${OS_VERSION})"
        TARGET_PKGS=("${RL8_ORA_PKG[@]}")
        OEL_VALUE="OEL7.8"
        ;;
    9)
        log_info "감지된 OS: RHEL 9 계열 (${OS_VERSION})"
        TARGET_PKGS=("${RL9_ORA_PKG[@]}")
        OEL_VALUE="OL8"
        ;;
    *)
        log_error "지원하지 않는 OS 버전입니다: ${OS_VERSION} (메이저 버전: ${OS_MAJOR})"
        exit 1
        ;;
esac
log_info "CV_ASSUME_DISTID로 사용할 값: ${OEL_VALUE}"
log_info "#################### 실행 대상 목록 ####################"
log_info "Repository 패키지 (${#TARGET_PKGS[@]}개): ${TARGET_PKGS[*]}"
log_info "######################################################"

# yum 패키지 설치 (최대 3회 재시도)
MAX_RETRIES=3
RETRY_COUNT=0
YUM_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    ((RETRY_COUNT++))
    log_info "패키지 설치 시도 중... (${RETRY_COUNT}/${MAX_RETRIES})"

    dnf install -y "${TARGET_PKGS[@]}"

    if [ $? -eq 0 ]; then
        log_info "yum 패키지 설치 명령이 성공적으로 완료되었습니다."
        YUM_SUCCESS=true
        break
    else
        log_warn "yum 패키지 설치 중 오류가 발생했습니다. (${RETRY_COUNT}/${MAX_RETRIES})"
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_info "5초 후 재시도합니다..."
            sleep 5
        fi
    fi
done

if [ "$YUM_SUCCESS" = false ]; then
    log_warn "${MAX_RETRIES}회 재시도 후에도 yum install 명령어 실행 중 일부 에러가 발생했습니다."
    log_warn "실제 필수 패키지 개별 설치 상태 검증 단계로 넘어갑니다."
fi

# 2-2. 패키지 개별 검증 (rpm -q)
log_info "필수 패키지 개별 설치 상태를 최종 점검합니다."

# ※ REQUIRED_PACKAGES가 linux_common.env/호스트 env 어디에도 정의되어 있지 않아
#   기존 코드는 이 루프가 항상 빈 배열을 돌아 "전부 통과"로 잘못 로그를 남겼음.
#   별도로 정의되어 있지 않으면 위에서 설치한 TARGET_PKGS 목록으로 검증한다.
if [ ${#REQUIRED_PACKAGES[@]} -eq 0 ]; then
    log_warn "REQUIRED_PACKAGES가 정의되어 있지 않아 TARGET_PKGS(${#TARGET_PKGS[@]}개) 목록으로 검증을 대체합니다."
    REQUIRED_PACKAGES=("${TARGET_PKGS[@]}")
fi

MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        log_info " [OK] 패키지 설치됨: $pkg"
    else
        log_error " [FAIL] 패키지 미설치: $pkg"
        MISSING_PACKAGES+=("$pkg")
    fi
done

# 미설치 패키지가 존재할 경우 중단
if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    log_error "다음 필수 패키지가 최종적으로 설치되지 않았습니다: ${MISSING_PACKAGES[*]}"
    log_error "패키지 설치 실패로 인해 오라클 클라이언트 설치 스크립트를 중단합니다."
    exit 1
else
    log_info "모든 필수 패키지가 성공적으로 설치 및 검증되었습니다."
fi

# ==============================================================================
# 3. 디렉토리 생성 및 권한 설정
# ==============================================================================
log_info "디렉토리 생성 및 권한을 설정합니다."

mkdir -p "$ORACLE_HOME" && log_info "디렉토리 생성 완료: $ORACLE_HOME" || log_error "디렉토리 생성 실패: $ORACLE_HOME"
mkdir -p "$INVENTORY_LOCATION" && log_info "디렉토리 생성 완료: $INVENTORY_LOCATION" || log_error "디렉토리 생성 실패: $INVENTORY_LOCATION"

# oracle 계정/그룹 존재 여부 사전 체크
if ! id "oracle" &>/dev/null; then
    log_error "oracle 계정이 존재하지 않습니다. 계정을 먼저 생성해주세요."
    exit 1
fi

chown -R $ORACLE_OWNER ${ORACLE_BASE}
chmod -R 755 ${ORACLE_BASE}

# ※ oraInventory(INVENTORY_LOCATION)는 관례상 ORACLE_BASE 하위가 아닌 별도
#   경로로 지정되는 경우가 흔하다. 그 경우 위 chown -R $ORACLE_OWNER ${ORACLE_BASE}
#   만으로는 oraInventory 소유권이 바뀌지 않아 root로 남고, oracle 계정으로
#   실행되는 runInstaller가 중앙 인벤토리(ContentsXML, orainstRoot.sh 생성 등)를
#   쓰지 못해 조용히 실패한다(oraInventory 안에 logs 디렉토리만 남는 증상으로
#   나타남). ORACLE_HOME/INVENTORY_LOCATION도 명시적으로 chown한다
#   (ORACLE_BASE 하위에 중첩돼 있어도 다시 적용될 뿐 무해함).
chown -R $ORACLE_OWNER "$ORACLE_HOME"
chmod -R 755 "$ORACLE_HOME"
chown -R $ORACLE_OWNER "$INVENTORY_LOCATION"
chmod -R 755 "$INVENTORY_LOCATION"

# ==============================================================================
# 4. Oracle 계정 작업 (파일 다운로드, 압축 해제, 설치)
# ==============================================================================
log_info "Oracle 설치 파일 준비 작업을 시작합니다."

# ※ 기존 코드는 SOFTWARE_REPO_URL(어디에도 정의되지 않음)을 참조하고 있어서
#   DIR_URL이 항상 "/oracle_${SW_VERSION}"처럼 base URL 없이 만들어졌고,
#   ORACLE_FILE_19C도 정의된 곳이 없어 curl이 파일명 없는 URL로 요청되면서
#   "curl: Remote file name has no length!" 로 실패했음.
#   linux_common.env에 정의된 BASE_URL(구 FILE_REPO_URL)을 사용하고,
#   install_jdk.sh(oracle_jdk 분기)와 동일하게 저장소 디렉토리 리스팅에서
#   zip 파일명을 동적으로 찾도록 변경.

DOWNLOAD_URL_DIR="${FILE_URL}/${DIR_NAME}/"
mkdir -p "$TEMP_DIR"
log_info "설치파일zip 탐색 URL: $DOWNLOAD_URL_DIR"

# 다운로드 대상 파일 확인
ZIP_FILE=$(curl -s -k -L "$DOWNLOAD_URL_DIR" | grep -ioE 'href="[^"]+\.zip(\.[a-z0-9]+)?"' | cut -d'"' -f2 | grep -v "/" | head -n 1)
log_info "탐색된 ZIP 파일명: ${ZIP_FILE:-(찾지 못함)}"

if [ -z "$ZIP_FILE" ]; then
    log_error "해당 디렉토리에서 zip 설치 파일을 찾을 수 없습니다: $DOWNLOAD_URL_DIR"
    log_error "저장소 경로 또는 SW_VERSION(${SW_VERS})을 확인해주세요."
    exit 1
fi
log_info "대상 파일 확인: ${ZIP_FILE}"

# 다운로드 시작
DOWNLOAD_URL="${DOWNLOAD_URL_DIR}${ZIP_FILE}"
SOURCE_FILE="${ORACLE_HOME}/${ZIP_FILE}"
log_info "다운로드 URL: $DOWNLOAD_URL"
#RSP_FILE="${ORACLE_HOME}/clientsetup.rsp"

# 4-1. 파일 다운로드 및 압축 해제
su - oracle << EOF
cd "${ORACLE_HOME}" || exit 1

log_sub() { echo -e "[oracle] \$1"; }

log_sub "bash_profile 환경변수 등록 중..."
grep -q "ORACLE_HOME=${ORACLE_HOME}" ~/.bash_profile || echo "export ORACLE_HOME=${ORACLE_HOME}" >> ~/.bash_profile
grep -q "UNIX_GROUP_NAME=${UNIX_GROUP_NAME}" ~/.bash_profile || echo "export UNIX_GROUP_NAME=${UNIX_GROUP_NAME}" >> ~/.bash_profile
grep -q "INVENTORY_LOCATION=${INVENTORY_LOCATION}" ~/.bash_profile || echo "export INVENTORY_LOCATION=${INVENTORY_LOCATION}" >> ~/.bash_profile
grep -q "LD_LIBRARY_PATH=$ORACLE_HOME/lib" ~/.bash_profile || echo "export LD_LIBRARY_PATH=$ORACLE_HOME/lib" >> ~/.bash_profile
grep -q "PATH=$ORACLE_HOME/bin" ~/.bash_profile || echo "export PATH=$ORACLE_HOME/bin:$PATH" >> ~/.bash_profile

log_sub "Client 설치 파일 다운로드 중... (${DOWNLOAD_URL})"
if ! curl -f -s -k -L --retry 3 --retry-delay 3 "$DOWNLOAD_URL" -o "$SOURCE_FILE"; then
    log_error "파일 다운로드 실패: $DOWNLOAD_URL"
    exit 1
fi

if [ ! -f "${SOURCE_FILE}" ]; then
    echo "[ERROR] 설치 파일 다운로드 실패! (${SOURCE_FILE} 없음)"
    exit 1
fi
log_sub "다운로드 완료: ${SOURCE_FILE} (\$(du -h "${SOURCE_FILE}" 2>/dev/null | cut -f1))"

log_sub "압축 해제 중... ${SOURCE_FILE}"
unzip -oq "${SOURCE_FILE}"
UNZIP_RC=\$?
log_sub "압축 해제 종료 코드: \${UNZIP_RC}"
exit \${UNZIP_RC}
EOF

if [ $? -ne 0 ]; then
    log_error "Oracle 설치 파일 압축 해제 중 오류가 발생했습니다."
    exit 1
fi

# ==============================================================================
# 4-1-1. libclntshcore.so.19.1 원본 백업 (RHEL9 등에서의 relink 실패 대비)
#   뒤에서 실행할 runInstaller가 client_sharedlib(relink) 단계를 시도하는데,
#   RHEL9는 glibc가 바뀌면서 relink가 참조하는 /usr/lib64/libpthread_nonshared.a
#   가 더 이상 존재하지 않아 relink가 실패한다(Oracle 19.3 base 릴리스가
#   RHEL9/OL9을 공식 인증하지 않아 생기는 알려진 문제). relink가 실패하면
#   방금 압축 해제로 정상 생성된 lib/libclntshcore.so.19.1이 사라지고
#   깨진 심볼릭 링크(libclntshcore.so)만 남아 sqlplus 등이 라이브러리 로딩에
#   실패한다. zip에 포함된 원본 파일 자체는 정상 동작하므로, 여기서 한 벌
#   백업해뒀다가 relink 실패가 감지되면 그대로 복구한다(RHEL8처럼 relink가
#   정상 성공하는 환경에서는 아래 복구 로직이 개입하지 않는다).
# ==============================================================================
ORIG_LIBCLNTSHCORE="${ORACLE_HOME}/lib/libclntshcore.so.19.1"
LIBCLNTSHCORE_BACKUP="${TEMP_DIR}/libclntshcore.so.19.1.zip-orig.${SW_VERSION}"
if [ -f "${ORIG_LIBCLNTSHCORE}" ] && [ ! -L "${ORIG_LIBCLNTSHCORE}" ]; then
    cp -f "${ORIG_LIBCLNTSHCORE}" "${LIBCLNTSHCORE_BACKUP}"
    log_info "relink 실패 대비 백업 완료: ${ORIG_LIBCLNTSHCORE} -> ${LIBCLNTSHCORE_BACKUP}"
else
    log_warn "압축 해제 직후 ${ORIG_LIBCLNTSHCORE} 파일을 찾지 못해 백업을 건너뜁니다. (버전에 따라 zip 내부 구조가 다를 수 있음)"
fi

# 4-2. root 권한에서 clientsetup.rsp 치환 및 전체 권한 소유권 재설정
log_info "clientsetup.rsp 경로 변수 치환 및 권한 재설정 실행..."
# 압축 풀린 전체 파일/디렉토리에 oracle 소유권 및 775/755 권한 부여
chown -R $ORACLE_OWNER ${ORACLE_BASE}
chmod -R 755 ${ORACLE_BASE}

### if [ -f "${RSP_FILE}" ]; then
###     sed -i "s|\\\$ORACLE_BASE|${ORACLE_BASE}|g" "${RSP_FILE}"
###     sed -i "s|\\\$ORACLE_HOME|${ORACLE_HOME}|g" "${RSP_FILE}"
###     sed -i "s|\\\$UNIX_GROUP_NAME|${UNIX_GROUP_NAME}|g" "${RSP_FILE}"
###     sed -i "s|\\\$INVENTORY_LOCATION|${INVENTORY_LOCATION}|g" "${RSP_FILE}"
###
###     log_info "rsp 파일 치환 완료. 치환 결과 점검:"
###     grep -E "ORACLE_BASE=|ORACLE_HOME=" "${RSP_FILE}" | grep -v "^#"
### else
###     log_error "${RSP_FILE} 파일을 찾을 수 없습니다."
###     exit 1
### fi

# 4-3. oracle 계정으로 runInstaller 실행
log_info "oracle 계정으로 runInstaller를 실행합니다. (CV_ASSUME_DISTID=${OEL_VALUE})"

su - oracle << EOF
cd "${ORACLE_HOME}" || exit 1

# ※ 기존 코드는 여기서 OS_VERSION을 다시 감지했는데, 이 su-oracle 블록이
#   따옴표 없는 heredoc(<< EOF)이라 "OS_VERSION=\$(cat /etc/redhat-release)"가
#   oracle 서브쉘이 아니라 지금 이 부모(root) 쉘에서 먼저 실행되어 버렸다.
#   그 결과 heredoc 안에는 따옴표 없이
#     OS_VERSION=Red Hat Enterprise Linux release 8.6 (Ootpa)
#   같은 텍스트가 그대로 박혀서 oracle 서브쉘이 이 줄을 실행하는 순간
#   "syntax error near unexpected token '('" 로 죽어버리는 문제가 있었다.
#   section 2에서 이미 정확히 계산해 둔 OEL_VALUE(값 하나짜리 문자열이라
#   공백/괄호 문제 없이 안전하게 치환됨)를 그대로 재사용해서 재감지 자체를 없앴다.
echo "CV_ASSUME_DISTID = ${OEL_VALUE}"
export CV_ASSUME_DISTID=${OEL_VALUE}

CV_ASSUME_DISTID=${OEL_VALUE} ./runInstaller -silent \\
  -ignoreSysPrereqs \\
  -responseFile ${ORACLE_HOME}/install/response/clientsetup.rsp \\
  oracle.install.option=INSTALL_DB_SWONLY \\
  oracle.install.client.installType=Administrator \\
  ORACLE_HOSTNAME=$(hostname) \\
  UNIX_GROUP_NAME=${UNIX_GROUP_NAME} \\
  INVENTORY_LOCATION=${INVENTORY_LOCATION} \\
  ORACLE_HOME=${ORACLE_HOME} \\
  ORACLE_BASE=${ORACLE_BASE}
RUN_RC=\$?
echo "runInstaller 종료 코드: \${RUN_RC}"
exit \${RUN_RC}
EOF
RUNINSTALLER_RESULT=$?
log_info "runInstaller su 블록 종료 코드: ${RUNINSTALLER_RESULT}"

# ==============================================================================
# 4-4. libclntshcore.so.19.1 relink 실패 복구
#   -e는 심볼릭 링크가 깨져(대상 없음) 있어도 false를 반환하므로,
#   "파일이 아예 없는 경우"와 "깨진 링크만 남은 경우" 둘 다 잡아낸다.
#   RHEL8처럼 relink가 정상 성공했다면 이 조건은 항상 false라 개입하지 않는다.
# ==============================================================================
if [ ! -e "${ORIG_LIBCLNTSHCORE}" ] && [ -f "${LIBCLNTSHCORE_BACKUP}" ]; then
    log_warn "runInstaller relink(client_sharedlib) 단계에서 libclntshcore.so.19.1이 사라진 것을 감지했습니다."
    log_warn "(RHEL9 등에서 알려진 이슈: /usr/lib64/libpthread_nonshared.a 부재로 relink 실패) 백업해둔 원본으로 복구합니다."
    cp -f "${LIBCLNTSHCORE_BACKUP}" "${ORIG_LIBCLNTSHCORE}"
    chown oracle:"${UNIX_GROUP_NAME}" "${ORIG_LIBCLNTSHCORE}"
    chmod 755 "${ORIG_LIBCLNTSHCORE}"
    log_success "libclntshcore.so.19.1 복구 완료: ${ORIG_LIBCLNTSHCORE}"
fi

# ==============================================================================
# 5. Root 후속 스크립트 실행 (orainstRoot.sh)
# ==============================================================================
log_info "Oracle 설치 마무리 작업 시작 (orainstRoot.sh 실행 확인)"

ROOT_SCRIPT_1="${INVENTORY_LOCATION}/orainstRoot.sh"
ROOT_SCRIPT_2="${ORACLE_HOME}/orainstRoot.sh"

if [ -f "${ROOT_SCRIPT_1}" ]; then
    log_info "orainstRoot.sh 실행 중... (${ROOT_SCRIPT_1})"
    "${ROOT_SCRIPT_1}"
    log_info "orainstRoot.sh 실행 완료."
elif [ -f "${ROOT_SCRIPT_2}" ]; then
    log_info "orainstRoot.sh 실행 중... (${ROOT_SCRIPT_2})"
    "${ROOT_SCRIPT_2}"
    log_info "orainstRoot.sh 실행 완료."
else
    log_info "orainstRoot.sh 스크립트가 존재하지 않거나 이미 중앙 인벤토리가 생성되어 스킵되었습니다."
fi

# ==============================================================================
# 5-1. root 등 다른 계정에서도 공유 라이브러리를 찾을 수 있도록 시스템 전역 등록
#   oracle 계정은 ~/.bash_profile에 LD_LIBRARY_PATH=$ORACLE_HOME/lib 가 등록돼
#   sqlplus가 정상 동작하지만, root를 비롯한 다른 계정/프로세스는 이 값을
#   전혀 모른다. 그 결과 root에서 sqlplus 실행 시
#     "error while loading shared libraries: libsqlplus.so: cannot open
#      shared object file: no such file or directory"
#   가 발생한다. /etc/ld.so.conf.d/ 에 ORACLE_HOME/lib 경로를 등록하고
#   ldconfig을 실행하면 계정과 무관하게 동적 링커가 라이브러리를 찾을 수
#   있다(PATH에 sqlplus 자체를 추가하는 것은 별개이며, 여기서는 라이브러리
#   로딩 오류만 해결한다). 파일명을 고정해서 재설치/버전 변경 시 이전 경로가
#   쌓이지 않고 항상 최신 ORACLE_HOME으로 덮어써지도록 한다.
# ==============================================================================
log_info "시스템 전역 공유 라이브러리 경로 등록 (ldconfig)..."
LDCONF_FILE="/etc/ld.so.conf.d/oracle-client.conf"
echo "${ORACLE_HOME}/lib" > "$LDCONF_FILE"
if ldconfig; then
    log_success "ldconfig 등록 완료: ${LDCONF_FILE} -> ${ORACLE_HOME}/lib (root 등에서도 sqlplus 라이브러리 로딩 가능)"
else
    log_warn "ldconfig 실행에 실패했습니다. root 등 oracle 계정 외의 계정에서 sqlplus 실행 시 라이브러리 오류가 발생할 수 있습니다."
fi

# ==============================================================================
# 6. 설치 결과 최종 검증 (.bash_profile source 로드 추가)
# ==============================================================================
log_info "Oracle Client 설치 결과 검증 시작..."

su - oracle << 'EOF'
# 새로 등록된 환경변수를 반영하기 위해 source 호출
source ~/.bash_profile

if command -v sqlplus &>/dev/null; then
    echo "[SUCCESS] sqlplus 실행 가능 확인:"
    sqlplus -v
else
    echo "[ERROR] sqlplus 명령어를 찾을 수 없거나 실행할 수 없습니다."
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    log_info "=================================================="
    log_info " ★ Oracle Client 설치 완료"
    log_info "  - 버전     : ${SW_VERSION}"
    log_info "  - ORACLE_HOME : ${ORACLE_HOME}"
    log_info "  - 완료시각 : $(date)"
    log_info "                                                  "
    log_info "                                                  "
    log_info "                                                  "
    log_info "                                                  "
    log_info "                                                  "
    log_info "=================================================="
else
    log_error "★ Oracle Client 설치 검증 실패 ★"
    exit 1
fi

# ==============================================================================
# 7. tnsnames.ora 다운로드 및 배치
#   호스트별로 웹서버(FILE_URL/tnsnames/<hostname>.tnsnames.ora)에 미리 준비해
#   둔 tnsnames.ora를 받아 ${ORACLE_HOME}/network/admin/tnsnames.ora 에 배치한다.
#   위 검증에서 실패했다면 이미 exit 1로 스크립트가 끝났으므로, 이 아래는
#   Client 설치가 정상 완료된 경우에만 실행된다.
#   ※ 이 프로젝트의 기존 관례(호스트 전용 env 누락 시 경고+계속 등)를 따라,
#     tnsnames.ora 하나 못 받아왔다고 전체 설치를 실패 처리하지는 않는다.
#     웹서버에 해당 호스트용 파일이 아직 준비되지 않았을 수 있으므로
#     경고만 남기고 넘어간다.
# ==============================================================================
log_info "tnsnames.ora 배치 작업을 시작합니다."

TNSNAMES_URL="${FILE_URL}/tnsnames/${TARGET_HOSTNAME}.tnsnames.ora"
TNSNAMES_ADMIN_DIR="${ORACLE_HOME}/network/admin"
TNSNAMES_DEST="${TNSNAMES_ADMIN_DIR}/tnsnames.ora"

su - oracle << EOF
mkdir -p "${TNSNAMES_ADMIN_DIR}"

log_sub() { echo -e "[oracle] \$1"; }
log_sub "tnsnames.ora 다운로드 중... (${TNSNAMES_URL})"

if curl -f -s -k -L --retry 3 --retry-delay 3 "${TNSNAMES_URL}" -o "${TNSNAMES_DEST}"; then
    log_sub "tnsnames.ora 다운로드 완료: ${TNSNAMES_DEST}"
    exit 0
else
    log_sub "tnsnames.ora 다운로드 실패: ${TNSNAMES_URL}"
    exit 1
fi
EOF
TNSNAMES_RESULT=$?

if [ "${TNSNAMES_RESULT}" -eq 0 ]; then
    log_success "tnsnames.ora 배치 완료: ${TNSNAMES_DEST}"
else
    log_warn "tnsnames.ora 다운로드에 실패했습니다: ${TNSNAMES_URL}"
    log_warn "(웹서버에 이 호스트(${TARGET_HOSTNAME})용 tnsnames.ora가 준비되어 있는지 확인해주세요. Client 설치는 정상 완료된 상태이며 이 단계만 건너뜁니다.)"
fi
