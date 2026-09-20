#!/bin/bash
# ==========================================================
# Oracle Client 19c 설치 모듈 (install_oracle2.sh) - Clone 방식
#
# [기존 install_oracle.sh와의 차이]
#   기존: runInstaller로 매번 새로 설치 (약 941MB zip 다운로드 + Java
#         installer 실행) → 원본 zip 손상으로 tnsping 등 일부 파일이
#         0바이트로 설치되는 문제 발견됨.
#   신규: 이미 검증된 골든 서버의 /oracle 디렉터리(CLIENT, orainventory,
#         .bash_profile 포함) 전체를 tar로 백업해둔 것을 그대로 풀어서
#         복제. Oracle Inventory 등록만 -attachHome으로 별도 처리.
#
# [사전 준비 - 운영자가 미리 해둘 것]
#   RHEL 메이저 버전별 골든 서버에서 (예: RHEL8 골든 서버에서):
#     cd / && tar cf oracle_8.tar oracle/
#   RHEL9, RHEL10 골든 서버에서도 동일하게 oracle_9.tar, oracle_10.tar 생성.
#   - tar 안에는 oracle/CLIENT, oracle/orainventory, oracle/.bash_profile이
#     모두 포함되어 있어야 함 (.bash_profile은 오라클 계정용으로 미리 작성)
#   - 골든 서버 자체에서 tnsping 등 핵심 파일이 정상(0바이트 아님)인지
#     먼저 반드시 검증할 것
#   - 업로드 위치: ${BASE_URL}/files/linux/oracle_client_tar/oracle_{8,9,10}.tar
#
# [호출 규약]
#   install_oracle2.sh [SW_VERSION]
#   (SW_VERSION은 로그 표기용. 실제 배포본 선택은 OS 메이저 버전 자동
#    감지로 이루어진다.)
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
SW_VER="${1:-19.3.0}"
log_info "[Oracle Client(Clone 방식) 설치 시작 ($START_TIME_STR)] 요청 버전: $SW_VER"

# ==========================================================
# 3. root 권한 확인
# ==========================================================
if [ "$EUID" -ne 0 ]; then
    log_error "root 권한으로 실행해야 합니다."
    exit 1
fi

# ==========================================================
# 4. OS 배포판 및 메이저 버전 감지 (RHEL 8/9/10 지원)
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

case "$OS_ID" in
    rhel|rocky|almalinux|centos) : ;;
    *)
        log_error "지원하지 않는 OS입니다: $OS_ID (지원: RHEL 8/9/10 계열)"
        exit 1
        ;;
esac

# CV_ASSUME_DISTID 매핑
#  - 8  : OEL7.8  (실제 RHEL8.6 테스트 서버에서 검증된 값 그대로 사용)
#  - 9  : OEL9    (문서상 관례 - 이 프로젝트에서 실제 검증은 아직 안 됨)
#  - 10 : OEL10   (※ 미검증. Oracle 19c 인증 매트릭스에 RHEL10 자체가
#                   늦게 추가된 편이라, 최초 적용 시 반드시 실제 동작
#                   확인 필요. attachHome이 INS-08101 경고 이상으로
#                   실패하면 이 값을 조정할 것)
case "$OS_MAJOR" in
    8)  OEL_VALUE="OEL7.8" ;;
    9)  OEL_VALUE="OEL9" ;;
    10) OEL_VALUE="OEL10" ;;
    *)
        log_error "지원하지 않는 OS 메이저 버전입니다: $OS_MAJOR (지원: 8/9/10)"
        exit 1
        ;;
esac

TAR_FILE="oracle_${OS_MAJOR}.tar"
log_info "사용할 골든 이미지: ${TAR_FILE} (CV_ASSUME_DISTID=${OEL_VALUE})"

# ==========================================================
# 5. oracle 계정 존재 확인 (계정/그룹 생성 단계가 선행되어 있어야 함)
# ==========================================================
if ! id oracle >/dev/null 2>&1; then
    log_error "oracle 계정이 이 서버에 존재하지 않습니다. 계정/그룹 생성 단계를 먼저 수행하세요."
    exit 1
fi
ORACLE_UNIX_GROUP="${UNIX_GROUP_NAME:-dba}"

# ==========================================================
# 6. 기존 설치 확인 - 있으면 정리 후 재배포 (멱등성)
# ==========================================================
if [ -d /oracle/CLIENT ] || [ -d /oracle/orainventory ]; then
    log_warn "/oracle/CLIENT 또는 /oracle/orainventory가 이미 존재합니다. 기존 내용을 제거하고 새로 배포합니다."
    rm -rf /oracle/CLIENT /oracle/orainventory /oracle/.bash_profile
fi

# ==========================================================
# 7. 골든 이미지 다운로드
# ==========================================================
DOWNLOAD_URL="${BASE_URL}/files/linux/oracle_client_tar/${TAR_FILE}"
WORK_DIR="/var/tmp/oracle_clone_install"
SOURCE_FILE="${WORK_DIR}/${TAR_FILE}"
mkdir -p "$WORK_DIR"

