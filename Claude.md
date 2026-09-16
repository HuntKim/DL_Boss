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
   - `/etc/ld.so.conf.d/oracle-client.conf` + `ldconfig` (root 등 다른 계정
     대응)
   - 대상 서버 전용 `tnsnames.ora`로 교체
4. **참고**: 단순 복사만으로는 Oracle Inventory에 해당 호스트가 등록되지
   않아 이후 OPatch 패치 관리 시 문제될 수 있음 — 필요 시 `attachHome`
   절차 추가 검토
   ```
    su - oracle
    cd /oracle/CLIENT/oracle
    ./runInstaller -silent -attachHome \
    -invPtrLoc /etc/oraInst.loc \
    ORACLE_HOME=/oracle/CLIENT/oracle \
    ORACLE_HOME_NAME=OraCleient19Home1
   ```
   [확인]
   ```
   $ORACLE_HOME/OPatch/opatch lsinventory
   /oracle/oraInventory/ContentsXML/inventory.xml  //ORACLE HOME NAME이 지정되어 있는지 확인
   ```
   위에서 등록한 HOME 경로/이름 확인
   
## 6. 기타

- GitHub PAT을 이용해 이 세션 동안 `HuntKim/DL_Boss` 저장소에 대한
  clone/commit/push 작업을 진행함 (토큰 값 자체는 본 문서에 기록하지 않음)
