#!/bin/bash
# ==========================================================
# Python 자동 설치 모듈 (install_python.sh)
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

# 설치 시작 시간 측정 (타임스탬프)
START_TIME=$(date +%s)
START_TIME_STR=$(date "+%Y-%m-%d %H:%M:%S")

# ==========================================================
# 3. 파라미터 확인 및 변수 파싱 (하드코딩 파일명 제거)
# ==========================================================
SW_VER="$1"
if [ -z "$SW_VER" ]; then
    log_error "설치할 Python 버전 파라미터가 없습니다. (예: 3.10.9_64b)"
    exit 1
fi

if [ -z "$PYTHON_PATH" ] || [ -z "$PYTHON_OWNER" ]; then
    log_error "PYTHON_PATH 또는 PYTHON_OWNER 환경 변수가 정의되지 않았습니다. (common.env 확인)"
    exit 1
fi

REAL_VER=$(echo "$SW_VER" | cut -d'_' -f1)
DIR_NAME="python_${SW_VER}"
TARGET_DIR="${PYTHON_PATH%/}/python"
USER_ONLY=$(echo "$PYTHON_OWNER" | cut -d':' -f1)

log_info "[Python 설치 시작 ($START_TIME_STR)] 버전: $REAL_VER | 대상경로: $TARGET_DIR | 소유자: $PYTHON_OWNER"

# ==========================================================
# 3-2. 이미 설치된 경우 중복 설치 방지 (멱등성 보장)
# ==========================================================
if [ -x "$TARGET_DIR/bin/python3" ]; then
    INSTALLED_VER=$("$TARGET_DIR/bin/python3" --version 2>&1 | awk '{print $2}')
    if [ "$INSTALLED_VER" = "$REAL_VER" ]; then
        log_success "Python($REAL_VER)이(가) 이미 경로($TARGET_DIR)에 설치되어 있습니다. 설치를 건너뜁니다."
        
        # 심볼릭 링크만 재확인 및 갱신
        PYTHON_BIN_DIR="${TARGET_DIR}/bin"
        ln -sf "${PYTHON_BIN_DIR}/python3" "/usr/local/bin/python"
        ln -sf "${PYTHON_BIN_DIR}/python3" "/usr/local/bin/python3"
        ln -sf "${PYTHON_BIN_DIR}/pip3" "/usr/local/bin/pip"
        ln -sf "${PYTHON_BIN_DIR}/pip3" "/usr/local/bin/pip3"
        
        exit 0
    fi
fi

# ==========================================================
# 4. FILE_URL 분기: 동적 파일 탐색 및 확보
# ==========================================================

DOWNLOAD_URL_DIR="${FILE_URL%/}/${DIR_NAME}/"
mkdir -p "$TEMP_DIR"

log_info "원격 서버($DOWNLOAD_URL_DIR)에서 설치 파일 검색 중..."

# HTML 구조를 파싱하여 첫 번째 .tar, .tar.gz, .tar.xz 파일명을 추출
TAR_FILE_NAME=$(curl -s -k -L "$DOWNLOAD_URL_DIR" | grep -ioE 'href="[^"]+\.tar(\.[a-z0-9]+)?"' | cut -d'"' -f2 | grep -v "/" | head -n 1)

if [ -z "$TAR_FILE_NAME" ]; then
	log_error "원격 경로에서 압축 파일(.tar*)을 찾을 수 없습니다: $DOWNLOAD_URL_DIR"
	exit 1
fi

DOWNLOAD_URL="${DOWNLOAD_URL_DIR}${TAR_FILE_NAME}"
SOURCE_FILE="$TEMP_DIR/$TAR_FILE_NAME"

log_info "설치 파일을 다운로드합니다: $DOWNLOAD_URL"
if ! curl -f -s -k -L --retry 3 --retry-delay 3 "$DOWNLOAD_URL" -o "$SOURCE_FILE"; then
	log_error "다운로드 실패 (3회 재시도 초과): $DOWNLOAD_URL"
	exit 1
fi
chmod 644 "$SOURCE_FILE"
    

# ==========================================================
# 4-2. 필수 OS 패키지 자동 설치 (root 권한)
# ==========================================================
# RHEL 8/9 계열 필수 패키지 목록 정의
REQUIREMENTS="gcc gcc-c++ make zlib-devel openssl-devel libffi-devel sqlite-devel readline-devel bzip2-devel python3-devel"

