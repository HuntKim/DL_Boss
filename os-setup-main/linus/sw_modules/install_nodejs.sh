#!/bin/bash
# ==========================================================
# Node.js 자동 설치 모듈 (install_nodejs.sh)
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
    log_error "설치할 Node.js 버전 파라미터가 없습니다. (예: 22.16.0_64b)"
    exit 1
fi

if [ -z "$NODEJS_PATH" ] || [ -z "$NODEJS_OWNER" ]; then
    log_error "NODEJS_PATH 또는 NODEJS_OWNER 환경 변수가 정의되지 않았습니다. (호스트 env 확인)"
    exit 1
fi

REAL_VER=$(echo "$SW_VER" | cut -d'_' -f1)
DIR_NAME="nodejs_${SW_VER}"
TARGET_DIR="${NODEJS_PATH%/}/nodejs"
USER_ONLY=$(echo "$NODEJS_OWNER" | cut -d':' -f1)

log_info "[Node.js 설치 시작 ($START_TIME_STR)] 버전: $REAL_VER | 대상경로: $TARGET_DIR | 소유자: $NODEJS_OWNER"

# ==========================================================
# 3-2. 이미 설치된 경우 중복 설치 방지 (멱등성 보장)
# ==========================================================
if [ -x "$TARGET_DIR/bin/node" ]; then
    # Node.js는 버전 확인 시 'v'가 붙어서 출력되므로 제거하여 비교 (예: v22.16.0 -> 22.16.0)
    INSTALLED_VER=$("$TARGET_DIR/bin/node" --version 2>&1 | sed 's/v//')
    if [ "$INSTALLED_VER" = "$REAL_VER" ]; then
        log_success "Node.js($REAL_VER)이(가) 이미 경로($TARGET_DIR)에 설치되어 있습니다. 설치를 건너뜁니다."
        
        # 심볼릭 링크 재확인 및 갱신
        NODE_BIN_DIR="${TARGET_DIR}/bin"
        ln -sf "${NODE_BIN_DIR}/node" "/usr/local/bin/node"
        ln -sf "${NODE_BIN_DIR}/npm" "/usr/local/bin/npm"
        ln -sf "${NODE_BIN_DIR}/npx" "/usr/local/bin/npx"
        
        exit 0
    fi
fi

# ==========================================================
# 4. FILE_URL 분기: 동적 파일 탐색 및 확보
# ==========================================================
DOWNLOAD_URL_DIR="${FILE_URL%/}/${DIR_NAME}/"
mkdir -p "$TEMP_DIR"

log_info "원격 서버($DOWNLOAD_URL_DIR)에서 설치 파일 검색 중..."

# HTML 구조 파싱 (Python과 동일한 로직)[cite: 6]
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
# 4-2. 필수 OS 패키지 자동 설치 (NPM native 모듈 빌드 대비)
# ==========================================================
# node-gyp 등 C++ 기반 NPM 모듈 컴파일 시 요구되는 최소 의존성
REQUIREMENTS="gcc gcc-c++ make python3"

log_info "NPM 모듈 빌드에 대비한 필수 OS 패키지를 확인 및 설치합니다... (대상: $REQUIREMENTS)"

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
chown -R "$NODEJS_OWNER" "$TARGET_DIR"
chown -R "$NODEJS_OWNER" "$TEMP_DIR"  # (각 모듈에 맞는 OWNER 변수 사용: $NODEJS_OWNER 등)  
chmod -R 755 "$TEMP_DIR"

# ==========================================================
# 6. 해당 유저로 압축 해제 (Node.js는 빌드 불필요)
# ==========================================================
log_info "'$USER_ONLY' 계정으로 설치 파일 압축 해제를 진행합니다."

EXTRACT_LOG=$(mktemp)
if su - "$USER_ONLY" -c "tar -xf '$SOURCE_FILE' -C '$TARGET_DIR' --strip-components=1" > "$EXTRACT_LOG" 2>&1; then
    log_success "Node.js 압축 해제 완료: $TARGET_DIR"
    rm -f "$EXTRACT_LOG"
else
    log_error "Node.js 압축 해제 중 오류가 발생했습니다. 로그를 확인하세요."
    cat "$EXTRACT_LOG"
    rm -f "$EXTRACT_LOG"
    exit 1
fi

# ==========================================================
# 6-2. 내부망 프록시용 .npmrc 생성 (필요시 주석 해제 후 사용)
# ==========================================================
#: <<'COMMENT_OUT'
USER_HOME=$(eval echo "~$USER_ONLY")
NPMRC_FILE="$USER_HOME/.npmrc"

# 설정된 프록시/레지스트리가 있다면 파일 생성 (폐쇄망 적용 시 주소 수정 후 사용)
cat <<EOF > "$NPMRC_FILE"

registry=http://repository.samsungds.net/repository/proxy-npm-registry.npmjs.org
strict-ssl=false
EOF

chown "$NODEJS_OWNER" "$NPMRC_FILE"
chmod 644 "$NPMRC_FILE"
log_info "내부망 패키지 설치용 $NPMRC_FILE 파일을 생성했습니다."
#COMMENT_OUT

