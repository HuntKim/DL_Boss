#!/bin/bash
# ==========================================================
# Oracle Client 19c 설치 모듈 (install_oracle2.sh) - Clone 방식
#
# [기존 install_oracle.sh와의 차이]
#   기존: runInstaller로 매번 새로 설치 (약 941MB zip 다운로드 + Java
#         installer 실행) → 원본 zip 손상으로 tnsping 등 일부 파일이
#         0바이트로 설치되는 문제 발견됨.
#   신규: 이미 검증된 골든 서버의 /oracle/CLIENT, /oracle/orainventory를
#         각각 tar로 백업해둔 것을 개별 다운로드하여 그대로 복제하고,
#         oracle 계정용 .bash_profile도 별도 파일로 다운로드하여
#         /oracle/.bash_profile로 교체. Oracle Inventory 등록만
#         -attachHome으로 별도 처리.
#   ※ "복제"라고 해서 OS 필수 패키지 설치를 생략하면 안 됨 - 복사해온
#     바이너리도 여전히 OS가 제공하는 공유 라이브러리(libaio, libnsl 등)에
#     동적 링크돼 있고, 아래 attachHome 단계에서 runInstaller(OUI, Java
#     기반)를 실제로 실행하기 때문에 install_oracle.sh와 동일한 필수
#     패키지(RLn_ORA_PKG)가 그대로 필요하다.
#
# [사전 준비 - 운영자가 미리 해둘 것]
#   RHEL 메이저 버전별 골든 서버에서 (예: RHEL8 골든 서버에서):
#     cd /oracle && tar cf CLIENT_8.tar CLIENT/
#     cd /oracle && tar cf orainventory_8.tar orainventory/
#   RHEL9, RHEL10 골든 서버에서도 동일하게 반복 (파일명 접미사만 _9, _10)
#   - oracle 계정용 .bash_profile은 bash_profile_8 / bash_profile_9 /
#     bash_profile_10 이름으로 별도 준비 (RHEL 버전별 내용 차이는 없음)
#   - 골든 서버 자체에서 tnsping 등 핵심 파일이 정상(0바이트 아님)인지
#     먼저 반드시 검증할 것
#   - 업로드 위치 (총 9개 파일, 모두 같은 디렉터리):
#       ${BASE_URL}/files/linux/oracle_client_tar/CLIENT_{8,9,10}.tar
#       ${BASE_URL}/files/linux/oracle_client_tar/orainventory_{8,9,10}.tar
#       ${BASE_URL}/files/linux/oracle_client_tar/bash_profile_{8,9,10}
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

# 버전별 다운로드 대상 파일명 (RHEL 8/9/10 모두 절차는 동일, 파일명 접미사만 다름)
CLIENT_TAR="CLIENT_${OS_MAJOR}.tar"
INVENTORY_TAR="orainventory_${OS_MAJOR}.tar"
BASH_PROFILE_SRC="bash_profile_${OS_MAJOR}"

log_info "사용할 골든 이미지: ${CLIENT_TAR}, ${INVENTORY_TAR}, ${BASH_PROFILE_SRC} (CV_ASSUME_DISTID=${OEL_VALUE})"

# ==========================================================
# 5. 필수 dnf 패키지 설치 검증
#    install_oracle.sh와 동일한 목록(RLn_ORA_PKG, linux_common.env)과
#    동일한 재시도/개별 검증 로직을 그대로 재사용한다. 혹시 몰라 목록의
#    패키지를 임의로 빼지 않고 전체를 그대로 설치/검증한다.
# ==========================================================
case "$OS_MAJOR" in
    8)  TARGET_PKGS=("${RL8_ORA_PKG[@]}") ;;
    9)  TARGET_PKGS=("${RL9_ORA_PKG[@]}") ;;
    10) TARGET_PKGS=("${RL10_ORA_PKG[@]}") ;;
esac
log_info "#################### 필수 패키지 설치 대상 ####################"
log_info "Repository 패키지 (${#TARGET_PKGS[@]}개): ${TARGET_PKGS[*]}"
log_info "################################################################"

