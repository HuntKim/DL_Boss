# Claude 작업 로그

> Claude와의 대화 세션에서 다룬 내용을 정리한 기록이다. 실제 커밋된 변경
> 사항은 커밋 해시를 함께 남기고, 논의만 되고 아직 반영되지 않은 항목은
> 별도로 표시했다.

## 1. SVN(Apache Subversion) 설치 스크립트 추가

- `os-setup/linux/sw_modules/install_svn.sh` 신규 작성
- RHEL 8/9(`dnf`), Ubuntu 22.04(`apt`) 자동 감지 후 분기, 저장소 최신 버전 설치
- 멱등성 처리(이미 설치된 경우 갱신 시도), 설치 결과 검증 포함
- 이 샌드박스(Ubuntu 24.04)에서 `apt` 경로 실제 실행 테스트 완료
- 커밋: `a1d31c4`

## 2. OS 모니터링 알림 기준 정의서 작성

- `Monitoring/OS-모니터링-알림기준.md` 신규 작성 (`Monitoring/BBT-요건` 기반)
- 알림 등급(A/B/C/D) × 운영등급(M0~M4) 매핑 정리
- 알림 등급별 통보 채널(메일/메신저/SMS) 기준 정의
- CPU / Memory / Disk / File System / Ping Fail / Hang / OS 커널 오류
  7개 항목별 임계치 정리 (Hang은 원문에 없어 신규 정의)
- `/var/log` 로그 기반 탐지 문구(grep 패턴) 정리
- 커밋: `2404658`

## 3. Oracle Client — tnsping / Instant Client 관련 논의

- **Oracle Instant Client에는 `tnsping`이 포함되지 않음** (Oracle 공식 미지원,
  Tools 패키지에도 없음)
- 대안으로 검토한 방법
  - `sqlplus -L dummy/dummy@ALIAS` 더미 로그인 후 에러코드(`ORA-01017`,
    `ORA-12154`, `ORA-12541`, `ORA-12170`)로 상태 판단
  - `/dev/tcp`를 이용한 단순 포트 오픈 확인 (TNS 프로토콜 검증은 아님)
  - 정식 Client 서버에서 `tnsping` 바이너리만 복사해오는 워크어라운드
    (버전 일치 필요, `ldd`로 의존 라이브러리 확인 권장, 비공식 방법)
- 최종적으로 tnsping이 꼭 필요하다는 방향으로 결론 → 정식 Client(19c) 유지

## 4. `install_oracle.sh` 문제 진단 및 수정

### 4.1 ZIP 파일 탐색 로직 (별도 파일 기준 진단, 저장소에는 미반영)

- 증상: `curl`로 디렉토리를 조회하면 파일이 분명히 보이는데 스크립트는
  "zip 파일을 찾을 수 없음"으로 실패
- 원인: 대상 서버 응답이 HTML `href="..."` 형태가 아니라 평문 목록
  (타임스탬프 / 용량 / 파일명, 공백 구분)이라 `grep -oE '[^"]+\.zip'`
  (큰따옴표 기준 파싱)이 통째로 어긋남
- 제안한 수정:
  ```bash
  ZIP_FILE=$(curl -sf "$DIR_URL/" | grep -E '\.zip$' | awk '{print $NF}' | head -n 1)
  ```

### 4.2 `runInstaller -ignoreSysPrereqs` 오류 수정 (반영됨)

- 증상: `[INS-04009] 전달된 인수 [-ignoreSysPrereqs]은(는) 현재 컨텍스트
  ClientSetup에서 지원되지 않습니다`
- 원인: `-ignoreSysPrereqs`는 DB 설치 컨텍스트/구버전용 플래그이고, 19c
  Client Setup에서는 `-silent` 하위에 `-ignorePrereqFailure`만 지원
- 수정: `os-setup-main/linus/sw_modules/install_oracle.sh`의 runInstaller
  호출부 플래그 교체, 사유 주석 추가
- 커밋: `9593861`

## 5. Oracle Client 19c 홈(Home) 복제 절차 정리

정상 설치된 `/oracle/Client`, `/oracle/orainventory`를 새 서버에 그대로
복사해 재사용하는 시나리오에 대해 정리한 절차:

1. **사전 조건**: 소스/대상 OS 메이저 버전 일치, oracle 계정 UID/GID 일치
2. **복사**: 권한/심볼릭 링크 보존을 위해 `tar cpf`(또는 `tar cvpf`) 사용
   ```bash
   tar cvpf - -C /oracle Client orainventory | ssh target_server "tar xvpf - -C /oracle"
   ```
   (`-v`는 진행 로그 출력용, `-p`는 권한 보존용 — 이후 `chown/chmod`로
   최종 확정하므로 필수는 아님)
