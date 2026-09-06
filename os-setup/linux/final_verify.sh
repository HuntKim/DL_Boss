#!/bin/bash
# ==============================================================================
# os-setup/linux/final_verify.sh
# 계정/그룹, OS 파라미터, 스토리지, 디렉터리 권한, SW 설치까지 os-setup으로
# 적용한 전체 내용을 실제 터미널 명령 결과 그대로 캡처해서 리포트 파일
# 하나로 남긴다.
#
# ※ account_verify.sh 등의 [PASS]/[FAIL] 판정 스크립트와는 성격이 다르다 -
#   그쪽은 "값이 맞는지 자동 판정"이 목적이고, 이 스크립트는 "사람이
#   터미널에서 직접 확인하는 화면 그대로"를 최종 기록으로 남기는 것이
#   목적이다(예: 감사/인수인계용 증적). 그래서 각 항목 앞에 실제로 입력한
#   명령을 "$ ..." 형태로 같이 남긴다. 출력이 아주 긴 명령(cat
#   /etc/passwd 전체 등)은 생성한 개수만큼만(tail -n) 보여준다.
# ==============================================================================
# 사용법: sudo ./final_verify.sh
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "${CURRENT_DIR}/config" && pwd)"
# shellcheck source=config/common.env
source "${CONFIG_DIR}/common.env"

load_host_env

mkdir -p "$LOG_DIR"
REPORT_FILE="${LOG_DIR}/${HOSTNAME_SHORT}_final_report_$(date +%Y%m%d_%H%M%S).txt"

