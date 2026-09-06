# AS-IS 서버 정보 수집 (단계 1)

B Cloud 베어메탈 → A Cloud VM 마이그레이션 프로젝트의 "단계 1" 스크립트.
AS-IS 서버에서 **읽기 전용**으로 실행되며, 수집 외에 서버를 변경하거나
아무것도 설치하지 않는다.

## 수집 항목 (linux / windows 공통)

1. 계정/그룹 정보
2. OS 파라미터, 크론탭(윈도우는 예약 작업) 등 서버 설정 값
3. Storage 정보 (볼륨/파티션 구성)
4. SW 설치 정보/버전

## 사용법

### Linux (`linux/collect_as_is.sh`)
```bash
sudo ./collect_as_is.sh [출력_디렉토리]   # 기본값: /tmp/as_is_assessment
```
RHEL(rpm)/Ubuntu(dpkg) 자동 감지. root가 아니어도 실행되지만, 다른 계정의
crontab 조회 등 일부 항목은 권한이 있어야 정상적으로 수집된다.

### Windows (`windows/Collect-AsIs.ps1`)
```powershell
powershell -ExecutionPolicy Bypass -File .\Collect-AsIs.ps1 [-OutputDir <경로>]
# 기본값: C:\assessment_output
```
관리자 권한 권장 (예약 작업/방화벽 등 일부 항목은 권한이 있어야 조회됨).
**이 스크립트는 실제 Windows 환경에서 아직 실행 검증을 하지 못했다** (개발
환경에 PowerShell/Windows Server가 없어 코드 리뷰만 진행함). 처음엔 서버
1대에서 먼저 실행해 결과물을 확인한 뒤 전체 서버로 확대할 것을 권장한다.

## 출력물

호스트별로 아래 파일들이 생성되고, 전송 편의를 위해 압축 파일도 함께
만들어진다 (`<hostname>_assessment_<timestamp>.tar.gz` / `.zip`).

| 파일 | 내용 | 비고 |
|---|---|---|
| `accounts_raw_*` | 계정/그룹 원본 전체 | 감사/참고용 |
| `os_parameters.txt` | sysctl, limits, 네트워크, SELinux/방화벽 등 | 참고용 |
| `crontabs.txt` / `scheduled_tasks.txt` | 크론탭 / 예약 작업 | 참고용 |
| `storage.txt` | df, lsblk, blkid, fstab, LVM / Volume, Partition, Disk | 참고용 |
| `sw_packages_raw.txt` | 설치된 패키지/SW 전체 목록 | 참고용 |
| `sw_mapping_draft.txt` | JDK/Oracle Client 등 자동 인식 draft (`sw_mapping_linux.txt`/`sw_mapping_window.txt` 형식 - 이 부분은 os-setup에서도 SW 모듈이 원래 방식 그대로라 CSV 성격 그대로 유지됨) | **초안 - 검토 필요** |
| `os_param_profile_draft.param.conf` | Linux 전용, OS 파라미터 프로파일 draft (`sysctl.conf`/`sysctl.d`, `limits.conf`/`limits.d`에 실제로 적힌 줄만 모음 - `sysctl -a` 전체 덤프 아님) | **초안 - 검토 필요, 배포판 기본값이 섞여 있을 수 있음** |
| `os_env_draft.env` / `.ps1` | **계정+스토리지+권한을 하나로 합친 draft** (CSV 아님). `HOST_GROUPS`/`HOST_ACCOUNTS`/`HOST_FILESYSTEMS`/`HOST_DIR_PERMISSIONS` (linux) 또는 `$HostGroups`/`$HostAccounts`/`$HostVolumes`/`$HostDirPermissions` (windows) 배열을 전부 담고 있어, 검토 후 파일명을 `<hostname>.{env,ps1}`로 바꿔서 `config/os_env/`에 두면 그대로 쓸 수 있다 | **초안 - 검토 필요** |

**`os_env_draft.env`/`.ps1`은 반드시 사람이 검토한 후** 파일명을
`<hostname>.env`/`.ps1`로 바꿔 `os-setup/{linux,windows}/config/os_env/`
아래 그대로 두면 된다(내용 수정 없이 파일명만 바꿔도 되도록 os-setup이
그대로 기대하는 배열 형식으로 생성됨 - 실제로 os-setup의
`account_verify.sh`로 인식되는 것까지 확인함). `HOST_OS_PARAM_PROFILE`은
기본으로 호스트명이 들어있다(서버 1대당 프로파일 파일 1개가 기본 - 다른
서버와 값이 완전히 같다고 확인되면 그 서버들과 같은 프로파일명으로 바꿔서
공유해도 된다). `os_param_profile_draft.param.conf`(Linux)를 검토해서
배포판 기본값을 걷어내고 실제 필요한 값만 남긴 뒤
`config/os_param_profiles/<프로파일명>.param.conf`로 옮기면 된다 - 실제로
파일명만 바꿔서 `os_param_apply.sh`가 인식하는 것까지 확인함. Windows는
레지스트리 특성상 "뭐가 커스텀인지" 안전하게 구분하기 어려워 이 draft가
없고, `HostOsParamProfile`을 직접 채워야 한다.
`sw_mapping_draft.txt`는 `config/sw_mapping_*.txt`에 별도로 반영한다(SW
모듈은 원래 방식 그대로 유지되는 부분이라 자동 병합되지 않음).

## 계정 정보와 비밀번호

이 스크립트들은 **계정의 비밀번호를 어떤 형태로도 수집/저장하지 않는다.**
(이전에 `windows_user_gen.txt`에 평문 비밀번호가 커밋되어 있던 문제가 있어
삭제 및 회전 조치함 — 계정 자동화를 다시 설계할 때도 비밀번호는 다루지
않는 방식으로 갈 것.) TO-BE 서버에 계정을 생성할 때는 이 draft로 계정
목록/그룹만 참고하고, 비밀번호는 별도 채널로 새로 발급해야 한다.

## draft 자동 인식의 한계

- **계정**: 로그인 쉘이 "실사용 쉘"(bash/csh/ksh 등)인 계정만 대상으로
  하고, 표준 시스템/서비스 계정(nologin류)과 `root`/내장 계정은 제외한다.
- **Storage**: (Linux) LVM 볼륨그룹명은 조회를 시도하지만 실패 시 `appvg`로
  표시된다. LVM이 아닌 구성은 draft가 정확하지 않을 수 있다. (Windows)
  시스템 드라이브(보통 C:) 외의 고정 드라이브만 `$HostVolumes`에 담기며,
  `$HostDirPermissions`(NTFS ACL)는 자동 판단이 어려워 항상 빈 배열로
  남겨두므로 직접 채워야 한다.
- **SW**: 이 프로젝트가 이미 자동화 대상으로 다루는 JDK(OpenJDK/Oracle
  JDK)와 Oracle Client만 자동 인식한다. 그 외 일반 패키지(`pkg_` 접두사
  대상)는 `sw_packages_raw.txt` 전체 목록을 보고 사람이 직접 판단해서
  추가해야 한다 - AS-IS에 깔려 있다고 TO-BE에도 전부 필요한 건 아니기
  때문이다. Windows `.NET Framework`도 레지스트리 Release 번호만 확인하고
  정확한 버전 문자열 매핑은 수동 확인이 필요하다.