log_info "다운로드 시작: $DOWNLOAD_URL"
if ! curl -f -s -k -L --retry 3 --retry-delay 3 "$DOWNLOAD_URL" -o "$SOURCE_FILE"; then
    log_error "다운로드 실패: $DOWNLOAD_URL"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 다운로드 결과 크기 검증 (기존 zip 손상 사례 재발 방지 - 최소한의 방어선)
LOCAL_SIZE=$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo 0)
if [ "$LOCAL_SIZE" -lt 1000000 ]; then
    log_error "다운로드된 파일이 비정상적으로 작습니다 (${LOCAL_SIZE} bytes). 원본 파일을 확인하세요: $DOWNLOAD_URL"
    rm -rf "$WORK_DIR"
    exit 1
fi
log_info "다운로드 완료: ${SOURCE_FILE} (${LOCAL_SIZE} bytes)"

# ==========================================================
# 8. tar 무결성 사전 검증 (풀기 전에 확인 - 기존 unzip 무검증 문제 재발 방지)
# ==========================================================
FILELIST="${WORK_DIR}/filelist.txt"
if ! tar tf "$SOURCE_FILE" > "$FILELIST" 2>"${WORK_DIR}/tar_error.log"; then
    log_error "tar 파일이 손상되어 목록을 읽을 수 없습니다. 아래 오류 참고:"
    cat "${WORK_DIR}/tar_error.log"
    rm -rf "$WORK_DIR"
    exit 1
fi

