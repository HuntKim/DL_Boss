#!/bin/bash  
# ==========================================================================================    
#  [ Cloud OS Tech Service 리눅스 통합 설치 가이드 ]  
#  
#  본 스크립트는 OSmanaged Collector의 설치 및 구동 상태를 확인하고    
#  누락된 구성 요소만 선택적으로 설치하는 최적화 도구입니다.  
#  
#  [ 필수 실행 조건 ]    
#  1. root 권한 또는 sudo 권한이 있는 계정으로 실행해 주세요.    
#     (시스템 서비스 등록 및 /opt 경로 쓰기 권한이 필요합니다.)  
#  
#  [ 실행 순서 ]    
#  ------------------------------------------------------------------------------------------    
#  Step 1. 설치 스크립트 다운로드    
#    curl -s -k -L https://osmanaged.samsungds.net/os_setup/scripts/linux/monitoring/setup_monitoring.sh -o setup_monitoring.sh  
#  
#  Step 2. 스크립트 실행 권한 부여    
#    chmod +x setup_monitoring.sh  
#  
#  Step 3. 설치 스크립트 실행 (sudo 권한 필요)    
#    sudo ./setup_monitoring.sh    
#  ------------------------------------------------------------------------------------------  
#  
#  [ 주요 기능 ]    
#  - 서비스 상태(Active 여부) 및 크론탭 등록 여부 자동 체크    
#  - 로컬에 설치 파일(.sh)이 존재할 경우 네트워크 다운로드 없이 우선 설치    
#  - 필수 설정 파일(.conf, .keyfile 등) 자동 배치 및 통신 확인    
# ========================================================================================== 

set -e

echo "============================================================"  
echo " Cloud OS Tech Service 통합 설치를 시작합니다."  
echo "============================================================"

# 1. 환경 변수 설정  
BASE_DIR="/opt/osmanaged"  
# NODE_EXPORTER_PORT="9100"  
CURL_OPTS="--silent --insecure --retry 10 --retry-delay 10 --retry-connrefused"  
# NODE_INSTALLER="node-exporter-install.sh"  
COLLECTOR_INSTALLER="install.sh"

# [추가] 사전 통신 확인  
echo "[CHECK] osmanaged 서버 통신 상태를 확인합니다..."  
if curl -s -k -o /dev/null https://osmanaged.samsungds.net; then  
    echo " -> 통신 상태 정상"  
else  
    echo "------------------------------------------------------------"  
    echo "[ERROR] osmanaged 서버(https://osmanaged.samsungds.net)와 통신이 불가능합니다."  
    echo " 443 포트 오픈 여부를 확인해 주세요. (대상 IP: 10.172.104.132)"  
    echo "------------------------------------------------------------"  
    exit 1  
fi  

# ==============================================================================  
# [사전 체크] 에이전트 구동 상태 확인  
# ==============================================================================  
echo "[CHECK] 기존 에이전트 구동 상태를 확인합니다..."

# NODE_UP=false  
# if systemctl is-active --quiet node_exporter; then  
#     NODE_UP=true  
# fi

COLLECTOR_UP=false  
if [ -f "$BASE_DIR/bin/collector" ] && sudo crontab -l 2>/dev/null | grep -q "$BASE_DIR/bin/collector"; then  
    COLLECTOR_UP=true  
fi

if [ "$COLLECTOR_UP" = true ]; then  
    echo "------------------------------------------------------------"  
    echo "[결과] Collector가 이미 정상 작동 중입니다."  
    echo " 기존 설정을 유지하며 스크립트를 종료합니다."  
    echo "------------------------------------------------------------"  
    exit 0  
fi

echo " -> 설치가 필요하거나 일부 구성 요소가 누락되었습니다. 작업을 진행합니다."

# ==============================================================================  
# [모듈 1] Node Exporter 설치  
# ==============================================================================  
# if [ "$NODE_UP" = true ]; then  
#     echo "[1/2] Node Exporter: 이미 작동 중이므로 건너뜁니다."  
# else  
#     echo "[1/2] Node Exporter 설치 진행 중..."  
#     sudo systemctl stop node_exporter 2>/dev/null || true  
#     sudo systemctl disable node_exporter 2>/dev/null || true  
#     sudo find /etc/systemd/system/ -name "node_exporter.service" -exec rm {} \; 2>/dev/null || true  
#     sudo systemctl daemon-reload 2>/dev/null || true

#     if [ -f "$NODE_INSTALLER" ]; then  
#         echo " -> 로컬 설치 파일($NODE_INSTALLER)을 발견했습니다. 이를 사용하여 설치합니다."  
#         bash "$NODE_INSTALLER" $BASE_DIR $NODE_EXPORTER_PORT  
#     else  
#         echo " -> 로컬 설치 파일이 없습니다. 신규 다운로드 후 설치합니다."  
#         curl -s -k -L https://osmanaged.samsungds.net/agent_deploy/node-exporter-install.sh | bash -s -- $BASE_DIR $NODE_EXPORTER_PORT  
#     fi  
#     echo " -> Node Exporter 설치 완료."  
# fi

