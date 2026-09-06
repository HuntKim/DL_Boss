#!/bin/bash
# ==========================================================
# Nginx 자동 설치 모듈 (install_nginx.sh)
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
# 3. 파라미터 확인 및 변수 파싱
# ==========================================================
SW_VER="$1"
if [ -z "$SW_VER" ]; then
    log_error "설치할 Nginx 버전 파라미터가 없습니다. (예: 1.20.1_64b)"
    exit 1
fi

if [ -z "$NGINX_PATH" ] || [ -z "$NGINX_OWNER" ]; then
    log_error "NGINX_PATH 또는 NGINX_OWNER 환경 변수가 정의되지 않았습니다. (common.env 확인)"
    exit 1
fi

REAL_VER=$(echo "$SW_VER" | cut -d'_' -f1)
DIR_NAME="nginx_${SW_VER}"
TARGET_DIR="${NGINX_PATH%/}/nginx"
USER_ONLY=$(echo "$NGINX_OWNER" | cut -d':' -f1)

log_info "[Nginx 설치 시작 ($START_TIME_STR)] 버전: $REAL_VER | 대상경로: $TARGET_DIR | 소유자: $NGINX_OWNER"

# ==========================================================
# 3-2. 이미 설치된 경우 중복 설치 방지 (멱등성 보장)
# ==========================================================
if [ -x "$TARGET_DIR/sbin/nginx" ]; then
    # Nginx는 'nginx version: nginx/1.20.1' 형태로 표준 에러(stderr)에 출력됨
    INSTALLED_VER=$("$TARGET_DIR/sbin/nginx" -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$INSTALLED_VER" = "$REAL_VER" ]; then
        log_success "Nginx($REAL_VER)이(가) 이미 경로($TARGET_DIR)에 설치되어 있습니다. 설치를 건너뜁니다."
        
        exit 0
    fi
fi

# ==========================================================
# 4. FILE_URL 분기: 동적 파일 탐색 및 확보
# ==========================================================
DOWNLOAD_URL_DIR="${FILE_URL%/}/${DIR_NAME}/"
mkdir -p "$TEMP_DIR"

log_info "원격 서버($DOWNLOAD_URL_DIR)에서 설치 파일 검색 중..."

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
# 4-2. 필수 OS 패키지 자동 설치
# ==========================================================
# Nginx 컴파일 시 요구되는 최소 의존성 (PCRE, zlib, OpenSSL)
REQUIREMENTS="gcc make pcre-devel zlib-devel openssl-devel"

log_info "Nginx 컴파일에 필요한 필수 OS 패키지를 확인 및 설치합니다... (대상: $REQUIREMENTS)"

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
# 5. 대상 디렉토리 생성 및 권한 부여
# ==========================================================
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi
chown -R "$NGINX_OWNER" "$TARGET_DIR"

BUILD_DIR="${TEMP_DIR}/nginx_build_${REAL_VER}"
mkdir -p "$BUILD_DIR"

cp "$SOURCE_FILE" "$BUILD_DIR/"
chown -R "$NGINX_OWNER" "$BUILD_DIR"
chmod -R 755 "$BUILD_DIR"

# ==========================================================
# 6. 해당 유저로 변경하여 소스 컴파일 및 설치 진행
# ==========================================================
log_info "'$USER_ONLY' 계정으로 설치 파일 압축 해제 및 컴파일을 진행합니다."

# 임시 폴더와 다운로드 파일의 소유권 OWNER에게 양도 
chown -R "$NGINX_OWNER" "$TEMP_DIR"  # (각 모듈에 맞는 OWNER 변수 사용: $NODEJS_OWNER 등)  
chmod -R 755 "$TEMP_DIR"

BUILD_LOG=$(mktemp)
if su - "$USER_ONLY" -c "
    cd '$BUILD_DIR' &&
    tar -xf '$(basename "$SOURCE_FILE")' --no-same-owner --strip-components=1 &&
    ./configure --prefix='$TARGET_DIR' \
                --with-http_ssl_module \
                --with-http_v2_module \
                --with-cc-opt='-Wno-error' && \
    make -j\$(nproc) &&
    make install
" > "$BUILD_LOG" 2>&1; then
    log_success "Nginx($REAL_VER) 컴파일 및 설치 완료: $TARGET_DIR"
    rm -rf "$BUILD_DIR"
    rm -f "$BUILD_LOG"
else
    log_error "Nginx 컴파일/설치 중 오류가 발생했습니다. 로그를 확인하세요."
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
fi

# ==========================================================
# 7. Nginx 데몬 직접 기동 및 프로세스 확인 (Service 미사용)
# ==========================================================
log_info "Nginx 데몬을 백그라운드로 기동합니다..."

# Non-root 계정일 경우 80번 포트 바인딩 에러를 방지하기 위해 기본 포트를 8090으로 임시 변경
if [ "$USER_ONLY" != "root" ]; then
    sed -i 's/listen       80;/listen       8090;/g' "$TARGET_DIR/conf/nginx.conf"
    log_info "Non-root 계정 실행을 위해 기본 Listen 포트를 8090으로 변경했습니다."
fi

# Nginx 실행
su - "$USER_ONLY" -c "$TARGET_DIR/sbin/nginx"
sleep 5 # 프로세스가 완전히 뜰 때까지 잠시 대기

if ps -ef | grep "[n]ginx: master process" | grep -q "$TARGET_DIR"; then
    log_success "Nginx 프로세스가 정상적으로 메모리에 상주했습니다 (ps -ef 검증 완료)."
	
	log_info "================ [ Nginx 프로세스 기동 증빙 ] ================"
    ps -ef | grep "[n]ginx" | grep "$TARGET_DIR" | while read -r line; do
        log_info " $line"
    done
    log_info "=============================================================="
	
else
    log_error "Nginx 데몬 기동에 실패했습니다. (포트 충돌 또는 권한 문제 확인 필요)"
    exit 1
fi

# 기동 확인이 끝났으므로 다음 작업자를 위해 프로세스 종료
su - "$USER_ONLY" -c "$TARGET_DIR/sbin/nginx -s quit"
log_info "설치 검증을 위한 Nginx 임시 기동 테스트를 완료하고 데몬을 종료했습니다."

# ==========================================================
# 8. 설치 완료 및 정리
# ==========================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "Nginx($REAL_VER) 총 설치 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

rm -f "$SOURCE_FILE"

exit 0
