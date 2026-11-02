# Claude 작업 대화 요약 (2)

> `Claude.md`에 이어지는 Claude 채팅 작업 기록의 요약본입니다.
> 기간: 2026-09 ~ 2026-11-02 · 첨부/작업 파일과 접속 토큰은 포함하지 않았습니다.

---

## 1. SVN 설치 스크립트 — `os-setup/linux/sw_modules/install_svn.sh`

- 대상: RHEL 8/9(rocky·almalinux·centos 포함), Ubuntu 22.04. Apache Subversion(svn) 최신 패키지.
- `/etc/os-release`로 OS를 판별해 RHEL 계열은 `dnf install -y subversion`, Ubuntu는 `apt-get install -y subversion`을 실행.
- `apt-get update` 실패(외부 저장소 403 등)는 경고로만 처리.
- 이미 설치돼 있으면 건너뜀(멱등), 설치 후 `svn --version --quiet`로 확인.

## 2. OS 모니터링 알림 기준 문서 — `Monitoring/OS-모니터링-알림기준.md`

- `Monitoring/BBT-요건`을 바탕으로 작성.
- 알림 등급별 채널: A/B → 메일+메신저+SMS, C → 메일+메신저, D → 메일(일일 요약).
- 항목: CPU / MEM / DISK / FS / Ping fail / Hang / Kernel 오류 임계치.
- Hang 판단: 커널 메시지 `blocked for more than`, `soft lockup` 등.
- `/var/log` 감시 문구: `Kernel panic - not syncing`, `Oops:`, `soft lockup`, `blocked for more than`, `Out of memory`, `I/O error`, `EXT4-fs error`, `Remounting filesystem read-only` 등.

## 3. Oracle Client 19c 설치 (`install_oracle.sh`)

### 발생한 문제와 조치
| 증상 | 원인 | 조치 |
|---|---|---|
| `[INS-04009] -ignoreSysPrereqs` | 19.3 ClientSetup의 `-silent`는 해당 옵션 미지원 | `-ignorePrereqFailure`로 교체 (push 완료) |
| curl은 되는데 "ZIP not found" | 파일서버 목록이 HTML이 아닌 일반 텍스트라 `href="..."` 정규식 실패 | awk로 파일명 추출하도록 수정안 제시 (미반영) |
| `-invPtrLoc` 사용 시 INS-04009 | 19.3 ClientSetup 미지원 | 옵션 제거, 기본 `/etc/oraInst.loc` 사용 |
| attachHome 시 `INS-08101` | supportedOSCheck 경고 | `CV_ASSUME_DISTID` 지정, `opatch lsinventory`로 등록 확인 |
| 전 서버에서 `tnsping` 등 0바이트 | 파일서버 zip 손상 추정, `unzip` 결과 미검사 | `unzip -t` 검증 필요 (확인 대기) |

### 참고 사항
- RHEL 8은 `CV_ASSUME_DISTID=OEL7.8`.
- Instant Client에는 tnsping이 없음 → `sqlplus -L dummy/dummy@ALIAS`의 ORA 코드로 대체 확인
  (01017=접속 정상, 12154=alias 미해석, 12541=리스너 없음, 12170=타임아웃).
- `clone.pl`은 19c부터 deprecated.

## 4. 복제 방식 설치 — `install_oracle2.sh` (신규)

정상 설치된 서버의 `/oracle` 전체(`CLIENT`, `orainventory`, `.bash_profile`)를 tar로 묶어 새 서버에 배포하는 방식.

