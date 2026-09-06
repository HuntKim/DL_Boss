# os-setup/linux

B Cloud 베어메탈 → A Cloud VM 마이그레이션 "단계 2": Assessment(단계 1)에서
조사된 자료를 기준으로 신규 VM에 계정/그룹, OS 파라미터, 스토리지, 디렉터리
권한을 구성한다.

`os-setup-main`과 별개의 새 구현이다. **CSV를 쓰지 않는다** - 모든 호스트별
데이터는 `config/os_env/<hostname>.env` 안에 bash 배열로 직접 선언한다.

## 디렉터리 구조

```
os-setup/linux/
├── init.sh                  # 6개 모듈을 순서대로 실행하는 오케스트레이터
├── config/
│   ├── common.env           # (신규 4모듈용) 공통 로그 함수 + env 로더 + manifest 헬퍼
│   ├── linux_common.env     # (SW모듈용, os-setup-main에서 그대로 가져옴) 로그 함수 등
│   ├── sw_mapping_linux.txt # (SW모듈용, os-setup-main에서 그대로 가져옴) 호스트별 SW 매핑
│   ├── tnsmanes/            # (SW모듈용, os-setup-main에서 그대로 가져옴) tnsnames.ora 예시
│   ├── env/
│   │   └── test.env                    # (SW모듈용, os-setup-main에서 그대로 가져옴)
│   ├── os_env/
│   │   ├── example_host.env.template   # (신규 4모듈용) 호스트별 env 파일 스키마 문서 겸 템플릿
│   │   └── <hostname>.env              # 실제 호스트별 정의 (호스트마다 1개, 직접 생성)
│   └── os_param_profiles/
│       └── <프로파일명>.param.conf   # sysctl+limits 값을 한 파일에 (네이티브 형식, "=" 유무로 자동 분류)
├── account/           # 계정/그룹: account_gen.sh / account_rollback.sh / account_verify.sh
├── os-parameter/      # OS 파라미터: os_param_apply.sh / os_param_rollback.sh / os_param_verify.sh
├── storage/           # 스토리지(LVM): storage_gen.sh / storage_rollback.sh / storage_verify.sh
├── permission/        # 디렉터리 권한: permission_apply.sh / permission_rollback.sh / permission_verify.sh
├── sw_modules/        # (os-setup-main에서 그대로 가져옴, 수정 없음) SW 설치: setup_sw.sh, install_*.sh
└── monitoring/        # (os-setup-main에서 그대로 가져옴, 수정 없음) 모니터링 에이전트: setup_monitoring.sh
```

**`sw_modules`/`monitoring`은 `os-setup-main`에서 그대로 복사해온 것이다** -
다운로드 URL, curl 옵션(`-k` 등), 내부 설치 로직을 전혀 수정하지 않았다
(바이트 단위로 동일함을 diff로 확인). `init.sh apply` 실행 시 계정→OS
파라미터→스토리지→권한 4단계가 전부 성공해야 5단계(SW 설치)·6단계
(모니터링)로 이어지며, 이 둘은 인자를 받지 않고(`-y` 옵션 없음) 자체적으로
hostname 기준 설정을 읽어 동작한다. 원래부터 rollback/verify 스크립트가
없어서(`os-setup-main`에도 없었음) `init.sh verify`/`rollback`에는 포함되지
않고 `apply`에만 있다.

`config/os_env/<hostname>.env`는 신규 4모듈(계정/OS파라미터/스토리지/권한)
전용이고, `config/env/<hostname>.env`는 SW 모듈(setup_sw.sh가 읽는 호스트별
오버라이드) 전용이다 - 처음엔 둘 다 `config/env/`를 써서 같은 파일을
가리키는 상태였는데, 헷갈린다는 지적을 받아 분리했다. 한 호스트에
계정/스토리지 설정과 SW 오버라이드가 둘 다 필요하면 두 파일을 각각 만들어야
한다.

## 사용법

1. `config/os_env/example_host.env.template`을 복사해 `config/os_env/<hostname>.env`로
   저장하고(파일명은 `hostname -s` 결과와 정확히 일치해야 함), Assessment
   결과(`accounts_gen_draft.csv`, `filesystem_gen_draft.txt` 등)를 참고해
   값을 채운다.
2. 신규 VM에서 root로 실행:
   ```bash
   sudo ./init.sh apply     # 계정 -> OS파라미터 -> 스토리지 -> 권한 순서로 적용
   sudo ./init.sh verify    # 4단계 전부 검증 (읽기 전용)
   sudo ./init.sh rollback  # 권한 -> 스토리지 -> OS파라미터 -> 계정 역순으로 롤백
   ```
   개별 모듈만 실행하려면 각 디렉터리의 스크립트를 직접 실행해도 된다
   (예: `./account/account_gen.sh -y`).
3. 프롬프트 확인 없이(예: 자동화 파이프라인) 실행하려면 `-y`/`--yes`를 붙인다.

## 설계 원칙