3. **복사 후 조치**
   - `chown -R oracle:dba`, `chmod -R 750` 재적용
   - `/etc/oraInst.loc` 신규 생성 (디렉토리 복사에 포함되지 않음)
     inventory_loc=/oracle/orainventory
     inst_group=dba
   - oracle 계정 `.bash_profile`에 `ORACLE_HOME`, `ORACLE_BASE`,
     ```
     TNS_ADMIN`, `LD_LIBRARY_PATH`, `PATH` 등 환경변수 추가
     export ORACLE_HOME=/oracle/CLIENT/oracle
     export ORACLE_BASE=/oracle/CLIENT
     export UNIX_GROUP_NAME=dba
     export INVENTORY_LOCATION=/oracle/orainventory
     export TNS_ADMIN=$ORACLE_HOME/network/admin
     export LD_LIBRARY_PATH=$ORACLE_HOME/lib
     export PATH=$ORACLE_HOME/bin:$PATH
     ```
   - echo "/oracle/CLIENT/oracle/lib" > /etc/ld.so.conf.d/oracle-client.conf
   - ldconfig
   - `/etc/ld.so.conf.d/oracle-client.conf` + `ldconfig` (root 등 다른 계정
     대응)
   - 대상 서버 전용 `tnsnames.ora`로 교체
4. **참고**: 단순 복사만으로는 Oracle Inventory에 해당 호스트가 등록되지
   않아 이후 OPatch 패치 관리 시 문제될 수 있음 — 필요 시 `attachHome`
   절차 추가 검토
   ```
    su - oracle
    cd /oracle/CLIENT/oracle
    CV_ASSUME_DISTID=OEL7.8 ./runInstaller -silent -attachHome \
    ORACLE_HOME=/oracle/CLIENT/oracle \
    ORACLE_HOME_NAME=OraCleient19Home1

   ==> 동작은 정상 [WARNING] [INS-08101] Unexpected error while executing the action at state: 'clientSupportedOSCheck'
   CAUSE: No additional information available.
   ACTION: Contact Oracle Support Services or refer to the software manual.
   SUMMARY:
       - java.lang.NullPointerException

   ```
   [확인]
   ```
   $ORACLE_HOME/OPatch/opatch lsinventory
   /oracle/oraInventory/ContentsXML/inventory.xml  //ORACLE HOME NAME이 지정되어 있는지 확인
   ```
   위에서 등록한 HOME 경로/이름 확인
   
## 6. GitHub 연동 및 `install_oracle2.sh`(golden image clone 설치) 도입

- PAT(Personal Access Token)으로 `HuntKim/DL_Boss` 저장소에 연결, 다른 세션에서
  작업해둔 `install_oracle2.sh`(문법 검사 완료본)를 최초 반영 — 정상 설치된
  Oracle Client 19c(`CLIENT`/`orainventory`) 골든 이미지를 tar로 복제해 설치하는
  방식. `os-setup`, `os-setup-main` 양쪽에 동일하게 반영
  (커밋 `5c35421`)
- 이후 다운로드 방식을 전면 재작성: 기존엔 tar 하나에 다 합쳐서 받았는데,
  아래처럼 major 버전별 + 구성요소별로 분리
  - `CLIENT_8.tar` / `orainventory_8.tar` (RHEL8)
  - `CLIENT_9.tar` / `orainventory_9.tar` (RHEL9)
  - `CLIENT_10.tar` / `orainventory_10.tar` (RHEL10)
  - `bash_profile_8` / `bash_profile_9` / `bash_profile_10` (환경변수 파일, OS
    버전별 동일 내용이지만 파일 자체는 별도 다운로드)
  - 다운로드 위치: `${BASE_URL}/files/linux/oracle_client_tar/`
  - **`.bash_profile` 실 파일은 저장소에 커밋하지 않고**, 대화창에서 직접
    다운로드 받을 수 있게 전달함(민감정보는 아니지만 사용자 요청에 따름)
  - `extract_component_tar()` 헬퍼로 tar 최상위 디렉터리 유무를 자동 판별해
    압축 해제
  - 커밋 `5416a01`
- 이후 "복제 방식도 OS 필수 패키지 설치가 필요한가?"라는 질문에 대해:
  복사해온 바이너리도 여전히 OS가 제공하는 공유 라이브러리(libaio, libnsl
  등)에 동적 링크돼 있고, `attachHome` 단계에서 실제로 `runInstaller`(OUI,
  Java 기반)를 실행하기 때문에 **`install_oracle.sh`와 동일한 필수 패키지
  (`RLn_ORA_PKG`, 목록에서 아무것도 빼지 않고 그대로)가 필요하다**고 결론.
  `install_oracle2.sh`에도 동일한 dnf install + rpm 검증 단계(최대 3회
  재시도) 추가 (커밋 `5cbec22`)

## 7. `os_param_apply.sh` — HISTTIMEFORMAT 적용

- RHEL 서버의 `.bash_history`에 명령 실행 시각이 함께 기록되도록
  `HISTTIMEFORMAT` 환경변수를 설명 후, `os-setup`(os-setup-main 제외, 이번
  요청은 os-setup 한정)의 OS 파라미터 적용 스크립트에 반영
- `/etc/profile.d/histtimeformat.sh` 파일로 전역 적용, 기존
  `backup_if_needed` / `manifest_record` 로직 재사용
- `os_param_verify.sh`에도 동일 항목 검증 로직 추가. `os_param_rollback.sh`는
  파일명 기반 와일드카드 처리라 별도 수정 불필요함을 확인
- 커밋 `7b1bf3b`

## 8. `account_gen.sh` — `osmanaged` 계정 초기 비밀번호 처리

- 요청: `osmanaged` 계정만 `cotsadm1!`로 비밀번호를 하드코딩해달라는 요청
- 저장소 git 이력을 확인한 결과, **동일 계정에 대해 정확히 이 패스워드가
  평문으로 커밋됐다가 보안 사고로 삭제된 이력**(커밋 `ecc0f9a`)을 발견 →
  하드코딩 대신 `HOST_OSMANAGED_PASSWORD` 호스트 전용 env 변수로 처리하고,
  값이 없으면 기존 `HOST_INITIAL_PASSWORD`로 폴백하도록 구현
- `os-setup/linux/config/os_env/example_host.env.template`에 주석 처리된
  플레이스홀더(`HOST_OSMANAGED_PASSWORD="ChangeMe456!"`) 추가, 사고 이력
  커밋 참조 코멘트 포함
- 저장소 루트에 `.gitignore` 신규 생성 — 실제 호스트 env 파일이 커밋되지
  않도록 방지 (`.template` 파일은 그대로 추적됨)
  ```
  os-setup/linux/config/os_env/*.env
  os-setup/windows/config/os_env/*.ps1
  ```
- 커밋 `1d50666`

## 9. VirtualBox 7.1.6 + RHEL10.2 설치 이슈 (정보성, 저장소 미반영)

- 증상 1: `supR3HardNtChildPurify` / `supHardenedWinVerifyProcess` 오류 —
  Windows Hyper-V/Core Isolation(메모리 무결성)이 VirtualBox의 자체
  변조 검사(hardening)와 충돌해서 발생. Hyper-V 관련 기능 끄기로 해결 방향 안내
- 증상 2: 게스트 부팅 시 `Fatal glibc error: CPU does not support
  x86-64-v3` — 실제로는 CPU가 x86-64-v3를 지원하는데도 VirtualBox
  7.1.x~7.2.8/9 대의 VMM이 Hyper-V/NEM 실행 모드에서 CPU 기능을 잘못
  보고하는 회귀 버그. **7.2.10에서 수정됨** → 최신(7.2.18 등)으로 업그레이드
  권장

## 10. RHEL10용 Oracle 19c Client 필수 패키지(`RL10_ORA_PKG`) 추가 및 실측 보정

- `linux_common.env`에 `RL10_ORA_PKG` 배열 최초 추가. Oracle이 19c를
  OL10/RHEL10에 아직 공식 인증하지 않은 상태라는 점을 주석으로 명시하고,
  oracle-base.com의 OL10 설치 가이드 필수 패키지 목록이 `RL9_ORA_PKG`와
  패키지명이 완전히 같아 그대로 가져와 시작함 (커밋 `ae4a9cb`)
- `install_oracle.sh`의 OS 감지 case문에 `10)` 분기 추가
  (`OEL_VALUE="OEL10"`, "미검증" 주석 포함)
- 이후 실제 RHEL10 테스트 서버에서 `dnf install`로 검증한 결과,
  **`compat-openssl11`만 "일치하는 인수가 없습니다"로 설치 실패** 확인.
  Red Hat 공식 문서(RHEL 10 adoption 가이드, Security 챕터)에 "OpenSSL
  1.1이 단종되어 RHEL10에서 `compat-openssl11` 패키지 자체를 제거했다"고
  명시돼 있고, 패키지 출처인 oracle-base.com 가이드 자체도 이 항목을
  "설치 안 돼도 무방"으로 취급하고 있어 `RL10_ORA_PKG`에서 제외.
  나머지 패키지는 전부 실제 설치 확인됨 (2026-09-21) (커밋 `35d41e0`)

## 11. RHEL9/RHEL10 Oracle 19c Client 설치 트러블슈팅 (실제 설치 중 순차 발견)

수동/자동 설치 도중 연쇄적으로 나타난 문제를 원인 순서대로 정리:

1. **`libnsl.so.1: cannot open shared object file`** — RHEL8부터 glibc가
   제공하던 옛 NIS 라이브러리가 분리되면서, 최신 `libnsl` 패키지는
   `libnsl.so.2`(새 ABI)만 제공. `libnsl` 패키지 설치로 해결(이미
   `RLn_ORA_PKG`에 포함돼 있었음 — 원인은 수동 설치 절차에서 패키지 설치
   단계 자체를 건너뛴 것)
2. **`libcrypt.so.1: cannot open shared object file`** — RHEL9부터
   `libxcrypt-compat`가 기본 미설치로 분리됨. 마찬가지로 `RL9/10_ORA_PKG`에
   이미 포함된 패키지라 전체 목록을 한 번에 설치하면 예방됨
3. **`[FATAL] make ... 'client_sharedlib' 대상을 호출하는 중 오류`** —
   glibc 2.34+(RHEL9/10)에서 정적 아카이브 `/usr/lib64/libpthread_nonshared.a`
   자체가 제거됨(pthread 함수가 libc.so에 직접 흡수됨). relink가 이 파일의
   "존재 여부"만 확인하고 실제 심볼은 이미 libc에 있어 안 쓰기 때문에, 빈
   더미 아카이브만 만들어도 relink가 끝까지 성공함:
   ```bash
   ar cr /usr/lib64/libpthread_nonshared.a
   ```
   RHEL10, RHEL9.2 실제 테스트로 확인. `install_oracle.sh`의 패키지 설치
   검증 직후 · `runInstaller` 실행 전 단계로 자동화 반영(파일이 이미 있는
   RHEL8 등은 손대지 않음). `install_oracle2.sh`는 `attachHome`만 수행하고
   실제 relink를 타지 않는 구조라 이번 변경 대상에서 제외 (커밋 `2d48fe4`)
4. **relink FATAL의 2차 피해 — `tnsping` 등 유틸리티가 0바이트로 남음** —
   원본 zip 안에서도 `tnsping`은 0바이트(정상, 설치 시점에 make로 실제
   링크되는 스텁). `client_sharedlib`(`ins_rdbms.mk`) 단계가 FATAL로
   죽으면 OUI가 그 뒤에 예정된 make 호출(`ins_net_client.mk` 등)을 아예
   실행하지 않아 tnsping도 비어있는 채로 남음 — zip 손상이 아니라 **설치가
   중간에 끊겨서** 생기는 현상임을 확인
5. **잘못된 복구 시도 — `relink all`** — DB 전용 명령이라 클라이언트
   설치엔 없는 `rdbms/lib/libknlopt.a`, `inventory/make/makeorder.xml`을
   찾다가 실패함. **클라이언트 전용 설치엔 `$ORACLE_HOME/bin/relink
   as_installed`가 정답** — 실제 설치된 컴포넌트만 기준으로 relink
   대상을 판단해서 DB 전용 산출물을 건드리지 않음
   ```bash
   cd $ORACLE_HOME/bin
   ./relink as_installed
   ```

## 12. Oracle 19c Client 수동(비-스크립트) 설치 절차 정리 (채팅 전달, 저장소 미반영)

"설치스크립트 없이 zip 풀고 수동 설치하는 명령"을 요청받아 `install_oracle.sh`
의 실제 로직을 그대로 따라가며 수동 명령 순서로 재정리(디렉터리 준비 →
zip 다운로드/압축 해제 → `libclntshcore.so.19.1` 사전 백업 → `runInstaller`
→ relink 복구 → `orainstRoot.sh` → `ldconfig` 등록 → `sqlplus -v` 검증).

- 이 과정에서 사용자가 그대로 사용하던 `-ignoreSysPrereqs` 플래그가
  `os-setup`의 `install_oracle.sh`엔 아직 남아있던 옛날 값임을 재확인(이미
  `os-setup-main`은 커밋 `9593861`로 `-ignorePrereqFailure`로 수정된
  상태) — 수동 명령에는 올바른 `-ignorePrereqFailure`를 안내
- 위 11번 항목의 문제들을 이 수동 절차를 실제로 따라 하던 도중 순서대로
  발견함(즉, 수동 절차 1차 버전에서 패키지 설치 단계를 빠뜨렸던 게 이후
  문제들의 시발점)

## 13. RHEL8.6 — Oracle 19c Client → 11g 전환 검토 (신규 VM, 앱 호환 문제)

- 신규 RHEL8.6 VM에 19c Client를 설치했으나 **앱에서 사용 불가**(앱이
  `libclntsh.so.11.1` 등 11g 계열 SONAME을 요구하는 것으로 추정) → 11g 설치
  요청
- **Oracle은 11g(11.2.0.4)를 RHEL8에 공식 인증하지 않음**을 확인. 19c
  설치 때는 없던 새로운 걸림돌: `compat-libstdc++-33`, `compat-libcap1`
  같은 패키지가 RHEL8/9 저장소에 **아예 존재하지 않음**(Red Hat 공식 확인)
  → CentOS7 vault(`vault.centos.org`)에서 rpm을 직접 받아 강제 설치해야 함
- 19c 대비 **다운그레이드가 필요한 항목**: RHEL8 기본(최신) `libaio`를
  EL7 빌드(`libaio-0.3.109-13.el7.*.rpm`)로 교체하는 게 커뮤니티에서 널리
  쓰이는 패턴(단, 버전 번호 자체는 el7/el8이 거의 동일해 실제 필요 여부는
  케이스에 따라 다를 수 있음 — prereq 에러에 libaio가 안 걸리면 생략 가능)
- Full Client(OUI) 설치 시 순서: 19c `deinstall` → 잔여물 정리
  (`oraInventory`까지 삭제 후 새로 시작 권장) → 패키지 재구성(RHEL8 기본
  패키지 + libaio 다운그레이드 + compat 패키지 CentOS7 vault 수동 설치 +
  `libnsl.so` 심볼릭 링크) → oracle 계정 환경변수 재설정 → `runInstaller
  -ignoreSysPrereqs`(11g는 구버전 플래그가 맞음, 19c와 반대) → `root.sh`/
  `orainstRoot.sh` → `ldconfig` 등록 → 검증
- **대안으로 Oracle Instant Client 11.2.0.4 Basic 검토** — OUI 없이 zip만
  풀면 되는 방식이라 위 RHEL8 미인증 문제 대부분을 회피 가능. 실제 준비된
  `instantclient-basic-linux-11.2.0.4.0.zip`(58,793,148바이트) 파일을
  `unzip -l` 결과로 무결성 검증:
  - 정상적인 11.2.0.4 Basic 패키지는 12개 파일 구성이 맞음(19c와 달리
    `libclntshcore.so`가 없는 단일 `libclntsh.so.11.1` 구조)
  - 앱이 필요로 하는 `libclntsh.so.11.1`(44,316,855바이트) 포함 확인 →
    파일 정상
  - Instant Client 설치 절차(zip 풀기 → `libclntsh.so`/`libocci.so`
    심볼릭 링크 생성 → `/etc/ld.so.conf.d/` 등록 + `ldconfig` →
    `LD_LIBRARY_PATH` 설정) 정리해 전달. `network/admin/tnsnames.ora`는
    zip에 없어 직접 생성 필요, sqlplus 필요 시 별도
    `instantclient-sqlplus` 패키지 요구됨을 안내
- 이 항목은 아직 결론(Full Client vs Instant Client 중 최종 선택) 및
  저장소 반영 여부가 확정되지 않은 **논의 중 상태**

## 14. 기타

- GitHub PAT을 이용해 여러 세션에 걸쳐 `HuntKim/DL_Boss` 저장소에 대한
  clone/commit/push 작업을 진행함 (토큰 값 자체는 본 문서에 기록하지 않음)
- 사용자가 `install_oracle2.sh`의 경로 하드코딩(`/oracle/CLIENT` 등)을
  `TARGET_ORACLE_BASE` 등 호스트 env로 오버라이드 가능한 변수 기반으로
  직접 리팩터링(커밋 `26d36d0`) — Claude 세션 밖에서 사용자가 직접 진행한
  작업이라 상세 diff는 이 문서에서 별도로 재정리하지 않음