# ==========================================================
# 9. tar 내부 구조 자동 판별 후 압축 해제
#    ("oracle/"로 시작 -> "/"에 풀기, 아니면 "/oracle"에 바로 풀기)
# ==========================================================
TOP_ENTRY=$(head -n 1 "$FILELIST")
if [[ "$TOP_ENTRY" == oracle/* || "$TOP_ENTRY" == "oracle" ]]; then
    EXTRACT_TARGET="/"
else
    log_warn "tar 최상위 항목이 'oracle/'로 시작하지 않습니다 (${TOP_ENTRY}). /oracle 밑으로 바로 풉니다."
    mkdir -p /oracle
    EXTRACT_TARGET="/oracle"
fi

log_info "압축 해제 대상: $EXTRACT_TARGET"
if ! tar xpf "$SOURCE_FILE" -C "$EXTRACT_TARGET"; then
    log_error "tar 압축 해제 실패."
    rm -rf "$WORK_DIR"
    exit 1
fi

rm -rf "$WORK_DIR"

# 필수 디렉터리 존재 확인
for d in /oracle/CLIENT /oracle/orainventory; do
    if [ ! -d "$d" ]; then
        log_error "압축 해제 후 필수 디렉터리가 없습니다: $d (tar 내용물을 확인하세요)"
        exit 1
    fi
done
log_success "압축 해제 완료 및 디렉터리 구조 확인됨"

# ==========================================================
# 10. 소유권 / 권한 설정
# ==========================================================
chown -R oracle:${ORACLE_UNIX_GROUP} /oracle
chmod -R 750 /oracle/CLIENT /oracle/orainventory
if [ -f /oracle/.bash_profile ]; then
    chown oracle:${ORACLE_UNIX_GROUP} /oracle/.bash_profile
    chmod 640 /oracle/.bash_profile
else
    log_warn "/oracle/.bash_profile이 tar 안에 없습니다. 환경변수가 누락됐을 수 있으니 확인하세요."
fi

# SELinux 컨텍스트 복구 (enforcing 환경에서 tar로 옮긴 파일은 라벨이 깨질 수 있음)
if command -v restorecon >/dev/null 2>&1; then
    restorecon -R /oracle 2>/dev/null || true
fi
log_success "소유권/권한 설정 완료 (oracle:${ORACLE_UNIX_GROUP})"

# ==========================================================
# 11. 경로 확정 (host env로 오버라이드 가능, 기본값은 기존 관례 그대로)
# ==========================================================
ORACLE_HOME_PATH="${TARGET_ORACLE_HOME:-/oracle/CLIENT/oracle}"
INVENTORY_PATH="${TARGET_INVENTORY_LOCATION:-/oracle/orainventory}"
ORACLE_HOME_NAME="${TARGET_ORACLE_HOME_NAME:-OraClient19Home1}"

if [ ! -f "${ORACLE_HOME_PATH}/oui/bin/runInstaller" ]; then
    log_error "ORACLE_HOME(${ORACLE_HOME_PATH}) 경로가 예상과 다릅니다. golden tar 구조 또는 TARGET_ORACLE_HOME 설정을 확인하세요."
    exit 1
fi

# ==========================================================
# 12. /etc/oraInst.loc 생성 (tar에는 포함되지 않는 시스템 전역 파일)
# ==========================================================
cat > /etc/oraInst.loc <<EOF
inventory_loc=${INVENTORY_PATH}
inst_group=${ORACLE_UNIX_GROUP}
EOF
log_info "/etc/oraInst.loc 생성 완료 (inventory_loc=${INVENTORY_PATH})"

# ==========================================================
# 13. 시스템 전역 라이브러리 경로 등록
#     (root 등 oracle 계정이 아닌 사용자도 sqlplus 등을 실행할 수 있도록)
# ==========================================================
echo "${ORACLE_HOME_PATH}/lib" > /etc/ld.so.conf.d/oracle-client.conf
ldconfig
log_info "ldconfig 등록 완료 (${ORACLE_HOME_PATH}/lib)"

# ==========================================================
# 14. (선택) 호스트 전용 tnsnames.ora 배치
#     host env에 TNSNAMES_URL이 정의된 경우에만 golden 이미지의 기본값을 교체
# ==========================================================
if [ -n "${TNSNAMES_URL:-}" ]; then
    TNSNAMES_DEST="${ORACLE_HOME_PATH}/network/admin/tnsnames.ora"
    log_info "호스트 전용 tnsnames.ora 다운로드: $TNSNAMES_URL"
    if curl -f -s -k -L --retry 3 --retry-delay 3 "$TNSNAMES_URL" -o "$TNSNAMES_DEST"; then
        chown oracle:${ORACLE_UNIX_GROUP} "$TNSNAMES_DEST"
        chmod 640 "$TNSNAMES_DEST"
        log_success "tnsnames.ora 교체 완료"
    else
        log_warn "tnsnames.ora 다운로드 실패 - golden 이미지에 포함된 기본값을 그대로 사용합니다."
    fi
fi

# ==========================================================
# 15. Oracle Inventory에 Home 등록 (attachHome)
# ==========================================================
log_info "Oracle Inventory에 Home 등록 시도 (attachHome, ORACLE_HOME_NAME=${ORACLE_HOME_NAME})"

ATTACH_LOG=$(mktemp)
su - oracle -c "
export CV_ASSUME_DISTID=${OEL_VALUE}
cd '${ORACLE_HOME_PATH}'
./runInstaller -silent -attachHome \
  ORACLE_HOME='${ORACLE_HOME_PATH}' \
  ORACLE_HOME_NAME='${ORACLE_HOME_NAME}'
" > "$ATTACH_LOG" 2>&1
ATTACH_RC=$?
cat "$ATTACH_LOG"

# INS-08101(supportedOSCheck 경고) 등은 실패로 간주하지 않고, 실제 등록
# 여부는 opatch lsinventory로 최종 확인한다.
if [ $ATTACH_RC -ne 0 ]; then
    log_warn "attachHome 명령이 0이 아닌 종료코드(${ATTACH_RC})를 반환했습니다. 아래 검증 단계에서 실제 등록 여부를 재확인합니다."
fi
rm -f "$ATTACH_LOG"

if su - oracle -c "${ORACLE_HOME_PATH}/OPatch/opatch lsinventory" 2>/dev/null | grep -q "products installed"; then
    log_success "Oracle Inventory 등록 확인 완료"
else
    log_error "Oracle Inventory 등록을 확인하지 못했습니다. attachHome 로그를 직접 확인하세요."
    exit 1
fi

# ==========================================================
# 16. 설치 결과 검증
#     (핵심: 기존 zip 손상 사례처럼 0바이트 파일이 없는지 반드시 확인)
# ==========================================================
log_info "핵심 파일 무결성 검증 중..."
CRITICAL_FILES=(
    "${ORACLE_HOME_PATH}/bin/tnsping"
    "${ORACLE_HOME_PATH}/bin/sqlplus"
)
VERIFY_FAIL=0
for f in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        log_error "필수 파일이 없습니다: $f"
        VERIFY_FAIL=1
        continue
    fi
    FSIZE=$(stat -c%s "$f")
    if [ "$FSIZE" -eq 0 ]; then
        log_error "파일 크기가 0입니다 (golden 이미지 손상 의심): $f"
        VERIFY_FAIL=1
    else
        log_info "OK: $f (${FSIZE} bytes)"
    fi
done

if [ "$VERIFY_FAIL" -eq 1 ]; then
    log_error "설치 검증 실패 - golden 이미지(${TAR_FILE}) 자체를 다시 확인하세요."
    exit 1
fi

su - oracle -c "export LD_LIBRARY_PATH=${ORACLE_HOME_PATH}/lib; ${ORACLE_HOME_PATH}/bin/sqlplus -v" 2>&1

# ==========================================================
# 17. 완료
# ==========================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

log_success "Oracle Client(Clone 방식, RHEL${OS_MAJOR}) 설치 완료. 총 소요 시간: ${HOURS}시간 ${MINUTES}분 ${SECONDS}초"

exit 0
