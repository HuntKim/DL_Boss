# os-setup/windows

B Cloud 베어메탈 → A Cloud VM 마이그레이션 "단계 2" Windows 쪽. Linux 쪽
(`os-setup/linux`)과 동일한 설계 원칙(manifest 기반 롤백, CSV 미사용,
호스트별 env 파일)을 따른다.

**중요**: 기존 `os-setup-main/windows`에는 계정(account) 모듈만 있었고,
OS 파라미터/스토리지 모듈은 아예 없었다. 이 폴더의 os-parameter/storage는
교체가 아니라 새로 설계한 것이다. 또한 이 환경에는 PowerShell 실행 환경이
없어 **모든 스크립트가 코드 리뷰로만 검증됐고 실제 실행 테스트는 못
했다.** Linux 쪽처럼 loop device 등으로 라이브 검증을 하지 못했으니,
**반드시 실제 Windows Server 1대에서 먼저 검증**한 뒤 다른 서버로 확대할
것을 강하게 권장한다.

## 디렉터리 구조

```
os-setup/windows/
├── init.ps1                 # 6개 모듈을 순서대로 실행하는 오케스트레이터
├── config/
│   ├── common.ps1           # (신규 4모듈용) 공통 로그 함수 + env 로더 + manifest 헬퍼
│   ├── windows_common.ps1   # (SW모듈용, os-setup-main에서 그대로 가져옴)
│   ├── sw_mapping_window.txt # (SW모듈용, os-setup-main에서 그대로 가져옴)
│   ├── env/
│   │   └── test.ps1         # (SW모듈용, os-setup-main에서 그대로 가져옴)
│   ├── os_env/
│   │   ├── example_host.ps1.template
│   │   └── <hostname>.ps1   # 실제 호스트별 정의
│   └── os_param_profiles/
│       └── <프로파일명>/registry.reg   # 네이티브 .reg 형식
├── account/       # Account-Gen.ps1 / Account-Rollback.ps1 / Account-Verify.ps1
├── os-parameter/  # OsParam-Apply.ps1 / OsParam-Rollback.ps1 / OsParam-Verify.ps1
├── storage/       # Storage-Gen.ps1 / Storage-Rollback.ps1 / Storage-Verify.ps1
├── permission/    # Permission-Apply.ps1 / Permission-Rollback.ps1 / Permission-Verify.ps1
├── sw_modules/    # (os-setup-main에서 그대로 가져옴, 수정 없음) setup_sw.ps1, install_*.ps1
└── monitoring/    # (os-setup-main에서 그대로 가져옴, 수정 없음) setup_monitoring.ps1
```

**`sw_modules`/`monitoring`은 `os-setup-main`에서 그대로 복사해온 것이다**
(diff로 완전 동일 확인, 다운로드 URL/옵션 등 무수정). `init.ps1 -Mode apply`
실행 시 4단계가 전부 성공해야 5단계(SW 설치)·6단계(모니터링)로 이어지며,
이 둘은 인자 없이 `$env:COMPUTERNAME` 기준으로 동작한다. rollback/verify
스크립트가 원래 없어(`os-setup-main`에도 없었음) apply에만 포함된다.

## 사용법

1. `config/os_env/example_host.ps1.template`을 복사해 `config/os_env/<hostname>.ps1`로
   저장한다(파일명은 `$env:COMPUTERNAME` 값과 일치해야 함).