MAX_RETRIES=3
RETRY_COUNT=0
YUM_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    ((RETRY_COUNT++))
    log_info "패키지 설치 시도 중... (${RETRY_COUNT}/${MAX_RETRIES})"

    dnf install -y "${TARGET_PKGS[@]}"

    if [ $? -eq 0 ]; then
        log_info "dnf 패키지 설치 명령이 성공적으로 완료되었습니다."
        YUM_SUCCESS=true
        break
    else
        log_warn "dnf 패키지 설치 중 오류가 발생했습니다. (${RETRY_COUNT}/${MAX_RETRIES})"
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_info "5초 후 재시도합니다..."
            sleep 5
        fi
    fi
done

if [ "$YUM_SUCCESS" = false ]; then
    log_warn "${MAX_RETRIES}회 재시도 후에도 dnf install 명령어 실행 중 일부 에러가 발생했습니다."
    log_warn "실제 필수 패키지 개별 설치 상태 검증 단계로 넘어갑니다."
fi

# 패키지 개별 검증 (rpm -q) - 목록 전체를 하나도 빼지 않고 검증한다.
MISSING_PACKAGES=()
for pkg in "${TARGET_PKGS[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        log_info " [OK] 패키지 설치됨: $pkg"
    else
        log_error " [FAIL] 패키지 미설치: $pkg"
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    log_error "다음 필수 패키지가 최종적으로 설치되지 않았습니다: ${MISSING_PACKAGES[*]}"
    log_error "패키지 설치 실패로 인해 오라클 클라이언트 설치 스크립트를 중단합니다."
    exit 1
else
    log_success "모든 필수 패키지가 성공적으로 설치 및 검증되었습니다."
fi

# ==========================================================
# 6. oracle 계정 존재 확인 (계정/그룹 생성 단계가 선행되어 있어야 함)
# ==========================================================
if ! id oracle >/dev/null 2>&1; then
    log_error "oracle 계정이 이 서버에 존재하지 않습니다. 계정/그룹 생성 단계를 먼저 수행하세요."
    exit 1
fi
ORACLE_UNIX_GROUP=${TARGET_UNIX_GROUP_NAME}

# ==========================================================
# 7. 기존 설치 확인 - 있으면 정리 후 재배포 (멱등성)
# ==========================================================
if [ -d /oracle/CLIENT ] || [ -d /oracle/orainventory ] || [ -f /oracle/.bash_profile ]; then
    log_warn "/oracle 하위에 기존 설치 흔적이 있습니다. 기존 내용을 제거하고 새로 배포합니다."
    rm -rf /oracle/CLIENT /oracle/orainventory /oracle/.bash_profile
fi
mkdir -p /oracle

# ==========================================================
# 8. 다운로드 공통 함수
#    (CLIENT tar / orainventory tar / .bash_profile 3개 파일에 공용 사용)
# ==========================================================
BASE_DOWNLOAD_URL="${FILE_URL}/oracle_client_tar"
WORK_DIR="/var/tmp/oracle_clone_install"
mkdir -p "$WORK_DIR"

download_file() {
    local url="$1"
    local dest="$2"
    log_info "다운로드 시작: $url"
    if ! curl -f -s -k -L --retry 3 --retry-delay 3 "$url" -o "$dest"; then
        log_error "다운로드 실패: $url"
        return 1
    fi
    local size
    size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    if [ "$size" -eq 0 ]; then
        log_error "다운로드된 파일이 비어 있습니다: $url"
        return 1
    fi
    log_info "다운로드 완료: $dest (${size} bytes)"
    return 0
}

CLIENT_TAR_PATH="${WORK_DIR}/${CLIENT_TAR}"
INVENTORY_TAR_PATH="${WORK_DIR}/${INVENTORY_TAR}"
BASH_PROFILE_PATH="${WORK_DIR}/${BASH_PROFILE_SRC}"

download_file "${BASE_DOWNLOAD_URL}/${CLIENT_TAR}" "$CLIENT_TAR_PATH" || { rm -rf "$WORK_DIR"; exit 1; }
download_file "${BASE_DOWNLOAD_URL}/${INVENTORY_TAR}" "$INVENTORY_TAR_PATH" || { rm -rf "$WORK_DIR"; exit 1; }
download_file "${BASE_DOWNLOAD_URL}/${BASH_PROFILE_SRC}" "$BASH_PROFILE_PATH" || { rm -rf "$WORK_DIR"; exit 1; }