### 1. manifest 기반 롤백 - "우리가 실제로 만든 것"만 되돌린다
`config/os_env/<hostname>.env`에는 "이미 존재해야 하는 표준 그룹"(예: RHEL의
`wheel`)처럼 우리가 만들지 않은 항목도 섞여 있다. 개발 중 실제로
`account_rollback.sh`가 env 정의를 그대로 순회하며 지우도록 만들었다가
**사전에 있던 `sudo`/`wheel` 같은 시스템 그룹까지 삭제해버리는 사고를
테스트로 발견**했다. 그래서 모든 `_gen.sh`/`_apply.sh`는 "실제로 생성/변경한
것"만 `/os-setup-backup/<hostname>/`에 기록해두고, `_rollback.sh`는 반드시
이 기록만 근거로 되돌린다. env 정의를 직접 순회하며 삭제하는 rollback
스크립트는 없다.

### 2. OS 파라미터는 네이티브 형식 그대로, 파일 하나로 합쳐서
sysctl/limits 값은 커스텀 포맷으로 재발명하지 않고 실제 `sysctl.conf`/
`limits.conf` 문법 그대로 쓰되, 두 형식을 별도 파일로 나누지 않고
`config/os_param_profiles/<프로파일명>.param.conf` 한 파일에 섞어서
작성한다. 각 줄에 `"="`이 있으면 sysctl 값("key = value"), 없으면
limits 값("domain type item value", 공백 4컬럼)으로 자동 분류된다(두
형식 문법이 원래 겹치지 않아 별도 섹션 마커 없이 이 판별만으로 충분함).
파일을 여러 개 찾아다닐 필요 없이 한 파일만 열어서 수정하면 된다.

**프로파일명은 "도메인"이 아니라 "실제 값이 같은 단위"로 짓는다.** 같은
도메인(예: EES-PHOTO)이라도 WEB/WAS/DB처럼 역할이 다르거나 도메인 안에
여러 시스템이 있으면 값이 서로 다를 수 있다 - 이 경우 도메인명 하나로
퉁치면 안 되고 `EES-PHOTO-WEB.param.conf`, `EES-PHOTO-SYS1-DB.param.conf`
처럼 값이 실제로 같은 서버들끼리만 같은 프로파일명을 쓰도록 더 잘게
나눠야 한다. 정말 그 서버 하나만 특이하면 프로파일명을 그 호스트명으로
지으면 "서버 1대당 설정 파일 1개"가 그대로 재현된다(이전 방식과 동일).
값이 진짜 동일한 서버가 여러 대일 때만 프로파일을 공유해서 중복을 줄이면
된다 - 프로파일명을 얼마나 잘게 쪼갤지는 순전히 운영 판단의 영역이고
스크립트는 그 이름을 그대로 조회할 뿐이다.

### 3. sysctl 롤백은 "런타임 값"까지 복원한다
`/etc/sysctl.d/`에서 설정 파일을 지우는 것만으로는 이미 커널에 반영된
값이 되돌아가지 않는다(다음 부팅부터 재적용되지 않을 뿐). 그래서 적용
시점에 각 파라미터의 원래 런타임 값을 기록해두고, 롤백 시 `sysctl -w`로
직접 복원한다(테스트로 확인한 실제 동작 차이).

### 4. "스토리지 구성"과 "디렉터리 권한"은 분리된 단계
LVM 볼륨 생성(storage)과 디렉터리 owner/group/perm 설정(permission)은
별개 모듈이다. `permission_apply.sh`는 스토리지로 만들어지지 않은 일반
디렉터리의 권한도 다룰 수 있다. 새로 만든 디렉터리(사전에 없던 경로)는
롤백 시 삭제되고, 원래 있던 디렉터리는 백업해둔 원래 권한으로 복원된다 -
이 둘을 구분하지 않으면 롤백 후 빈 디렉터리가 잘못된 소유자로 남는
문제가 있어 분리했다.

### 5. `set -u`와 빈 배열
bash의 `set -u`(nounset) 아래에서는 완전히 선언되지 않은 배열은 물론,
`declare -A`만 하고 원소를 하나도 넣지 않은 연관 배열(`${#arr[@]}` 등)도
"unbound variable" 에러가 난다(테스트로 확인). 그래서 `common.env`는 호스트
env 파일을 소스하기 전에 모든 배열을 빈 값으로 미리 초기화하고, 스크립트
내에서 새로 선언하는 연관 배열은 항상 `declare -A NAME=()` 형태로 쓴다.

## 검증 현황

이 샌드박스(Ubuntu 컨테이너)에서 실제로 계정/그룹, OS 파라미터(sysctl
0→1→0 왕복 포함), 디렉터리 권한 모듈은 gen→verify→rollback 전체 사이클을
직접 실행해 확인했다. 스토리지 모듈은 loop device로 디스크 배정 로직·
mount·fstab 로직까지 확인했으나, 이 컨테이너에 device-mapper 커널 드라이버가
없어 실제 LVM 블록 디바이스 생성(pvcreate/vgcreate/lvcreate 이후 단계)까지는
끝까지 실행하지 못했다 - 해당 로직은 기존 `os-setup-main`의
`Linux_filesystem_gen.sh`에서 이미 실서버로 검증된 방식을 그대로 재사용한
것이다. **실제 RHEL 서버 1대에서 storage 모듈을 먼저 검증할 것을 권장한다.**