2. 신규 VM에서 관리자 권한 PowerShell로 실행:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode apply     # -Yes 로 확인 프롬프트 생략 가능
   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode verify
   powershell -ExecutionPolicy Bypass -File .\init.ps1 -Mode rollback
   ```

## 계정 비밀번호는 절대 저장하지 않는다

이전에 `windows_user_gen.txt`(CSV)에 평문 비밀번호가 커밋되어 있던 사고가
있었다. 이 재발을 막기 위해 `Account-Gen.ps1`은:
- 계정 생성 시 16자리 임의 비밀번호를 그 자리에서 생성
- **콘솔 출력으로 딱 한 번만 보여주고 어디에도 저장하지 않음**
- 계정을 "다음 로그온 시 반드시 암호 변경"으로 설정(WinNT ADSI provider의
  `PasswordExpired` 속성 사용 - `New-LocalUser` 자체는 이 옵션을 노출하지
  않음)

콘솔에 뜬 임시 비밀번호는 그 실행 세션에서만 볼 수 있으니 즉시 안전한
채널로 전달해야 한다.

## OS 파라미터는 네이티브 .reg 형식

Linux의 sysctl.conf와 같은 원칙: 커스텀 포맷을 만들지 않고 실제 `.reg`
파일 형식 그대로 작성해 `reg import`로 적용한다. 검증/롤백을 위해
dword/string 값만 별도로 추적하며(대부분의 튜닝 파라미터가 이 두 타입),
binary/multi-string 등 다른 타입은 적용은 되지만(reg import 자체가
처리) 이 스크립트의 확인·백업 대상에서는 빠지고 경고로 안내된다.

**프로파일명은 "도메인"이 아니라 "실제 값이 같은 단위"로 짓는다.** 같은
도메인이라도 역할(WEB/WAS/DB)이나 시스템이 다르면 값이 다를 수 있으니,
값이 실제로 같은 서버들끼리만 같은 프로파일명을 쓰도록 나눈다(예:
`EES-PHOTO-WEB`, `EES-PHOTO-SYS1-DB`). 그 서버 하나만 특이하면 프로파일명을
호스트명으로 지어 "서버 1대당 설정 파일 1개"를 그대로 재현하면 된다.

## 스토리지는 드라이브 문자 기준

`HostVolumes`에 "드라이브문자:크기(GB):레이블" 형식으로 정의하면,
RAW(초기화되지 않은) 디스크를 디스크 번호 순서대로 자동 배정해 GPT
파티션 + NTFS 포맷을 진행한다.

## 디렉터리 권한은 NTFS ACL 추가(grant) 방식

`HostDirPermissions`에 "경로:계정또는그룹:권한수준"
(FullControl/Modify/ReadAndExecute)으로 정의하면 해당 계정/그룹에 대한
ACL을 **추가**한다(기존 Administrators/SYSTEM 등의 권한은 그대로 유지,
전체 ACL을 덮어쓰지 않음). 새로 만든 디렉터리는 롤백 시 삭제되고,
기존에 있던 디렉터리는 SDDL로 백업해둔 원래 ACL로 복원된다.

## manifest 기반 롤백

Linux 쪽과 동일한 원칙 - 모든 `*-Gen.ps1`/`*-Apply.ps1`은 "실제로
생성/변경한 것"만 `C:\os-setup-backup\<hostname>\`에 기록하고, 롤백은
그 기록만 근거로 되돌린다. `$HostGroups`/`$HostAccounts` 등 env 정의를
직접 순회하며 삭제하는 롤백 스크립트는 없다(Administrators 같은 내장
그룹을 잘못 건드리는 사고를 막기 위함 - Linux 쪽 개발 중 실제로 겪은
문제라 Windows 쪽에도 처음부터 이 원칙을 적용함).

## 알려진 제한사항 (실서버 검증 시 확인 필요)

- 계정 삭제(rollback) 시 사용자 프로필 폴더(`C:\Users\<계정>`)는 자동
  삭제되지 않는다.
- `Account-Verify.ps1`의 그룹 소속 확인은 `Get-LocalGroupMember`의 반환
  형식(`컴퓨터명\계정명`)에 의존한다 - 도메인 계정이 섞여 있으면 별도
  처리가 필요할 수 있다.
- Storage 모듈은 RAW 디스크를 디스크 번호 순으로 기계적으로 배정한다 -
  디스크 크기가 요청 용량보다 큰지 등은 확인하지 않으므로, 디스크 구성이
  복잡한 서버는 결과를 꼭 확인할 것.