log_info "Python 컴파일에 필요한 필수 OS 패키지를 확인 및 설치합니다... (대상: $REQUIREMENTS)"

# dnf를 통해 패키지 설치 진행 (실패 시에만 상세 로그를 기록)
DNI_LOG=$(mktemp)
if dnf install -y $REQUIREMENTS > "$DNI_LOG" 2>&1; then
    log_success "필수 패키지 준비 완료."
    rm -f "$DNI_LOG"
else
    log_error "필수 패키지 설치에 실패했습니다. dnf 레포지토리를 확인하세요."
    cat "$DNI_LOG"
    rm -f "$DNI_LOG"
    exit 1
fi

# ==========================================================
# 5. 대상 및 임시 빌드 디렉토리 생성, 권한 부여
# ==========================================================
# 최종 설치 경로
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi
chown -R "$PYTHON_OWNER" "$TARGET_DIR"

# 컴파일(조립)을 진행할 임시 작업 경로 생성
BUILD_DIR="${TEMP_DIR}/python_build_${REAL_VER}"
mkdir -p "$BUILD_DIR"

# [핵심] root 권한으로 원본 파일을 임시 작업장으로 복사해 옴 (권한 에러 원천 차단)
cp "$SOURCE_FILE" "$BUILD_DIR/"
COPIED_TAR="$BUILD_DIR/$(basename "$SOURCE_FILE")"

# 폴더와 복사된 파일의 소유권을 해당 SW 사용 계정으로 일괄 양도
chown -R "$PYTHON_OWNER" "$BUILD_DIR"
chown -R "$PYTHON_OWNER" "$TEMP_DIR"
chmod -R 755 "$TEMP_DIR"

# ==========================================================
# 6. 해당 유저로 변경하여 소스 컴파일 및 설치 진행
# ==========================================================
log_info "'$USER_ONLY' 계정으로 설치 파일 압축 해제 및 컴파일을 진행합니다. (실패 시에만 상세 로그 기록)"

# 컴파일 및 설치의 상세 출력은 터미널에 안 보이게 하고, 실패 시에만 로그 파일에 남김
BUILD_LOG=$(mktemp)
if su - "$USER_ONLY" -c "
    cd '$BUILD_DIR' &&
    tar -xf '$(basename "$SOURCE_FILE")' --strip-components=1 &&
    ./configure --prefix='$TARGET_DIR' --enable-optimizations &&
    make -j\$(nproc) &&
    make install
" > "$BUILD_LOG" 2>&1; then
    log_success "Python($REAL_VER) 컴파일 및 설치 완료: $TARGET_DIR"
    rm -rf "$BUILD_DIR" # 임시 폴더 삭제
    rm -f "$BUILD_LOG"
else
    log_error "Python 컴파일/설치 중 오류가 발생했습니다. 로그를 확인하세요."
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
fi

# ==========================================================
# 6-2. 사내망 프록시용 pip.conf 사전 설정 (필요시 주석 해제 후 사용)
# ==========================================================
USER_HOME=$(eval echo "~$USER_ONLY")
PIP_CONF_DIR="$USER_HOME/.pip"

mkdir -p "$PIP_CONF_DIR"
chown -R "$PYTHON_OWNER" "$PIP_CONF_DIR"

cat <<EOF > "$PIP_CONF_DIR/pip.conf"
[global]
index-url = http://repository.samsungds.net/repository/proxy-pypi-files.pythonhosted.org/simple
trusted-host = repository.samsungds.net
EOF

chown "$PYTHON_OWNER" "$PIP_CONF_DIR/pip.conf"
chmod 644 "$PIP_CONF_DIR/pip.conf"
log_info "pip 프록시 설정을 위한 $PIP_CONF_DIR/pip.conf 파일을 생성했습니다."

# ==========================================================
# 7. 전역 실행을 위한 심볼릭 링크 설정
# ==========================================================
log_info "전역 실행을 위한 심볼릭 링크 설정을 진행합니다..."

PYTHON_BIN_DIR="${TARGET_DIR}/bin"

