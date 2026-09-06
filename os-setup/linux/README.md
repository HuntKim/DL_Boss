# os-setup/linux

B Cloud 베어메탈 → A Cloud VM 마이그레이션 "단계 2": Assessment(단계 1)에서
조사된 자료를 기준으로 신규 VM에 계정/그룹, OS 파라미터, 스토리지, 디렉터리
권한을 구성한다.

`os-setup-main`과 별개의 새 구현이다. **CSV를 쓰지 않는다** - 모든 호스트별
데이터는 `config/env/<hostname>.env` 안에 bash 배열로 직접 선언한다.

## 디렉터리 구조

```
os-setup/linux/
├── init.sh                  # 4개 모듈을 순서대로 실행하는 오케스트레이터
├── config/
│   ├── common.env           # 공통 로그 함수 + env 로더 + manifest(생성기록) 헬퍼
│   ├── env/
│   │   ├── example_host.env.template   # 호스트별 env 파일 스키마 문서 겸 템플릿
│   │   └── <hostname>.env              # 실제 호스트별 정의 (호스트마다 1개, 직접 생성)
│   └── os_param_profiles/
│       └── <프로파일명>/{sysctl.conf,limits.conf}   # 네이티브 형식 그대로
├── account/           # 계정/그룹: account_gen.sh / account_rollback.sh / account_verify.sh
├── os-parameter/      # OS 파라미터: os_param_apply.sh / os_param_rollback.sh / os_param_verify.sh
├── storage/           # 스토리지(LVM): storage_gen.sh / storage_rollback.sh / storage_verify.sh
└── permission/        # 디렉터리 권한: permission_apply.sh / permission_rollback.sh / permission_verify.sh
```

## 사용법

1. `config/env/example_host.env.template`을 복사해 `config/env/<hostname>.env`로
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
`config/env/<hostname>.env`에는 "이미 존재해야 하는 표준 그룹"(예: RHEL의
`wheel`)처럼 우리가 만들지 않은 항목도 섞여 있다. 개발 중 실제로
`account_rollback.sh`가 env 정의를 그대로 순회하며 지우도록 만들었다가
**사전에 있던 `sudo`/`wheel` 같은 시스템 그룹까지 삭제해버리는 사고를
테스트로 발견**했다. 그래서 모든 `_gen.sh`/`_apply.sh`는 "실제로 생성/변경한
것"만 `/os-setup-backup/<hostname>/`에 기록해두고, `_rollback.sh`는 반드시
이 기록만 근거로 되돌린다. env 정의를 직접 순회하며 삭제하는 rollback
스크립트는 없다.

### 2. OS 파라미터는 네이티브 형식 그대로
sysctl/limits 값은 커스텀 포맷으로 재발명하지 않고 실제 `sysctl.conf`/
`limits.conf` 형식 그대로 프로파일 파일에 작성한다. 파싱 로직이 따로
필요 없고, 사람이 봐도 바로 이해된다.

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
