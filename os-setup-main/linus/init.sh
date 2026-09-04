#!/bin/bash

# ==============================================================================  
# Script Name    : init.sh  
# Description    : OS Setup 파일 및 구조 자동 배포 스크립트 (RHEL 8/9 호환)  
# ------------------------------------------------------------------------------  
# [Quick Guide]  
# 방법 1. 다운로드 후 실행:  
#   curl -s -k -L https://osmanaged.samsungds.net/os_setup/scripts/linux/init.sh -o init.sh  
#   bash init.sh  
#  
# 방법 2. 다운로드 없이 즉시 실행 (추천):  
#   curl -s -k -L https://osmanaged.samsungds.net/os_setup/scripts/linux/init.sh | bash  
# ==============================================================================  

# 1. 기본 설정 (중앙 서버 정보)  
BASE_URL="https://osmanaged.samsungds.net/os_setup/scripts/linux"  
TARGET_ROOT="/tmp/os-setup/linux"
LOG_DIR="/tmp/os-setup/log"  
LOG_FILE="$LOG_DIR/os-setup_init_$(date +%Y%m%d_%H%M%S).log"
HOSTNAME=$(hostname)

# 기존 작업 영역 삭제 (Fresh Install을 위해)  
# 로그 폴더(/tmp/os-setup/log)는 유지
if [ -d "$TARGET_ROOT" ]; then    
    echo "[INFO] Cleaning up previous installation files..."    
    rm -rf "$TARGET_ROOT"  
fi

# 로그 디렉토리 생성 (로그 파일 생성 전 필수 실행)  
mkdir -p $LOG_DIR

# 로그 시작  
echo "===============================================================" | tee -a $LOG_FILE  
echo "  OS Setup Initialization started at $(date)" | tee -a $LOG_FILE  
echo "  Target Host: $HOSTNAME" | tee -a $LOG_FILE  
echo "===============================================================" | tee -a $LOG_FILE

# 2. OS 버전 확인 (RHEL 8.x, 9.x 대응)  
if [ -f /etc/redhat-release ]; then  
    OS_VER=$(cat /etc/redhat-release | grep -oP '\d+\.\d+')  
    echo "[INFO] Detected OS Version: $OS_VER" | tee -a $LOG_FILE  
else  
    echo "[ERROR] Cannot detect RedHat version. This script is for RHEL only." | tee -a $LOG_FILE  
    exit 1  
fi

# 3. 디렉토리 구조 생성 (상대 경로 유지를 위해 반드시 필요)  
echo "[INFO] Creating directory structure..." | tee -a $LOG_FILE  
mkdir -p $TARGET_ROOT/config/env
mkdir -p $TARGET_ROOT/config/tnsnames
mkdir -p $TARGET_ROOT/account
mkdir -p $TARGET_ROOT/os-parameter
mkdir -p $TARGET_ROOT/file-system  
mkdir -p $TARGET_ROOT/sw-modules
mkdir -p $TARGET_ROOT/monitoring

# 4. 파일 다운로드 함수 (중복 코드 방지)  
download_file() {  
    local remote_path=$1  
    local local_path=$2  
      
    # -f 옵션 추가: 서버 에러(404 등) 발생 시 파일을 생성하지 않고 즉시 실패 처리  
    # -s -k -L은 유지  
    curl -s -f -k -L "$BASE_URL/$remote_path" -o "$local_path"  
      
    if [ $? -eq 0 ]; then  
        echo "[DOWNLOAD] $remote_path $\rightarrow$ $local_path" | tee -a $LOG_FILE  
    else  
        # 파일이 없거나 다운로드 실패 시, 생성된 빈 파일(또는 에러파일) 삭제  
        rm -f "$local_path"  
        echo "[SKIP] $remote_path not found or download failed. Skipping..." | tee -a $LOG_FILE  
    fi  
}

download_and_convert() {    
    local remote_path=$1    
    local local_path=$2    
    local tmp_file="${local_path}.tmp"

    # 1. .txt 파일을 다운로드하여 임시 파일로 저장  
    curl -s -f -k -L "$BASE_URL/$remote_path" -o "$tmp_file"    
        
    if [ $? -eq 0 ]; then    
        # 2. 윈도우 줄바꿈(\r)을 제거하며 .csv 파일로 저장 (이 과정에서 인코딩 정돈)  
        tr -d '\r' < "$tmp_file" > "$local_path"  
        rm -f "$tmp_file"  
        echo "[CONVERTED] $remote_path $\rightarrow$ $local_path" | tee -a $LOG_FILE    
    else    
        rm -f "$tmp_file"    
        echo "[SKIP] $remote_path not found or download failed. Skipping..." | tee -a $LOG_FILE    
    fi    
}  

# 5. 파일 다운로드 실행

# 5.1 Config 영역
echo "[INFO] Downloading configuration files..." | tee -a $LOG_FILE  
download_and_convert "config/Linux_user_gen.txt" "$TARGET_ROOT/config/Linux_user_gen.csv"      
download_and_convert "config/os_param_apply.txt" "$TARGET_ROOT/config/os_param_apply.csv"      
download_and_convert "config/Linux_filesystem_gen.txt" "$TARGET_ROOT/config/Linux_filesystem_gen.csv" 
download_file "config/sw_mapping_linux.txt" "$TARGET_ROOT/config/sw_mapping_linux.txt"  
download_file "config/linux_common.env" "$TARGET_ROOT/config/linux_common.env"  
download_file "config/env/$HOSTNAME.env" "$TARGET_ROOT/config/env/$HOSTNAME.env"
download_file "config/tnsnames/$HOSTNAME.tnsnames.ora" "$TARGET_ROOT/config/tnsnames/$HOSTNAME.tnsnames.ora"