- 배포 파일: `${BASE_URL}/files/linux/oracle_client_tar/oracle_8.tar | oracle_9.tar | oracle_10.tar` (RHEL 메이저 버전별)
- 흐름:
  1. root·oracle 사용자 확인, OS 버전 판별 → `CV_ASSUME_DISTID` 매핑
  2. 기존 `/oracle/CLIENT`, `/oracle/orainventory` 제거
  3. tar 다운로드(1MB 미만이면 실패) → `tar tf` 무결성 확인 → 최상위가 `oracle/`이면 `/`, 아니면 `/oracle`에 `tar xpf`
  4. `chown -R oracle:dba /oracle`, `restorecon`
  5. `/etc/oraInst.loc`, `/etc/ld.so.conf.d/oracle-client.conf` 작성 후 `ldconfig`
  6. (선택) 호스트별 `tnsnames.ora` 다운로드
  7. `runInstaller -silent -attachHome ORACLE_HOME=... ORACLE_HOME_NAME=OraClient19Home1`
  8. `opatch lsinventory`, `tnsping`/`sqlplus` 0바이트 여부, `sqlplus -v` 확인
- 상태: 로컬 커밋까지 완료했으나 git proxy 403(세션 승인 저장소 아님)으로 **push 미완료**. 재작업 필요.
- 남은 확인: RHEL 9/10의 `CV_ASSUME_DISTID` 값, `BASE_URL`/`FILE_URL` 경로 일치 여부.

### tar 생성 시 심볼릭 링크
- tar는 기본으로 심볼릭 링크를 링크 그대로 저장. `-h`(`--dereference`)는 쓰지 말 것.
- 생성: `cd / && tar -cpf /tmp/oracle_8.tar oracle`
- 생성 전: `find /oracle -type l | wc -l`, `find /oracle/CLIENT -type f -size 0`(0바이트 파일 점검)
- 생성 후: `tar -tvf oracle_8.tar | grep -c '^l'`로 링크 개수 비교, `bin/tnsping`·`bin/sqlplus` 크기 확인
- `/oracle` 밖을 가리키는 링크는 새 서버에서 깨지므로 확인 필요.

## 5. JDK 6u37 설치 (RHEL)

- `.zip` 안이 `jdk1.6.0_37/` 폴더면 `/usr/local/java`에 unzip 후 `bin`, `jre/bin` 실행권한 보정.
- `.bin`이면 `/usr/local/java`에서 `echo | ./jdk-6u37-linux-x64.bin` (마지막 Enter 프롬프트 넘김).
- `ln -sfn /usr/local/java/jdk1.6.0_37 /usr/local/java/jdk6`. 다른 JDK가 기본이면 `profile.d` 대신 앱별 `JAVA_HOME` 지정.
- 오류 `Unable to load native library: libnsl.so.1` → `dnf install -y libnsl` (폐쇄망은 ISO의 rpm 사용).
  - 설치 후 `jre/lib/rt.jar`가 없으면 압축 해제가 중간에 멈춘 것이므로 폴더 삭제 후 재실행.
  - RHEL 10에서의 제공 여부는 미확인 (`dnf provides '*/libnsl.so.1'`로 확인).
- 주의: JDK 6는 지원 종료, TLS 1.0만 지원 → RHEL 8/9 기본 암호 정책에서 외부 HTTPS 연동 실패 가능.
- 후속: 여러 서버 적용 시 `libnsl` 선행 설치를 포함한 `install_jdk6.sh` 모듈화 예정.

## 6. 기타

- **VirtualBox 기동 실패**(`VBOX_E_FILE_ERROR`, 저장 상태 `.sav` 파일 없음): VM 우클릭 → "저장된 상태 버리기" 또는 `VBoxManage discardstate "<VM명>"`. 안 되면 `.vbox` 백업 후 `stateFile` 속성 삭제.
- **git 연동**: 저장소 읽기는 가능하나, 세션에 저장소가 승인 소스로 등록되지 않으면 push가 403으로 거부됨 → 새 세션에서 저장소를 소스로 선택해 진행.
- **대화 원문 저장 시도**: 원본 기록에 토큰·내부 지시문이 포함돼 자동 안전 필터로 중지됨. 또 대화가 길어 앞부분은 요약본만 남아 있어 본 문서는 요약으로 작성.
