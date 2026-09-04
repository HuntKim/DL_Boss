#!/bin/bash
# ==========================================================
# install_perl.sh
# 호출 규약: install_perl.sh <SW_VERSION> <PERL_PATH>
#   SW_VERSION  : ex) 5.26.3
#   PERL_PATH   : perl 실행 파일이 최종적으로 위치할 정확한 경로
#                 (예: /usr/bin/perl, /usr2/bin/perl - 반드시 ".../bin/perl"
#                 형태. 서버마다 시스템 기본 경로(/usr/bin/perl)를 쓰기도 하고
#                 별도 마운트(/usr2/bin/perl)를 쓰기도 하므로, common.env에는
#                 기본값을, 예외적인 호스트는 env/<host>.env의
#                 TARGET_PERL_PATH로 재정의한다.)
#                 빌드 prefix는 이 경로에서 "/bin/perl" 부분을 뗀 나머지이다.
#
# setup_sw.sh 가 SW_TYPE="perl" 항목을 만났을 때 호출하는 모듈.
# perl-<SW_VERSION>.tar.gz 소스를 받아 Configure/make/make install로 설치한다.
#
# 지원 OS: RHEL 8 / 9 / 10 계열
#   - RHEL9(gcc11+), RHEL10(gcc14+)에서는 오래된 Perl 소스가 최신 gcc
#     기본 정책(-fno-common, 암묵적 함수선언 에러화 등)에 걸려 빌드가
#     실패할 수 있어, ccflags에 안전한 호환 플래그를 항상 포함시킨다.
#     (RHEL8 gcc8에는 영향 없는 무해한 플래그들)
# ==========================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config/env/" && pwd)"
COMMON_ENV="$(cd "$CURRENT_DIR/../config" && pwd)/linux_common.env"

if [ -f "$COMMON_ENV" ]; then
    source "$COMMON_ENV"
else
    echo "[ERROR] 공통 설정 파일($COMMON_ENV)을 찾을 수 없습니다." >&2
    exit 1
fi

SW_VERSION="$1"
PERL_PATH="$2"

if [ -z "$SW_VERSION" ] || [ -z "$PERL_PATH" ]; then
    log_error "필수 인자값이 누락되었습니다. (Ver: $SW_VERSION, Path: $PERL_PATH)"
    exit 1
fi

# 이 스크립트 전용 구분선 로그 (log_info 기반 - common.env에 log_step이 이미
# 있다면 이 함수는 지우고 그쪽을 쓰세요. 이름 충돌 방지를 위해 _step 사용)
_step() {
    log_info "----------------------------------------------------------------"
    log_info "$1"
    log_info "----------------------------------------------------------------"
}

_step "[Perl 설치 시작] 버전: ${SW_VERSION} / 경로: ${PERL_PATH}"

# ==========================================================
# 호스트 전용 환경설정 로드
#   호스트 env는 PERL_PATH를 직접 재정의하지 않고 TARGET_PERL_PATH를
#   사용한다(install_oracle.sh와 동일한 규약). 그래야 source 시 빈 값으로
#   실수로 덮어써질 위험 없이, 아래 apply_target_override에서만 명시적으로
#   우선순위를 적용한다. 호스트 전용 파일이 없어도 common.env 기본값으로
#   계속 진행한다.
# ==========================================================
CONF_FILE="${CONFIG_DIR}/$(hostname -s).env"
if [ -f "${CONF_FILE}" ]; then
    log_info "환경변수 설정 파일 로드: ${CONF_FILE}"
    . "${CONF_FILE}"
else
    log_warn "호스트 전용 환경설정 파일이 없습니다: ${CONF_FILE} (linux_common.env 기본값으로 진행합니다)"
fi

# TARGET_PERL_PATH가 호스트 env에 있으면 그 값 사용, 없으면(또는 빈 값이면)
# 위에서 확정된 PERL_PATH(= common.env 기본값 또는 setup_sw.sh가 넘긴 값)를 유지.
apply_target_override "PERL_PATH"

# ==========================================================
# PERL_PATH는 "perl 실행 파일의 최종 경로"(예: /usr/bin/perl, /usr2/bin/perl)이지
# 설치 prefix 디렉터리가 아니다. Perl 빌드(Configure -Dprefix)는 prefix
# 디렉터리가 필요하므로, PERL_PATH에서 "/bin/perl" 부분을 떼어내 구한다.
#   /usr/bin/perl  -> PERL_PREFIX=/usr
#   /usr2/bin/perl -> PERL_PREFIX=/usr2
# ==========================================================
case "${PERL_PATH}" in
    */bin/perl)
        PERL_PREFIX="${PERL_PATH%/bin/perl}"
        ;;
    *)
        log_error "PERL_PATH는 반드시 '.../bin/perl' 형태여야 합니다. (현재 값: ${PERL_PATH})"
        exit 1
        ;;
