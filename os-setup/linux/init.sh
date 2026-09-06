#!/bin/bash
# ==============================================================================
# os-setup/linux/init.sh
# 계정/그룹 -> OS 파라미터 -> 스토리지 -> 디렉터리 권한 -> SW 설치 -> 모니터링
# 순서로 실행하는 오케스트레이터.
# ==============================================================================
# 사용법:
#   sudo ./init.sh apply [-y|--yes]      6단계를 순서대로 적용 (기본값)
#   sudo ./init.sh verify                앞의 4단계만 순서대로 검증 (읽기 전용)
#   sudo ./init.sh rollback [-y|--yes]   앞의 4단계만 역순으로 롤백
#
# apply/rollback 도중 한 단계라도 실패하면 즉시 중단한다(다음 단계가
# 이전 단계 결과에 의존하기 때문 - 예: 스토리지 권한은 계정이 먼저
# 생성되어 있어야 함). verify는 실패한 항목이 있어도 전체 현황을 보기
# 위해 끝까지 계속 진행한다.
#
# ※ sw_modules/setup_sw.sh, monitoring/setup_monitoring.sh는
#   os-setup-main에서 그대로 가져온 것으로(다운로드 URL/curl 옵션 등
#   내부 로직 변경 없음), 인자를 받지 않고(-y 옵션 없음) 자체적으로
#   hostname 기준 설정을 읽어 동작한다. 또한 이 둘은 rollback/verify
#   스크립트가 원래부터 없어(os-setup-main에서도 없었음) apply 모드에만
#   포함하고, 앞의 4단계와 같은 공통 인자 루프에는 넣지 않는다.
# ==============================================================================
set -u

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-apply}"
shift || true

case "$MODE" in
    apply)
        steps=(
            "account/account_gen.sh"
            "os-parameter/os_param_apply.sh"
            "storage/storage_gen.sh"
            "permission/permission_apply.sh"
        )
        ;;
    verify)
        steps=(
            "account/account_verify.sh"
            "os-parameter/os_param_verify.sh"
            "storage/storage_verify.sh"
            "permission/permission_verify.sh"
        )
        ;;
    rollback)
        # 적용의 역순으로 되돌린다: 권한 -> 스토리지 -> OS 파라미터 -> 계정
        # (계정을 먼저 지워버리면 아직 남은 파일의 소유자가 사라져 뒤 단계
        # 확인이 꼬일 수 있으므로 항상 마지막에 지운다)
        steps=(
            "permission/permission_rollback.sh"
            "storage/storage_rollback.sh"
            "os-parameter/os_param_rollback.sh"
            "account/account_rollback.sh"
        )
        ;;
    *)
        echo "사용법: $0 {apply|verify|rollback} [-y|--yes]"
        exit 1
        ;;
esac

overall_fail=0
for step in "${steps[@]}"; do
    script_path="${CURRENT_DIR}/${step}"
    echo "=================================================="
    echo ">>> [${MODE}] 실행: ${step}"
    echo "=================================================="

    if bash "$script_path" "$@"; then
        echo ">>> 성공: ${step}"
    else
        echo ">>> 실패: ${step}"
        overall_fail=1
        if [ "$MODE" != "verify" ]; then
            echo "=================================================="
            echo "실패가 발생해 이후 단계를 중단합니다: ${step}"
            echo "=================================================="
            exit 1
        fi
        # verify는 실패해도 전체 현황을 보기 위해 계속 진행한다.
    fi
    echo
done

# ==============================================================================
# 5~6. SW 설치 / 모니터링 (apply 모드에서만, 인자 없이 실행)
# ==============================================================================
if [ "$MODE" = "apply" ] && [ "$overall_fail" -eq 0 ]; then
    for extra_step in "sw_modules/setup_sw.sh" "monitoring/setup_monitoring.sh"; do
        script_path="${CURRENT_DIR}/${extra_step}"
        if [ ! -f "$script_path" ]; then
            echo "건너뜀 (파일 없음): ${extra_step}"
            continue
        fi
        echo "=================================================="
        echo ">>> [${MODE}] 실행: ${extra_step}"
        echo "=================================================="
        if bash "$script_path"; then
            echo ">>> 성공: ${extra_step}"
        else
            echo ">>> 실패: ${extra_step}"
            overall_fail=1
            echo "=================================================="
            echo "실패가 발생해 이후 단계를 중단합니다: ${extra_step}"
            echo "=================================================="
            exit 1
        fi
        echo
    done
fi

if [ "$overall_fail" -eq 0 ]; then
    echo "=================================================="
    echo " ★ 전체 ${MODE} 완료 (모든 단계 성공)"
    echo "=================================================="
else
    echo "=================================================="
    echo " ${MODE} 완료 - 일부 항목 실패 (위 로그에서 [FAIL]/실패 항목 확인)"
    echo "=================================================="
fi

exit "$overall_fail"
