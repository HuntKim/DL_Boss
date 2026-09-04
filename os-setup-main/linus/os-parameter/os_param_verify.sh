#!/bin/bash



# ==============================================================================  

# Windows Server/Linux OS 파라미터 적용 결과 검증 스크립트  

# ==============================================================================



# 0. 환경 설정 및 권한 확인  

# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/os_param_apply.csv"



if [[ $EUID -ne 0 ]]; then echo "Error: Root privilege required"; exit 1; fi  

if [ ! -f "$CONFIG_FILE" ]; then echo "Error: $CONFIG_FILE not found"; exit 1; fi



# 1. 서버 식별 및 그룹 매칭  

HOSTNAME=$(hostname -s)  

GROUP=$(grep "^$HOSTNAME," "$CONFIG_FILE" | cut -d',' -f2)



if [ -z "$GROUP" ]; then  

    echo "No group defined for $HOSTNAME. Skipping verification."  

    exit 0  

fi



echo "----------------------------------------------------------------------------"  

echo " [ 검증 시작 ] 서버: $HOSTNAME / 매칭 그룹: $GROUP"  

echo "----------------------------------------------------------------------------"



# 검증 결과 저장을 위한 변수  

FAIL_COUNT=0



# [함수] sysctl 파라미터 검증 (현재 값 vs 파일 값)  

verify_sysctl() {  

    local param=$1  

    local expected=$2  

      

    # 현재 커널에 적용된 실제 값 추출  

    local current_val=$(sysctl -n "$param" 2>/dev/null)  

    # 설정 파일(/etc/sysctl.conf)에 기록된 값 추출  

    local file_val=$(grep "^$param" /etc/sysctl.conf | awk -F'=' '{print $2}' | tr -d ' ')



    if [[ "$current_val" == "$expected" && "$file_val" == "$expected" ]]; then  

        echo " [V] $param : $expected (적용완료)"  

    else  

        echo " [X] $param : 기대값($expected) != 현재값($current_val) / 파일값($file_val)"  

        ((FAIL_COUNT++))  

    fi  

}



# [함수] limits.conf 검증  

verify_limit() {  

    local user=$1  

    local type=$2  

    local item=$3  

    local expected=$4  

      

    # limits.conf 파일 내 설정값 확인  

    local file_val=$(grep "^$user $type $item" /etc/security/limits.conf | awk '{print $4}')



    if [[ "$file_val" == "$expected" ]]; then  

        echo " [V] Limit $user $type $item : $expected (설정완료)"  

    else  

        echo " [X] Limit $user $type $item : 기대값($expected) != 파일값($file_val)"  

        ((FAIL_COUNT++))  

    fi  

}



# ------------------------------------------------------------------------------  

# 2. 그룹별 검증 로직 수행  

# ------------------------------------------------------------------------------



case $GROUP in  

    "EES-PHOTO"|"AR_FPA")  

        echo ">>> UDP Buffer Tuning 검증 중..."  

        verify_sysctl "net.core.rmem_max" "16777216"  

        verify_sysctl "net.core.wmem_max" "16777216"  

        verify_sysctl "net.core.rmem_default" "16777216"  

        verify_sysctl "net.core.wmem_default" "16777216"  

        ;;  

    "TC")  

        echo ">>> TC 특화 설정 검증 중..."  

        verify_sysctl "vm.overcommit_memory" "0"  

        verify_sysctl "net.core.rmem_max" "16777216"  

        verify_sysctl "net.core.wmem_max" "16777216"  

          

        # NIC Ring Buffer 스크립트 존재 여부 확인  

        if [ -f "/etc/NetworkManager/dispatcher.d/99-nic-buffer" ]; then  

            echo " [V] NIC Buffer Dispatcher 스크립트 존재함"  

        else  

            echo " [X] NIC Buffer Dispatcher 스크립트 누락"  

            ((FAIL_COUNT++))  

        fi  

        ;;  

    "MOS")  

        echo ">>> MOS 특화 설정 검증 중..."  

        verify_sysctl "net.core.rmem_max" "16777216"  

        verify_sysctl "net.core.wmem_max" "16777216"  

        verify_sysctl "net.core.rmem_default" "16777216"  

        verify_sysctl "net.core.wmem_default" "16777216"  

        verify_limit "*" "soft" "stack" "81920"  

        verify_limit "*" "hard" "stack" "81920"  

        verify_limit "*" "soft" "nofile" "8192"  

        verify_limit "*" "hard" "nofile" "8192"  

        ;;  

    "RMS")  

        echo ">>> RMS 특화 설정 검증 중..."  

        verify_limit "*" "soft" "stack" "81920"  

        verify_limit "*" "hard" "stack" "81920"  

        ;;  

    *)  

        echo "Unknown group $GROUP. Nothing to verify."  

        exit 0  

        ;;  

esac



# ------------------------------------------------------------------------------  

# 3. 최종 결과 보고  

# ------------------------------------------------------------------------------  

echo "----------------------------------------------------------------------------"  

if [ $FAIL_COUNT -eq 0 ]; then  

    echo "결과: 모든 설정이 성공적으로 적용되었습니다."  

else  

    echo "결과: 총 $FAIL_COUNT 건의 설정 오류가 발견되었습니다. 확인이 필요합니다."  

fi  

echo "----------------------------------------------------------------------------"  