esac
log_info "PERL_PATH(최종 바이너리 경로)=${PERL_PATH} -> PERL_PREFIX(빌드 prefix)=${PERL_PREFIX}"

if [ -z "${BASE_URL}" ]; then
    log_error "BASE_URL 환경변수가 설정되어 있지 않습니다."
    exit 1
fi
if [ -z "${TEMP_DIR}" ]; then
    log_error "TEMP_DIR 환경변수가 설정되어 있지 않습니다."
    exit 1
fi

# ==========================================================
# SW_VERSION에는 아키텍처 접미사(_32b/_64b)가 붙어 있을 수 있다
# (예: sw_mapping의 "perl_5.26.3_64b" -> SW_VERSION="5.26.3_64b").
# 이 접미사는 저장소 디렉터리명(DIR_URL: perl_${SW_VERSION})에는 그대로
# 필요하지만, 실제 `perl -e 'print $^V'`가 내놓는 버전 문자열에는 접미사가
# 절대 포함되지 않으므로, "버전 비교"에는 접미사를 뗀 CORE_VERSION만 쓴다.
# (install_jdk.sh의 strip_arch_suffix와 동일한 목적)
# ==========================================================
case "${SW_VERSION}" in
    *_32b|*_64b)
        CORE_VERSION="${SW_VERSION%_*}"
        ;;
    *)
        CORE_VERSION="${SW_VERSION}"
        ;;
esac
log_info "버전 파싱: SW_VERSION=${SW_VERSION} -> CORE_VERSION(비교용)=${CORE_VERSION}"

# ==========================================================
# 이전 버전 스크립트의 버그(PERL_PATH를 prefix로 오인)로 인해
# PERL_PATH 자리에 "파일"이 아니라 "디렉터리"가 남아있을 수 있다
# (예: /usr2/bin/perl/bin/perl 로 잘못 설치되면서 /usr2/bin/perl 이
# 디렉터리로 생성된 경우). 디렉터리는 보통 실행권한(x)이 있어서 아래
# "-x" 체크를 통과해버리고, perl 버전 조회 시 "디렉터리를 실행할 수
# 없음" 에러로 조용히 빈 값이 나와 항상 재설치로 빠지는 원인이 된다.
# 정상 상태라면 PERL_PATH는 파일이거나 아예 없어야 하므로, 디렉터리로
# 존재하면 이전 버그의 잔존물로 판단하고 정리한다.
# ==========================================================
if [ -d "${PERL_PATH}" ]; then
    log_warn "PERL_PATH(${PERL_PATH})가 파일이 아니라 디렉터리로 존재합니다. (구버전 스크립트의 설치 위치 오류로 인한 잔존물로 추정) 정리 후 재설치를 진행합니다."
    rm -rf "${PERL_PATH}"
fi

# ==============================================================================
# 0. 이미 원하는 버전이 설치돼 있으면 스킵
# ==============================================================================
if [ -x "${PERL_PATH}" ] && [ ! -d "${PERL_PATH}" ]; then
    CUR_VER="$("${PERL_PATH}" -e 'print $^V' 2>/dev/null | sed 's/^v//')"
    if [ "${CUR_VER}" = "${CORE_VERSION}" ]; then
        log_success "Perl ${SW_VERSION} 이(가) 이미 ${PERL_PATH} 에 설치되어 있습니다. 설치를 스킵합니다."
        exit 0
    else
        log_warn "${PERL_PATH} 에 다른 버전(${CUR_VER})의 Perl이 이미 존재합니다. 재설치를 진행합니다."
    fi
fi

# ==============================================================================
# 1. OS 버전 감지
# ==============================================================================
_step "[1/6] OS 버전 감지"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_MAJOR="${VERSION_ID%%.*}"
elif [ -f /etc/redhat-release ]; then
    OS_RAW="$(cat /etc/redhat-release)"
    OS_MAJOR="$(echo "$OS_RAW" | grep -oE '[0-9]+' | head -1)"
else
    log_error "OS 버전을 확인할 수 없습니다. (/etc/os-release, /etc/redhat-release 모두 없음)"
    exit 1
fi

case "$OS_MAJOR" in
    8)  log_info "감지된 OS: RHEL 8 계열 (major=${OS_MAJOR})" ;;
    9)  log_info "감지된 OS: RHEL 9 계열 (major=${OS_MAJOR})" ;;
    10) log_info "감지된 OS: RHEL 10 계열 (major=${OS_MAJOR})" ;;
    *)
        log_error "지원하지 않는 OS 버전입니다: ${OS_MAJOR}"
        exit 1
        ;;
esac