if [ -d "$PYTHON_BIN_DIR" ]; then
    ln -sf "${PYTHON_BIN_DIR}/python3" "/usr/local/bin/python"
    ln -sf "${PYTHON_BIN_DIR}/python3" "/usr/local/bin/python3"
    ln -sf "${PYTHON_BIN_DIR}/pip3" "/usr/local/bin/pip"
    ln -sf "${PYTHON_BIN_DIR}/pip3" "/usr/local/bin/pip3"
    log_success "심볼릭 링크 생성 완료 - /usr/local/bin/python 및 pip"
else
    log_warn "설치된 경로에 'bin' 디렉토리가 없어 심볼릭 링크 생성을 건너뜁니다."
fi

# ==========================================================
# 7-2. 추가 Python 라이브러리(pip) 자동 설치
# ==========================================================
if [ -n "$PYTHON_LIBRARIES" ]; then
    log_info "설정된 추가 Python 라이브러리 설치를 시작합니다..."
    
    if [[ "$PYTHON_LIBRARIES" == *"pyodbc"* ]]; then    
        # OS 버전 확인 (RHEL 9 여부 판단)    
        OS_VERSION=$(cat /etc/redhat-release | grep -oE 'release [0-9]+')    
            
        if [[ "$OS_VERSION" == *"release 9"* ]]; then    
            # ==========================================================    
            # [Case 1] RHEL 9 버전: 지정된 URL에서 파일 다운로드 후 설치    
            # ==========================================================    
            log_info "[RHEL 9 감지] pyodbc 종속성(unixODBC 및 unixODBC-devel 2.3.12)을 파일 다운로드 방식으로 설치합니다."    
                
            ODBC_URL="${FILE_URL%/}/pkg_unixODBC_2.3.12_64b/"    
            DEV_URL="${FILE_URL%/}/pkg_unixODBC-devel_2.3.12_64b/"    
            ODBC_RPM=$(curl -s -k -L "$ODBC_URL" | grep -ioE '[a-zA-Z0-9._-]+\.rpm' | head -n 1)    
            DEV_RPM=$(curl -s -k -L "$DEV_URL" | grep -ioE '[a-zA-Z0-9._-]+\.rpm' | head -n 1)    
                
            if [ -z "$ODBC_RPM" ] || [ -z "$DEV_RPM" ]; then    
                log_error "원격 경로에서 unixODBC RPM 파일을 찾을 수 없습니다."    
                exit 1    
            fi

            curl -f -s -k -L "${ODBC_URL}${ODBC_RPM}" -o "$TEMP_DIR/$ODBC_RPM"    
            curl -f -s -k -L "${DEV_URL}${DEV_RPM}" -o "$TEMP_DIR/$DEV_RPM"    
                
            DNI_ODBC_LOG=$(mktemp)    
            if dnf install -y "$TEMP_DIR/$ODBC_RPM" "$TEMP_DIR/$DEV_RPM" > "$DNI_ODBC_LOG" 2>&1; then    
                log_success "unixODBC 및 unixODBC-devel(2.3.12) 로컬 설치 완료."    
                rm -f "$DNI_ODBC_LOG" "$TEMP_DIR/$ODBC_RPM" "$TEMP_DIR/$DEV_RPM"    
            else    
                log_error "unixODBC 로컬 설치 실패. 로그 확인: $(cat $DNI_ODBC_LOG)"    
                rm -f "$DNI_ODBC_LOG" "$TEMP_DIR/$ODBC_RPM" "$TEMP_DIR/$DEV_RPM"    
                exit 1    
            fi    
        else    
            # ==========================================================    
            # [Case 2] RHEL 8 등 그 외 버전: 표준 dnf install 시도    
            # ==========================================================    
            log_info "[RHEL 8/기타 감지] pyodbc 종속성(unixODBC 및 unixODBC-devel)을 표준 dnf install로 설치합니다."    
                
            DNI_ODBC_LOG=$(mktemp)    
            if dnf install -y unixODBC unixODBC-devel > "$DNI_ODBC_LOG" 2>&1; then    
                log_success "unixODBC 및 unixODBC-devel 표준 설치 완료."    
                rm -f "$DNI_ODBC_LOG"    
            else    
                log_error "unixODBC 표준 설치 실패. 로그 확인: $(cat $DNI_ODBC_LOG)"    
                rm -f "$DNI_ODBC_LOG"    
                exit 1    
            fi    
        fi    
    fi    
    
    # 1. 겉을 감싸고 있는 불필요한 작은따옴표 제거
    CLEAN_LIBS=$(echo "$PYTHON_LIBRARIES" | tr -d "'")
    
    # 2. 특수기호(<, >) 쉘 충돌 방지를 위해 임시 requirements.txt 생성
    REQ_FILE="$TEMP_DIR/pip_req_$$.txt"
    # 공백을 줄바꿈으로 변경하여 텍스트 파일에 저장 (한 줄에 패키지 하나씩)
    echo "$CLEAN_LIBS" | tr ' ' '\n' > "$REQ_FILE"
    
    # 권한 문제 방지를 위해 소유권 변경
    chown "$USER_ONLY" "$REQ_FILE"
    
    PIP_LOG=$(mktemp)
    if su - "$USER_ONLY" -c "export PYTHONNOUSERSITE=1 && \"$TARGET_DIR/bin/pip3\" install --upgrade pip && \"$TARGET_DIR/bin/pip3\" install -r \"$REQ_FILE\"" > "$PIP_LOG" 2>&1; then
        log_success "추가 Python 라이브러리 설치 완료."
        rm -f "$PIP_LOG" "$REQ_FILE"
    else
		log_error "일부 Python 라이브러리 설치에 실패했습니다. 로그 파일을 확인하세요."
		cat "$PIP_LOG"
		rm -f "$PIP_LOG" "$REQ_FILE"
		exit 1
	fi