# ==============================================================================  
# [모듈 2] Collector 설치  
# ==============================================================================  
if [ "$COLLECTOR_UP" = true ]; then  
    echo "[2/2] Collector: 이미 정상 등록되어 있어 건너뜁니다."  
else  
    echo "[2/2] Collector 설치 진행 중..."  
    (crontab -l 2>/dev/null | grep -v "$BASE_DIR/bin/collector") | crontab -  
    sudo find $BASE_DIR/bin -type f -exec rm {} \; 2>/dev/null || true  
    sudo find $BASE_DIR/sbin -type f -exec rm {} \; 2>/dev///null || true

    if [ -f "$COLLECTOR_INSTALLER" ]; then  
        echo " -> 로컬 설치 파일($COLLECTOR_INSTALLER)을 발견했습니다. 이를 사용하여 설치합니다."  

	mkdir -p $BASE_DIR/sbin $BASE_DIR/bin $BASE_DIR/conf $BASE_DIR/log
	curl $CURL_OPTS -o $BASE_DIR/conf/agent.conf https://osmanaged.samsungds.net/agent_deploy/agent.conf
	curl $CURL_OPTS -o $BASE_DIR/conf/token.conf https://osmanaged.samsungds.net/agent_deploy/token.conf
	curl $CURL_OPTS -o $BASE_DIR/conf/.keyfile https://osmanaged.samsungds.net/agent_deploy/.keyfile

        bash "$COLLECTOR_INSTALLER"  
    else  
        echo " -> 로컬 설치 파일이 없습니다. 신규 다운로드 후 설치합니다."  
        mkdir -p $BASE_DIR/sbin $BASE_DIR/bin $BASE_DIR/conf $BASE_DIR/log  
        curl $CURL_OPTS -o $BASE_DIR/sbin/install https://osmanaged.samsungds.net/agent_deploy/install  
        curl $CURL_OPTS -o $BASE_DIR/sbin/uninstall https://osmanaged.samsungds.net/agent_deploy/uninstall  
        curl $CURL_OPTS -o $BASE_DIR/bin/collector https://osmanaged.samsungds.net/agent_deploy/collector  
        curl $CURL_OPTS -o $BASE_DIR/conf/agent.conf https://osmanaged.samsungds.net/agent_deploy/agent.conf  
        curl $CURL_OPTS -o $BASE_DIR/conf/token.conf https://osmanaged.samsungds.net/agent_deploy/token.conf  
        curl $CURL_OPTS -o $BASE_DIR/conf/.keyfile https://osmanaged.samsungds.net/agent_deploy/.keyfile  
        chmod +x $BASE_DIR/bin/* $BASE_DIR/sbin/*  
        chmod -R 600 $BASE_DIR/conf/  
    fi  

    # 버전 파일 생성
    $BASE_DIR/bin/collector --version > $BASE_DIR/conf/version  
    chmod 600 $BASE_DIR/conf/version        
      
    # [수정본] 임시 파일을 이용한 확실한 크론탭 등록 (권한 문제 원천 차단)  
    CRON_JOB="30 5 * * * $BASE_DIR/bin/collector > /dev/null 2>&1"  
    TMP_CRON="/tmp/osmanaged_cron_tmp"

    # 1. 현재 루트 크론탭 내용을 임시 파일로 백업 (없으면 빈 파일 생성)  
    sudo crontab -l > "$TMP_CRON" 2>/dev/null || touch "$TMP_CRON"

    # 2. 기존 내용 중 중복되는 collector 라인 제거 후 새 라인 추가  
    grep -v "$BASE_DIR/bin/collector" "$TMP_CRON" > "${TMP_CRON}.new" 2>/dev/null || touch "${TMP_CRON}.new"  
    echo "$CRON_JOB" >> "${TMP_CRON}.new"

    # 3. 완성된 파일을 사용하여 루트 크론탭에 강제 등록 (가장 확실한 방법)  
    sudo crontab "${TMP_CRON}.new"

    # 4. 임시 파일 삭제  
    rm -f "$TMP_CRON" "${TMP_CRON}.new"  
      
    echo " -> Collector 설치 및 스케줄링 완료."  

fi

# ==============================================================================  
# [최종 확인] 에이전트 동작 및 서버 통신 테스트  
# ==============================================================================  
echo "============================================================"  
echo "[FINAL] 최종 통신 및 버전 확인 중... (약 1분 소요될 수 있습니다)"  
echo "============================================================"  
$BASE_DIR/bin/collector --version || echo "버전 정보 확인 불가"

echo "============================================================"  
echo " 모든 체크 및 설치 절차가 성공적으로 완료되었습니다!"  
echo "============================================================"  