# 5.2 메인 공통 스크립트  
# echo "[INFO] Downloading common script..." | tee -a $LOG_FILE  
# download_file "common.sh" "$TARGET_ROOT/common.sh"

# 5.3 계정 관리 모듈  
echo "[INFO] Downloading account modules..." | tee -a $LOG_FILE  
ACCT_MODULES_URL="${BASE_URL}/account/"

ACCT_FILES=$(curl -s -k -L "$ACCT_MODULES_URL" | grep -ioE 'href="[^"]+\.sh"' | cut -d'"' -f2 | grep -v "/")  

if [ -z "$ACCT_FILES" ]; then  
    echo "[WARN] account 폴더에서 다운로드할 .sh 파일을 찾지 못했습니다." | tee -a $LOG_FILE   
else 
    for FILE in $ACCT_FILES; do  
        download_file "account/$FILE" "$TARGET_ROOT/account/$FILE"  
    done  
fi

# 5.4 OS 파라미터 설정 모듈  
echo "[INFO] Downloading os-parameter modules..." | tee -a $LOG_FILE  
OS_PARAM_MODULES_URL="${BASE_URL}/os-parameter/"

OS_PARAM_FILES=$(curl -s -k -L "$OS_PARAM_MODULES_URL" | grep -ioE 'href="[^"]+\.sh"' | cut -d'"' -f2 | grep -v "/")  

if [ -z "$OS_PARAM_FILES" ]; then  
    echo "[WARN] os-parameter 폴더에서 다운로드할 .sh 파일을 찾지 못했습니다." | tee -a $LOG_FILE   
else 
    for FILE in $OS_PARAM_FILES; do  
        download_file "os-parameter/$FILE" "$TARGET_ROOT/os-parameter/$FILE"  
    done  
fi

# 5.5 파일시스템 관리 모듈  
echo "[INFO] Downloading file-system modules..." | tee -a $LOG_FILE  
FILE_SYS_MODULES_URL="${BASE_URL}/file-system/"

FILE_SYS_FILES=$(curl -s -k -L "$FILE_SYS_MODULES_URL" | grep -ioE 'href="[^"]+\.sh"' | cut -d'"' -f2 | grep -v "/")  

if [ -z "$FILE_SYS_FILES" ]; then  
    echo "[WARN] file-system 폴더에서 다운로드할 .sh 파일을 찾지 못했습니다." | tee -a $LOG_FILE   
else 
    for FILE in $FILE_SYS_FILES; do  
        download_file "file-system/$FILE" "$TARGET_ROOT/file-system/$FILE"  
    done  
fi


# 5.6 monitoring 설치 모듈  
echo "[INFO] Downloading monitoring modules..." | tee -a $LOG_FILE  
download_file "monitoring/setup_monitoring.sh" "$TARGET_ROOT/monitoring/setup_monitoring.sh"  

# 5.7 SW 설치 모듈  
echo "[INFO] Downloading all SW modules..." | tee -a $LOG_FILE

# sw_modules 폴더의 URL 설정  
SW_MODULES_URL="${BASE_URL}/sw-modules/"

# 1. HTML에서 .sh 확장자로 끝나는 모든 파일명 추출  
SW_FILES=$(curl -s -k -L "$SW_MODULES_URL" | grep -ioE 'href="[^"]+\.sh"' | cut -d'"' -f2 | grep -v "/")  

if [ -z "$SW_FILES" ]; then  
    echo "[WARN] sw_modules 폴더에서 다운로드할 .sh 파일을 찾지 못했습니다." | tee -a $LOG_FILE   
else  
    # 2. 추출된 파일 리스트를 루프 돌며 하나씩 다운로드  
    for FILE in $SW_FILES; do  
        # 원격 경로: sw_modules/파일명 -> 로컬 경로: $TARGET_ROOT/sw_modules/파일명  
        download_file "sw-modules/$FILE" "$TARGET_ROOT/sw-modules/$FILE"  
    done  
fi  


# 6. 모든 설정 및 스크립트 파일의 줄바꿈 변환 및 권한 부여    
echo "[INFO] Fixing line endings for all config and script files..." | tee -a $LOG_FILE

# 처리할 확장자 지정 (쉘스크립트, 환경설정파일, 텍스트 파일 등)    
# $ ... $ 괄호를 사용하여 OR 조건을 묶음
find $TARGET_ROOT -type f \( -name "*.sh" -o -name "*.env" -o -name "*.txt" -o -name "*.csv" -o -name "*.ora" \) | while read -r file; do   
    # CRLF -> LF 변환 (윈도우 줄바꿈 제거)    
    sed -i 's/\r$//' "$file"    
        
    # .sh 파일인 경우에만 실행 권한 부여    
    if [[ "$file" == *.sh ]]; then    
        chmod +x "$file"    
    fi    
        
    echo "[FIXED] $file" >> $LOG_FILE    
done  


echo "===============================================================" | tee -a $LOG_FILE  
echo "  Initialization Completed Successfully!" | tee -a $LOG_FILE  
echo "  Path: $TARGET_ROOT" | tee -a $LOG_FILE  
# echo "  Next Step: bash $TARGET_ROOT/common.sh" | tee -a $LOG_FILE  
echo "===============================================================" | tee -a $LOG_FILE  