else
    log_info "설정된 추가 Python 라이브러리가 없어 설치를 건너뜁니다."
fi

# ==========================================================
# 8. 설치 완료 및 버전/라이브러리 연동 확인
# ==========================================================
log_info "설치된 Python 경로 및 라이브러리 연동 상태를 확인합니다..."

LINK_PATH=$(readlink -f /usr/local/bin/python3)
if [[ "$LINK_PATH" == *"$TARGET_DIR"* ]]; then
    log_info "심볼릭 링크가 정확한 경로($LINK_PATH)를 가리키고 있습니다."
else
    log_error "심볼릭 링크가 잘못된 경로($LINK_PATH)를 가리키고 있습니다. 예상 경로: $TARGET_DIR"
    exit 1
fi

if "$TARGET_DIR/bin/python3" --version >/dev/null 2>&1; then
    INSTALLED_VER=$("$TARGET_DIR/bin/python3" --version 2>&1)
    
    if [ -n "$PYTHON_LIBRARIES" ]; then
        # 패키지명을 실제 임포트 가능한 모듈명으로 매핑 (예: python-dateutil -> dateutil)
        IMPORT_SUCCESS=true
        for lib in $PYTHON_LIBRARIES; do
            # ==, <, >, <=, >= 등 버전 비교 기호와 그 뒤의 버전 정보를 모두 제거하여 순수 패키지명만 추출
            pkg_name=$(echo "$lib" | sed -E 's/[<>=]+[a-zA-Z0-9._-]+//g')
            
            # 패키지명과 모듈명이 다른 경우 매핑
            module_name="$pkg_name"
            if [ "$pkg_name" = "python-dateutil" ]; then
                module_name="dateutil"
            fi
            
            if ! "$TARGET_DIR/bin/python3" -c "import $module_name" >/dev/null 2>&1; then
                log_error "라이브러리 import 실패: $pkg_name (모듈명: $module_name)"
                IMPORT_SUCCESS=false
                break
            fi
        done
        
        if [ "$IMPORT_SUCCESS" = true ]; then
            log_success "Python($INSTALLED_VER) 정상 작동 및 모든 라이브러리 연동 완료."
        else
            exit 1
        fi
    else
        log_success "Python($INSTALLED_VER) 정상 작동 확인 완료."
    fi
else
    log_error "설치 경로의 Python 실행 실패: $TARGET_DIR/bin/python3"
    exit 1
fi

# 설치 종료 시간 계산 및 소요 시간 출력
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "Python($REAL_VER) 총 설치 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

# 설치 및 검증이 완벽하게 끝난 후 임시 다운로드 파일 삭제
rm -f "$SOURCE_FILE"

exit 0