# ==========================================================
# 7. 전역 실행을 위한 심볼릭 링크 설정
# ==========================================================
log_info "전역 실행을 위한 심볼릭 링크 설정을 진행합니다..."

NODE_BIN_DIR="${TARGET_DIR}/bin"

if [ -d "$NODE_BIN_DIR" ]; then
    ln -sf "${NODE_BIN_DIR}/node" "/usr/local/bin/node"
    ln -sf "${NODE_BIN_DIR}/npm" "/usr/local/bin/npm"
    ln -sf "${NODE_BIN_DIR}/npx" "/usr/local/bin/npx"
    log_success "심볼릭 링크 생성 완료 - /usr/local/bin/ (node, npm, npx)"
else
    log_error "설치된 경로에 'bin' 디렉토리가 없습니다. 심볼릭 링크 생성을 실패했습니다."
    exit 1
fi

# ==========================================================
# 7-2. 추가 Node.js 라이브러리(NPM) 자동 설치
# ==========================================================
if [ -n "$NODEJS_LIBRARIES" ]; then
    log_info "설정된 추가 NPM 라이브러리 설치를 시작합니다... ($NODEJS_LIBRARIES)"
    
    # 겉을 감싸고 있는 불필요한 작은따옴표 제거[cite: 6]
    CLEAN_LIBS=$(echo "$NODEJS_LIBRARIES" | tr -d "'")
	
	# 1. 대상 계정의 .bash_profile에 커스텀 Node.js PATH 추가 (동적 홈 디렉토리 탐색)
    USER_HOME=$(eval echo "~$USER_ONLY")
    USER_PROFILE="$USER_HOME/.bash_profile"
	
    if ! grep -q "$TARGET_DIR/bin" "$USER_PROFILE"; then
        echo -e "\n# Node.js 글로벌 패키지 경로" >> "$USER_PROFILE"
        echo "export PATH=$TARGET_DIR/bin:\$PATH" >> "$USER_PROFILE"
        chown "$NODEJS_OWNER" "$USER_PROFILE"
        log_info "$USER_PROFILE 에 Node.js PATH를 추가했습니다."
    fi

    # 2. NPM 라이브러리 설치
    NPM_LOG=$(mktemp)
    if su - "$USER_ONLY" -c "export PATH=\"$TARGET_DIR/bin:\$PATH\" && rm -rf ~/.npm && npm install -g $CLEAN_LIBS" > "$NPM_LOG" 2>&1; then
        log_success "추가 NPM 라이브러리 설치 완료."
        rm -f "$NPM_LOG"
    else
        log_error "일부 NPM 라이브러리 설치에 실패했습니다. 로그 파일을 확인하세요."
        cat "$NPM_LOG"
        rm -f "$NPM_LOG"
        exit 1
    fi
else
    log_info "설정된 추가 NPM 라이브러리가 없어 설치를 건너뜁니다."
fi

# ==========================================================
# 8. 설치 완료 및 버전/라이브러리 연동 확인
# ==========================================================
log_info "설치된 Node.js 경로 및 라이브러리 연동 상태를 확인합니다..."

LINK_PATH=$(readlink -f /usr/local/bin/node)
if [[ "$LINK_PATH" == *"$TARGET_DIR"* ]]; then
    log_info "심볼릭 링크가 정확한 경로($LINK_PATH)를 가리키고 있습니다."
else
    log_error "심볼릭 링크가 잘못된 경로($LINK_PATH)를 가리키고 있습니다. 예상 경로: $TARGET_DIR"
    exit 1
fi

if "$TARGET_DIR/bin/node" --version >/dev/null 2>&1; then
    INSTALLED_VER=$("$TARGET_DIR/bin/node" --version 2>&1)
    
    if [ -n "$NODEJS_LIBRARIES" ]; then
        IMPORT_SUCCESS=true
        for lib in $NODEJS_LIBRARIES; do
            # pnpm@9.13.0 등에서 '@' 기호와 버전 정보를 제거하여 순수 패키지명만 추출
            # @ 기호 뒤에 숫자가 올 때만(버전 정보일 때만) 잘라내도록 수정
			pkg_name=$(echo "$lib" | sed -E 's/@[0-9][a-zA-Z0-9._-]*$//')
            
            # npm ls -g 로 글로벌 설치 여부 확인
            if ! su - "$USER_ONLY" -c "\"$TARGET_DIR/bin/npm\" ls -g $pkg_name" >/dev/null 2>&1; then
                log_error "NPM 라이브러리 설치 확인 실패: $pkg_name"
                IMPORT_SUCCESS=false
                break
            fi
        done
        
        if [ "$IMPORT_SUCCESS" = true ]; then
            log_success "Node.js($INSTALLED_VER) 정상 작동 및 지정된 라이브러리 연동 완료."
        else
            exit 1
        fi
    else
        log_success "Node.js($INSTALLED_VER) 정상 작동 확인 완료."
    fi
else
    log_error "설치 경로의 Node.js 실행 실패: $TARGET_DIR/bin/node"
    exit 1
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "Node.js($REAL_VER) 총 설치 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

# 설치 및 검증이 완벽하게 끝난 후 임시 다운로드 파일 삭제
rm -f "$SOURCE_FILE"

exit 0
