#!/bin/bash



# ==============================================================================  

# 리눅스 계정 및 시스템 전역 설정 검증 스크립트 (최종 확장본)  

# ==============================================================================



# 현재 실행 중인 스크립트의 절대 경로를 획득  
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(cd "$CURRENT_DIR/../config" && pwd)"
CONFIG_FILE="${CONFIG_DIR}/Linux_user_gen.csv"



if [[ $EUID -ne 0 ]]; then  

    echo "Error: This script must be run as root"  

    exit 1  

fi



log() {  

    local level=$1  

    local msg=$2  

    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")  

    echo -e "[$timestamp] [$level] $msg"  

}



print_res() {  

    local status=$1  

    local msg=$2  

    if [ "$status" = "OK" ]; then  

        echo -e "  \x1b[32m[✅ OK]\x1b[0m $msg"  

    else  

        echo -e "  \x1b[31m[❌ FAIL]\x1b[0m $msg"  

    fi  

}



# 1. 설정값 추출  

HOSTNAME=$(hostname -s)  

if [ ! -f "$CONFIG_FILE" ]; then echo "Error: Config file not found."; exit 1; fi  

if ! grep -q "^$HOSTNAME," "$CONFIG_FILE"; then echo "No config for $HOSTNAME"; exit 0; fi



echo -e "\n===================================================="  

echo "       [ 계정 및 시스템 설정 검증 - 서버: $HOSTNAME ]"  

echo "===================================================="



# ------------------------------------------------------------------------------  

# [파트 1] 개별 계정 설정 검증 (CSV 기반)  

# ------------------------------------------------------------------------------  

tail -n +2 "$CONFIG_FILE" | while IFS=',' read -r server user group uid gid home shell rest  

do  

    if [[ "$server" != "$HOSTNAME" ]]; then continue; fi



    echo -e "\n>>> Verifying User: \x1b[1m$user\x1b[0m"



    if id "$user" > /dev/null 2>&1; then  

        # UID/GID 확인  

        ACTUAL_UID=$(id -u "$user")  

        ACTUAL_GID=$(id -g "$user")  

        [[ "$ACTUAL_UID" == "$uid" && "$ACTUAL_GID" == "$gid" ]] && print_res "OK" "UID/GID match ($uid:$gid)" || print_res "FAIL" "UID/GID mismatch"



        # 셸/홈 확인  

        ACTUAL_SHELL=$(getent passwd "$user" | cut -d: -f7)  

        [[ "$ACTUAL_SHELL" == "$shell" ]] && print_res "OK" "Shell match ($shell)" || print_res "FAIL" "Shell mismatch"  

        [ -d "$home" ] && print_res "OK" "Home directory exists" || print_res "FAIL" "Home directory missing"



        # 보조 그룹 확인  

        IFS=',' read -ra SEC_GROUPS <<< "$rest"  

        for sgroup in "${SEC_GROUPS[@]}"; do  

            if [ -n "$sgroup" ]; then  

                id -nG "$user" | grep -qw "$sgroup" && print_res "OK" "SecGroup: $sgroup" || print_res "FAIL" "SecGroup missing: $sgroup"  

            fi  

        done  

    else  

        print_res "FAIL" "User account does not exist!"  

    fi  

done



# ------------------------------------------------------------------------------  

# [파트 2] 시스템 전역 및 관리자 특수 설정 검증 (account.sh 내용)  

# ------------------------------------------------------------------------------  

echo -e "\n>>> Verifying System Global & Admin Settings..."



# 1. osmanaged sudo 권한 확인  

if grep -q "osmanaged ALL=(ALL) NOPASSWD: ALL" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then  

    print_res "OK" "osmanaged has NOPASSWD sudo privileges"  

else  

    print_res "FAIL" "osmanaged sudo privileges NOT set"  

fi



# 2. root 계정 패스워드 정책 확인 (Max days: 99999)  

#ROOT_MAX=$(chage -l root | grep "Maximum number of days" | awk '{print $NF}')  
#
#if [[ "$ROOT_MAX" == "99999" ]]; then  
#
#    print_res "OK" "root password policy: MaxDays=99999"  
#
#else  
#
#    print_res "FAIL" "root password policy mismatch (Actual: $ROOT_MAX)"  
#
#fi



# 3. osmanaged 패스워드 만료 주기 확인  

# osmanaged: -1 (Never expires)  

OSM_MAX=$(chage -l osmanaged 2>/dev/null | sed -n '6p' | awk '{print $NF}')  

if [[ "$OSM_MAX" == "-1" || "$OSM_MAX" == "99999" ]]; then  

    print_res "OK" "osmanaged password: Never expires"  

else  

    print_res "FAIL" "osmanaged password expires (Actual: $OSM_MAX)"  

fi

# 4. osmanaged umask 037 설정 확인 (.bashrc, .bash_profile)  

UMASK_CHECK=true  

if [ -f "/home/osmanaged/.bashrc" ] && ! grep -q "umask 037" "/home/osmanaged/.bashrc"; then UMASK_CHECK=false; fi  

if [ -f "/home/osmanaged/.bash_profile" ] && ! grep -q "umask 037" "/home/osmanaged/.bash_profile"; then UMASK_CHECK=false; fi



if [ "$UMASK_CHECK" = true ]; then  

    print_res "OK" "osmanaged umask 037 set in shell profiles"  

else  

    print_res "FAIL" "osmanaged umask 037 missing in profiles"  

fi



echo -e "\n===================================================="  

echo "검증 완료. 위 로그에서 [❌ FAIL] 항목이 있는지 확인하십시오."  

echo "===================================================="
