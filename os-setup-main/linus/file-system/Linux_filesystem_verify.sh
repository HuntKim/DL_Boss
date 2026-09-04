#!/bin/bash

# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/Linux_filesystem_gen.csv"  

DEFAULT_VG="appvg"
DEFAULT_PERM="755"  # 기본 기대 디렉터리 권한

if [[ $EUID -ne 0 ]]; then echo "Error: Root privilege required"; exit 1; fi

# 1. 설정값 추출  
HOSTNAME=$(hostname -s)  
if [ ! -f "$CONFIG_FILE" ]; then echo "Error: $CONFIG_FILE not found"; exit 1; fi

CONFIG_LINE=$(grep "^$HOSTNAME," "$CONFIG_FILE")  
if [ -z "$CONFIG_LINE" ]; then echo "No config for $HOSTNAME"; exit 1; fi

IFS=',' read -ra ADDR <<< "$CONFIG_LINE"  
RAW_DATA=("${ADDR[@]:1}")

echo -e "\n>>> [ 검증 시작 ] 서버: $HOSTNAME\n"

FAIL_COUNT=0

# 2. 정밀 검증 루프  
for (( i=0; i<${#RAW_DATA[@]}; i+=4 )); do  
    ITEM=${RAW_DATA[$i]}  
    EXPECT_OWNER=${RAW_DATA[$i+1]}  
    EXPECT_GROUP=${RAW_DATA[$i+2]}  
    EXPECT_PERM=${RAW_DATA[$i+3]}  # CSV 4번째 인자 (없으면 DEFAULT_PERM 사용)
    [ -z "$EXPECT_PERM" ] && EXPECT_PERM=$DEFAULT_PERM

    MNT_POINT=$(echo "$ITEM" | cut -d':' -f1)  
      
    # -------------------------------------------------------------
    # 검증 항목들  
    # -------------------------------------------------------------
    # 1. 마운트 여부
    MOUNTED=$(mountpoint -q "$MNT_POINT" && echo "OK" || echo "FAIL")  

    # 2. 소유자 / 그룹
    OWNER=$(stat -c '%U' "$MNT_POINT" 2>/dev/null)  
    GROUP=$(stat -c '%G' "$MNT_POINT" 2>/dev/null)  

    # 3. 디렉터리 권한 (예: 755)
    PERM=$(stat -c '%a' "$MNT_POINT" 2>/dev/null)
    PERM_CHK=$([ "$PERM" == "$EXPECT_PERM" ] && echo "OK" || echo "FAIL")

    # 4. 마운트 옵션 내 실행 권한 (noexec 포함 여부 검증)
    # /proc/mounts에서 해당 마운트 포인트에 noexec 옵션이 없으면 OK
    NOEXEC_CHK=$(grep -w "$MNT_POINT" /proc/mounts | grep -q "noexec" && echo "FAIL(noexec)" || echo "OK")

    # 5. /etc/fstab 등록 여부
    FSTAB=$(grep -q "$MNT_POINT" /etc/fstab && echo "OK" || echo "FAIL")

    # -------------------------------------------------------------
    # 결과 판정  
    # -------------------------------------------------------------
    if [[ "$MOUNTED" == "OK" && "$OWNER" == "$EXPECT_OWNER" && "$GROUP" == "$EXPECT_GROUP" && "$PERM_CHK" == "OK" && "$NOEXEC_CHK" == "OK" && "$FSTAB" == "OK" ]]; then  
        RES="✅ 성공"  
    else  
        RES="❌ 실패"  
        ((FAIL_COUNT++))  
    fi

    echo "[$MNT_POINT] 결과: $RES (마운트:$MOUNTED, 소유자:$OWNER, 그룹:$GROUP, 권한:$PERM[$PERM_CHK], Exec옵션:$NOEXEC_CHK, fstab:$FSTAB)"  
done

echo -e "\n--------------------------------------------------"  
if [ $FAIL_COUNT -eq 0 ]; then  
    echo "최종 결과: 모든 설정이 정상입니다."  
else  
    echo "최종 결과: 총 $FAIL_COUNT 건의 오류가 발견되었습니다."  
fi  
echo "--------------------------------------------------"