{
echo "================================================================"
echo " os-setup 최종 확인 리포트 - ${HOSTNAME_SHORT}"
echo " 생성 시각: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"

# ==============================================================================
# 1. 계정/그룹 정보
# ==============================================================================
echo
echo "################################################################"
echo "# 1. 계정/그룹 정보"
echo "################################################################"

if [ "${#HOST_ACCOUNTS[@]}" -gt 0 ]; then
    echo
    echo "\$ tail -n ${#HOST_ACCOUNTS[@]} /etc/passwd"
    tail -n "${#HOST_ACCOUNTS[@]}" /etc/passwd 2>&1
else
    echo
    echo "(HOST_ACCOUNTS 없음)"
fi

if [ "${#HOST_GROUPS[@]}" -gt 0 ]; then
    echo
    echo "\$ tail -n ${#HOST_GROUPS[@]} /etc/group"
    tail -n "${#HOST_GROUPS[@]}" /etc/group 2>&1
fi

if [ "${#HOST_ACCOUNTS[@]}" -gt 0 ]; then
    echo
    echo "--- 계정별 소속 그룹 ---"
    for entry in "${HOST_ACCOUNTS[@]}"; do
        IFS=':' read -r uname _ <<< "$entry"
        [ -z "$uname" ] && continue
        echo
        echo "\$ id ${uname}"
        id "$uname" 2>&1
    done
fi

# ==============================================================================
# 2. OS 파라미터
# ==============================================================================
echo
echo "################################################################"
echo "# 2. OS 파라미터 (프로파일: ${HOST_OS_PARAM_PROFILE:-미지정})"
echo "################################################################"

if [ -n "$HOST_OS_PARAM_PROFILE" ]; then
    PROFILE_FILE="${OS_PARAM_PROFILE_DIR}/${HOST_OS_PARAM_PROFILE}.param.conf"
    if [ -f "$PROFILE_FILE" ]; then
        SYSCTL_LINES=$(extract_sysctl_lines "$PROFILE_FILE")
        if [ -n "$SYSCTL_LINES" ]; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                key=$(echo "$line" | cut -d'=' -f1 | xargs)
                [ -z "$key" ] && continue
                echo
                echo "\$ sysctl ${key}"
                sysctl "$key" 2>&1
            done <<< "$SYSCTL_LINES"
        fi

        LIMITS_DST="/etc/security/limits.d/99-migration-${HOST_OS_PARAM_PROFILE}.conf"
        if [ -f "$LIMITS_DST" ]; then
            echo
            echo "\$ cat ${LIMITS_DST}"
            cat "$LIMITS_DST" 2>&1
        fi
    else
        echo
        echo "(프로파일 파일 없음: ${PROFILE_FILE})"
    fi
else
    echo
    echo "(HOST_OS_PARAM_PROFILE 미지정)"
fi

# ==============================================================================
# 3. Storage
# ==============================================================================
echo
echo "################################################################"
echo "# 3. Storage"
echo "################################################################"

if [ "${#HOST_FILESYSTEMS[@]}" -gt 0 ]; then
    for entry in "${HOST_FILESYSTEMS[@]}"; do
        IFS=':' read -r mnt _ <<< "$entry"
        [ -z "$mnt" ] && continue
        echo
        echo "\$ df -h ${mnt}"
        df -h "$mnt" 2>&1
    done
    echo
    echo "\$ tail -n ${#HOST_FILESYSTEMS[@]} /etc/fstab"
    tail -n "${#HOST_FILESYSTEMS[@]}" /etc/fstab 2>&1
else
    echo
    echo "(HOST_FILESYSTEMS 없음)"
fi

# ==============================================================================
# 4. 디렉터리 권한
# ==============================================================================
echo
echo "################################################################"
echo "# 4. 디렉터리 권한"
echo "################################################################"

if [ "${#HOST_DIR_PERMISSIONS[@]}" -gt 0 ]; then
    for entry in "${HOST_DIR_PERMISSIONS[@]}"; do
        IFS=':' read -r path _ <<< "$entry"
        [ -z "$path" ] && continue
        echo
        echo "\$ ls -ld ${path}"
        ls -ld "$path" 2>&1
    done
else
    echo
    echo "(HOST_DIR_PERMISSIONS 없음)"
fi

# ==============================================================================
# 5. SW 설치 정보 (참고용 - sw_mapping_linux.txt에 이 호스트가 있으면
#    거기 적힌 항목을 기준으로 대표적인 버전 확인 명령만 보여준다.
#    setup_sw.sh/install_*.sh 자체는 os-setup-main에서 그대로 가져온
#    부분이라 이 스크립트가 상세히 검증하지 않는다)
# ==============================================================================
echo
echo "################################################################"
echo "# 5. SW 설치 정보"
echo "################################################################"

SW_MAPPING_FILE="${OS_SETUP_LINUX_CONFIG_DIR}/sw_mapping_linux.txt"
SW_LINE=""
if [ -f "$SW_MAPPING_FILE" ]; then
    SW_LINE=$(grep -E "^${HOSTNAME_SHORT}:" "$SW_MAPPING_FILE" 2>/dev/null | head -1)
fi

if [ -n "$SW_LINE" ]; then
    echo
    echo "\$ grep '^${HOSTNAME_SHORT}:' ${SW_MAPPING_FILE}"
    echo "$SW_LINE"
else
    echo
    echo "(sw_mapping_linux.txt에 ${HOSTNAME_SHORT} 항목 없음)"
fi

if command -v java >/dev/null 2>&1; then
    echo
    echo "\$ java -version"
    java -version 2>&1
fi
for jdir in /usr/java/*/; do
    [ -x "${jdir}bin/java" ] || continue
    echo
    echo "\$ ${jdir}bin/java -version"
    "${jdir}bin/java" -version 2>&1
done

if id oracle >/dev/null 2>&1; then
    ORACLE_HOME_VAL=$(su - oracle -c 'echo $ORACLE_HOME' 2>/dev/null | tail -1)
    if [ -n "$ORACLE_HOME_VAL" ] && [ -x "${ORACLE_HOME_VAL}/bin/sqlplus" ]; then
        echo
        echo "\$ ${ORACLE_HOME_VAL}/bin/sqlplus -v"
        "${ORACLE_HOME_VAL}/bin/sqlplus" -v 2>&1
    fi
fi

echo
echo "================================================================"
echo " 리포트 종료: ${REPORT_FILE}"
echo "================================================================"
} | tee "$REPORT_FILE"

log_success "최종 확인 리포트 생성 완료: ${REPORT_FILE}"