# ==========================================================
# 9. tar 무결성 검증 + 압축 해제 공통 함수
#    (tar 최상위 항목이 기대하는 디렉터리명으로 시작하는지 확인 후
#     /oracle 밑으로 풀되, 구조가 다르면 /oracle/<expected_name> 으로
#     직접 풀어 방어)
# ==========================================================
extract_component_tar() {
    local tar_file="$1"
    local expected_name="$2"   # "CLIENT" 또는 "orainventory"
    local filelist
    filelist=$(mktemp)

    if ! tar tf "$tar_file" > "$filelist" 2>"${WORK_DIR}/tar_error.log"; then
        log_error "${tar_file} 파일이 손상되어 목록을 읽을 수 없습니다. 아래 오류 참고:"
        cat "${WORK_DIR}/tar_error.log"
        rm -f "$filelist"
        return 1
    fi

    local top_entry
    top_entry=$(head -n 1 "$filelist")
    rm -f "$filelist"

    if [[ "$top_entry" == "${expected_name}/"* || "$top_entry" == "$expected_name" ]]; then
        log_info "[${expected_name}] 압축 해제 대상: /oracle (tar 최상위 = ${expected_name}/)"
        if ! tar xpf "$tar_file" -C /oracle; then
            log_error "[${expected_name}] tar 압축 해제 실패."
            return 1
        fi
    else
        log_warn "[${expected_name}] tar 최상위 항목이 '${expected_name}/'로 시작하지 않습니다 (${top_entry}). /oracle/${expected_name} 밑으로 바로 풉니다."
        mkdir -p "/oracle/${expected_name}"
        if ! tar xpf "$tar_file" -C "/oracle/${expected_name}"; then
            log_error "[${expected_name}] tar 압축 해제 실패."
            return 1
        fi
    fi
    return 0
}

extract_component_tar "$CLIENT_TAR_PATH" "CLIENT" || { rm -rf "$WORK_DIR"; exit 1; }
extract_component_tar "$INVENTORY_TAR_PATH" "orainventory" || { rm -rf "$WORK_DIR"; exit 1; }

# 필수 디렉터리 존재 확인
for d in /oracle/CLIENT /oracle/orainventory; do
    if [ ! -d "$d" ]; then
        log_error "압축 해제 후 필수 디렉터리가 없습니다: $d (tar 내용물을 확인하세요)"
        rm -rf "$WORK_DIR"
        exit 1
    fi
done

# .bash_profile은 tar가 아닌 단일 파일이므로 바로 배치
cp "$BASH_PROFILE_PATH" /oracle/.bash_profile
rm -rf "$WORK_DIR"
log_success "압축 해제 및 .bash_profile 배치 완료, 디렉터리 구조 확인됨"

# ==========================================================
# 10. 소유권 / 권한 설정
# ==========================================================
chown -R oracle:${ORACLE_UNIX_GROUP} /oracle
chmod -R 750 /oracle/CLIENT /oracle/orainventory
chown oracle:${ORACLE_UNIX_GROUP} /oracle/.bash_profile
chmod 640 /oracle/.bash_profile

# SELinux 컨텍스트 복구 (enforcing 환경에서 tar로 옮긴 파일은 라벨이 깨질 수 있음)
if command -v restorecon >/dev/null 2>&1; then
    restorecon -R /oracle 2>/dev/null || true
fi
log_success "소유권/권한 설정 완료 (oracle:${ORACLE_UNIX_GROUP})"

# ==========================================================
# 11. 경로 확정 (host env로 오버라이드 가능, 기본값은 기존 관례 그대로)
# ==========================================================
ORACLE_HOME_PATH=${TARGET_ORACLE_HOME}
INVENTORY_PATH=${TARGET_INVENTORY_LOCATION}
ORACLE_HOME_NAME=${TARGET_ORACLE_HOME_NAME}

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
# ==========================================================
TNSNAMES_URL="${FILE_URL}/tnsnames/${TARGET_HOSTNAME}.tnsnames.ora"
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
    log_error "설치 검증 실패 - golden 이미지(${CLIENT_TAR}/${INVENTORY_TAR}) 자체를 다시 확인하세요."
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
