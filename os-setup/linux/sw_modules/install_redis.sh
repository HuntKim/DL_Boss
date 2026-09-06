#!/bin/bash
# ==========================================================
# Redis 자동 설치 모듈 (install_redis.sh)
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
    log_error "설치할 Redis 버전 파라미터가 없습니다. (예: 6.2.22_64b)"
    exit 1
fi

if [ -z "$REDIS_PATH" ] || [ -z "$REDIS_OWNER" ]; then
    log_error "REDIS_PATH 또는 REDIS_OWNER 환경 변수가 정의되지 않았습니다. (common.env 확인)"
    exit 1
fi

REAL_VER=$(echo "$SW_VER" | cut -d'_' -f1)
DIR_NAME="redis_${SW_VER}"
TARGET_DIR="${REDIS_PATH%/}/redis"
USER_ONLY=$(echo "$REDIS_OWNER" | cut -d':' -f1)

log_info "[Redis 설치 시작 ($START_TIME_STR)] 버전: $REAL_VER | 대상경로: $TARGET_DIR | 소유자: $REDIS_OWNER"

# ==========================================================
# 3-2. 이미 설치된 경우 중복 설치 방지 (멱등성 보장)
# ==========================================================
if [ -x "$TARGET_DIR/bin/redis-server" ]; then
    # Redis는 'Redis server v=6.2.22 ...' 형태로 출력됨
    INSTALLED_VER=$("$TARGET_DIR/bin/redis-server" -v | grep -oE 'v=[0-9]+\.[0-9]+\.[0-9]+' | cut -d'=' -f2)
    if [ "$INSTALLED_VER" = "$REAL_VER" ]; then
        log_success "Redis($REAL_VER)이(가) 이미 경로($TARGET_DIR)에 설치되어 있습니다. 설치를 건너뜁니다."
        
        if ! ps -ef | grep "[r]edis-server" | grep -q "$TARGET_DIR"; then
            log_info "Redis 데몬이 꺼져 있어 재기동합니다..."
            su - "$USER_ONLY" -c "$TARGET_DIR/bin/redis-server $TARGET_DIR/conf/redis.conf"
        fi
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
# Redis는 순수 C언어로 작성되어 gcc와 make만 있으면 빌드 가능
REQUIREMENTS="gcc make"

log_info "Redis 컴파일에 필요한 필수 OS 패키지를 확인 및 설치합니다... (대상: $REQUIREMENTS)"

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
chown -R "$REDIS_OWNER" "$TARGET_DIR"

BUILD_DIR="${TEMP_DIR}/redis_build_${REAL_VER}"
mkdir -p "$BUILD_DIR"

cp "$SOURCE_FILE" "$BUILD_DIR/"
chown -R "$REDIS_OWNER" "$BUILD_DIR"
chown -R "$REDIS_OWNER" "$TEMP_DIR" 
chmod -R 755 "$TEMP_DIR"

# ==========================================================
# 6. 해당 유저로 변경하여 소스 컴파일 및 설치 진행
# ==========================================================
log_info "'$USER_ONLY' 계정으로 설치 파일 압축 해제 및 컴파일을 진행합니다."

# Redis는 ./configure 없이 바로 make를 수행하며, PREFIX 옵션으로 설치 경로 지정
BUILD_LOG=$(mktemp)
if su - "$USER_ONLY" -c "
    cd '$BUILD_DIR' &&
    tar -xf '$(basename "$SOURCE_FILE")' --strip-components=1 &&
    make -j\$(nproc) &&
    make PREFIX='$TARGET_DIR' install
" > "$BUILD_LOG" 2>&1; then
    log_success "Redis($REAL_VER) 컴파일 및 설치 완료: $TARGET_DIR"
    
    # 6-2. 설정 파일(redis.conf) 복사 및 독립 실행 환경 세팅
    su - "$USER_ONLY" -c "mkdir -p '$TARGET_DIR/conf'"
    cp "$BUILD_DIR/redis.conf" "$TARGET_DIR/conf/"
    chown "$REDIS_OWNER" "$TARGET_DIR/conf/redis.conf"
    
    # 일반 계정 기동 및 단독 폴더 운영을 위한 설정 파일 수정 (완벽한 격리)
    CONF_FILE="$TARGET_DIR/conf/redis.conf"
    sed -i 's/^daemonize no/daemonize yes/g' "$CONF_FILE"
    sed -i "s|^pidfile .*|pidfile $TARGET_DIR/redis.pid|g" "$CONF_FILE"
    sed -i "s|^logfile .*|logfile $TARGET_DIR/redis.log|g" "$CONF_FILE"
    sed -i "s|^dir .*|dir $TARGET_DIR/|g" "$CONF_FILE"
    log_info "Redis 독립 실행을 위한 설정 파일(redis.conf) 세팅이 완료되었습니다."
    
    rm -rf "$BUILD_DIR"
    rm -f "$BUILD_LOG"
else
    log_error "Redis 컴파일/설치 중 오류가 발생했습니다. 로그를 확인하세요."
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
fi

# ==========================================================
# 7. Redis 데몬 기동 테스트 및 프로세스 상주 증빙
# ==========================================================
log_info "Redis 데몬을 백그라운드로 기동합니다..."

# Redis 실행 (복사해 둔 설정 파일 바라보도록 지정)
su - "$USER_ONLY" -c "$TARGET_DIR/bin/redis-server $TARGET_DIR/conf/redis.conf"
sleep 3 # 프로세스 기동 대기

if ps -ef | grep "[r]edis-server" | grep -q "$TARGET_DIR"; then
    log_success "Redis 프로세스가 정상적으로 메모리에 상주했습니다 (ps -ef 검증 완료)."
    
    # 로그에 프로세스 기동 내역 증빙 남기기
    log_info "================ [ Redis 프로세스 기동 증빙 ] ================"
    ps -ef | grep "[r]edis-server" | grep "$TARGET_DIR" | while read -r line; do
        log_info " $line"
    done
    log_info "=============================================================="
    
else
    log_error "Redis 데몬 기동에 실패했습니다. 로그($TARGET_DIR/redis.log)를 확인하세요."
    exit 1
fi

# 기동 확인 후 다음 작업자를 위해 프로세스 안전 종료 (DB 덤프 저장 후 종료됨)
su - "$USER_ONLY" -c "$TARGET_DIR/bin/redis-cli shutdown"
log_info "설치 검증을 위한 Redis 임시 기동 테스트를 완료하고 데몬을 안전하게 종료했습니다."

# ==========================================================
# 8. 설치 완료 및 정리
# ==========================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "Redis($REAL_VER) 총 설치 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

rm -f "$SOURCE_FILE"

exit 0