# Perl 소스 빌드 의존 패키지는 linux_common.env의 PERL_PKG를 사용
# (RHEL 8/9/10 모두 이름 동일 - AppStream 기본 포함)
if [ ${#PERL_PKG[@]} -eq 0 ]; then
    log_error "PERL_PKG 배열이 정의되어 있지 않습니다. (linux_common.env 확인 필요)"
    exit 1
fi

# ==============================================================================
# 2. 빌드 의존 패키지 설치
# ==============================================================================
_step "[2/6] 빌드 의존 패키지 설치"
log_info "설치 대상 (${#PERL_PKG[@]}개): ${PERL_PKG[*]}"

sudo dnf install -y "${PERL_PKG[@]}"
if [ $? -ne 0 ]; then
    log_error "필수 패키지 설치 실패. Perl 빌드를 진행할 수 없습니다."
    exit 1
fi
log_info " -> 패키지 설치 완료"

# ==============================================================================
# 3. 소스 다운로드
# ==============================================================================
_step "[3/6] Perl 소스 다운로드"

DOWNLOAD_TMP="${TEMP_DIR}/download_tmp"
mkdir -p "${DOWNLOAD_TMP}"
mkdir -p "${PERL_PREFIX}"
DIR_URL="${BASE_URL}/perl_${SW_VERSION}"

log_info "탐색 대상 디렉터리 : ${DIR_URL}"

cd "${DOWNLOAD_TMP}" || { log_error "임시 디렉터리 이동 실패: ${DOWNLOAD_TMP}"; exit 1; }

# 디렉토리 리스팅에서 .tar.gz 파일명을 추출 (와일드카드로 직접 GET 불가하므로 목록을 먼저 받아 grep)
# TAR_FILE=$(curl -sf "$DIR_URL/" | grep -oE '[^"]+\.rpm' | head -n 1)
TAR_FILE=$(curl -sf "$DIR_URL/" | grep '\.tar.gz' | awk '{print $NF}' | head -n 1)
log_info "TAR_FILE 탐색 : $TAR_FILE"
if [ -z "$TAR_FILE" ]; then
    log_error "해당 디렉토리에서 RPM 파일을 찾을 수 없습니다: $DIR_URL"
    exit 1
fi

log_info "대상 파일 확인: $TAR_FILE"

DOWNLOAD_URL="${DIR_URL}/${TAR_FILE}"
if ! curl -sf -o "$DOWNLOAD_TMP/$TAR_FILE" "$DOWNLOAD_URL"; then
    log_error "파일 다운로드 실패: $DOWNLOAD_URL"
    exit 1
fi

if [ ! -f "$DOWNLOAD_TMP/$TAR_FILE" ]; then
    log_error "파일 다운로드 실패: $TAR_FILE"
    exit 1
fi

# ==============================================================================
# 4. 압축 해제
# ==============================================================================
_step "[4/6] 압축 해제"

# 압축 해제 후 생성될 디렉터리명은 실제로 받은 파일명(TAR_FILE)에서
# ".tar.gz" 확장자만 잘라내 구한다 (TAR_FILE%.tar.gz 표현식).
# SW_VERSION으로 직접 "perl-${SW_VERSION}"을 조립하면, 저장소의 실제
# 파일명이 그 예측과 정확히 일치하지 않을 때(예: perl-5.26.3-src.tar.gz)
# 실제 압축 해제된 디렉터리명과 어긋나 버린다.
SRC_DIR="${TAR_FILE%.tar.gz}"

# 이전 실행에서 남은 소스 디렉터리가 있으면 통째로 삭제한다.
# Configure -des는 같은 디렉터리에 이전 실행의 config.sh가 남아있으면
# 그걸 기본값으로 재사용해버려서, 이번에 -Dprefix를 새로 줘도
# installbin/installscript/binexp 같은 하위 경로가 예전 값 그대로
# 남는 문제가 있다. 매번 완전히 새 상태에서 Configure가 돌게 한다.
if [ -d "${SRC_DIR}" ]; then
    log_info "이전 실행에서 남은 소스 디렉터리 삭제: $(pwd)/${SRC_DIR}"
    rm -rf "${SRC_DIR}"
fi

tar xzf "${TAR_FILE}"
if [ $? -ne 0 ] || [ ! -d "${SRC_DIR}" ]; then
    log_error "압축 해제 실패 또는 소스 디렉터리(${SRC_DIR})를 찾을 수 없습니다."
    exit 1
fi

cd "${SRC_DIR}" || { log_error "소스 디렉터리 진입 실패: ${SRC_DIR}"; exit 1; }
log_info " -> 압축 해제 완료: $(pwd)"

# ==============================================================================
# 5. Configure / make / make install
#    -fcommon                        : gcc10+(RHEL9/10)의 -fno-common 기본값으로
#                                       인한 'multiple definition' 링크 에러 방지
#    -Wno-error=implicit-*, int-*    : gcc14+(RHEL10)에서 기본으로 에러 처리되는
#                                       구식 C 패턴(암묵적 함수선언 등)을
#                                       경고로 되돌려 컴파일 실패 방지
#    두 옵션 모두 RHEL8(gcc8)에는 영향이 없는 무해한 플래그라 OS 분기 없이 공통 적용
# ==============================================================================
_step "[5/6] Configure / make / make install"

PERL_CCFLAGS="-fcommon -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"

# 기본 -O2 최적화에서 regcomp.c 등 구코드의 sequence-point UB를 gcc10+가
# 공격적으로 이용해 miniperl 부트스트랩 단계에서 메모리 손상
# ("Attempt to free unreferenced scalar")이 발생하는 사례가 있어,
# 안전하게 -O1로 낮춰서 빌드한다.
PERL_OPTIMIZE="-O1"

log_info "Configure 실행 (prefix=${PERL_PREFIX}, optimize=${PERL_OPTIMIZE})"
# -Uinstallusrbinperl: 시스템 기본 perl(예: RHEL 패키지로 깔린 /usr/bin/perl)을
# 절대 건드리지 않도록 명시. 이게 없으면 -des 기본값이 "예"로 처리되어
# installperl이 /usr/bin/perl 자리에 뭔가 만들려다 기존 파일과 충돌한다.
./Configure -des -Dprefix="${PERL_PREFIX}" -Dccflags="${PERL_CCFLAGS}" -Doptimize="${PERL_OPTIMIZE}" -Uinstallusrbinperl > "${DOWNLOAD_TMP}/configure.log" 2>&1
if [ $? -ne 0 ]; then
    log_error "Configure 실패. 로그: ${DOWNLOAD_TMP}/configure.log (마지막 30줄 아래 출력)"
    tail -n 30 "${DOWNLOAD_TMP}/configure.log"
    exit 1
fi
log_info " -> Configure 완료 (로그: ${DOWNLOAD_TMP}/configure.log)"

# perl-${SW_VERSION} 시절 Configure(hints/linux.sh)는 gcc 버전 문자열을 "1*"
# 패턴으로만 검사해서 -fpcc-struct-return을 자동으로 끼워 넣는 오래된 버그가
# 있다. gcc10/11/12/13/14... 전부 "1"로 시작하므로 이 오검출에 걸리고,
# 그 결과 struct 반환 ABI가 바뀌어 miniperl 자체 실행 단계에서 메모리 손상
# ("Attempt to free unreferenced scalar")으로 빌드가 죽는다.
# -Dccflags로는 이 힌트 로직을 못 이기므로, 생성된 Makefile에서 직접 제거한다.
if grep -q -- '-fpcc-struct-return' Makefile 2>/dev/null; then
    log_info "Configure가 오검출로 끼워넣은 -fpcc-struct-return 플래그 제거 (gcc10+ ABI 버그 대응)"
    sed -i 's/-fpcc-struct-return//g' Makefile
fi

log_info "make 실행 (병렬: $(nproc) job)"
make -j"$(nproc)" > "${DOWNLOAD_TMP}/make.log" 2>&1
if [ $? -ne 0 ]; then
    log_error "make 빌드 실패. 로그: ${DOWNLOAD_TMP}/make.log (마지막 30줄 아래 출력)"
    tail -n 30 "${DOWNLOAD_TMP}/make.log"
    exit 1
fi
log_info " -> make 완료 (로그: ${DOWNLOAD_TMP}/make.log)"

log_info "make install 실행"
sudo make install > "${DOWNLOAD_TMP}/make_install.log" 2>&1
if [ $? -ne 0 ]; then
    log_error "make install 실패. 로그: ${DOWNLOAD_TMP}/make_install.log (마지막 30줄 아래 출력)"
    tail -n 30 "${DOWNLOAD_TMP}/make_install.log"
    exit 1
fi
log_info " -> make install 완료"

# ==============================================================================
# 6. 최종 검증
# ==============================================================================
_step "[6/6] 설치 검증"

if [ ! -x "${PERL_PATH}" ] || [ -d "${PERL_PATH}" ]; then
    log_error "설치 검증 실패: ${PERL_PATH} 실행 파일이 없습니다(또는 디렉터리로 잘못 생성됨)."
    exit 1
fi

INSTALLED_VER="$("${PERL_PATH}" -e 'print $^V' 2>/dev/null | sed 's/^v//')"
if [ "${INSTALLED_VER}" != "${CORE_VERSION}" ]; then
    log_error "설치 검증 실패: 설치된 버전(${INSTALLED_VER})이 요청 버전(${CORE_VERSION})과 다릅니다."
    exit 1
fi

log_success "=================================================="
log_success " Perl 설치 완료"
log_success "  - 버전     : ${INSTALLED_VER}"
log_success "  - 실행파일 : ${PERL_PATH}"
log_success "  - 완료시각 : $(date)"
log_success "=================================================="

exit 0
