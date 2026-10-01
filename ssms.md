# SSMS 22 설치 오류 — 패키지 서명/무결성 확인 불가

> Windows Server 2022에 SSMS(SQL Server Management Studio) 22 설치 중 발생한
> 오류와 조치 방법 정리.

## 1. 증상

- 환경: Windows Server 2022, SSMS 22 설치
- 설치 중 아래 메시지와 함께 설치가 종료됨:
  ```
  설치 파일의 무결성을 확인할 수 없습니다.
  패키지 서명을 확인할 수 없습니다.
  ```
- 상세 로그 위치: `%TEMP%\dd_bootstrapper_yyyyMMddHHmmss.log` — 보통 아래와
  같은 서명 검증 실패 로그가 함께 남음
  ```
  Certificate is invalid: <SSMS폴더>\vs_installer.opc
  Error 0x80131509: Signature verification failed
  ```

## 2. 원인

**인증서 체인 검증 실패**가 원인. Windows는 설치 파일 서명을 검증할 때,
로컬에 캐시되지 않은 루트/중간 인증서가 있으면 Windows Update 경로로
자동으로 내려받아 보완하는데, 대상 서버가 인터넷에 접근 못 하거나(폐쇄망),
방화벽으로 해당 경로가 막혀 있으면 이 보완 자체가 실패해서 "서명을 확인할
수 없음"으로 뜬다.

- SSMS 22부터는 서명에 **`Microsoft Windows Code Signing PCA 2024`**라는
  비교적 최근 인증서가 쓰이는데, 기존 Windows Server 2022 이미지엔 이게
  기본으로 캐시돼 있지 않은 경우가 많아 **이 버전에서 특히 자주 보고됨**
  (Microsoft Q&A에서도 이 인증서 누락이 SSMS v22 오프라인 설치 무응답/실패의
  대표 원인으로 확인됨)
- 그 외에 서버 시스템 시간이 틀어져 있어도 인증서 유효기간 검증 자체가
  실패해 동일한 증상이 날 수 있음

## 3. 조치 명령

### 3-1. 핵심 인증서 설치 (가장 먼저 시도)

인터넷 되는 PC에서 아래 인증서를 받아 대상 서버로 복사:
```
https://www.microsoft.com/pkiops/certs/Microsoft%20Windows%20Code%20Signing%20PCA%202024.crt
```

⚠️ **이 인증서는 루트(Root)가 아니라 "중간 인증 기관(Intermediate
Certification Authorities)" 저장소에 들어가야 함.** 이름의 "PCA"(Policy
Certification Authority)는 MS PKI 체계에서 통상 중간 발급 CA를 가리킴.
`"Root"`에 넣으면 설치는 "성공"했다고 뜨지만 체인 검증 시 여전히
"중간 인증서가 설치되지 않음"으로 실패한다.

대상 서버에서 **관리자 권한 명령 프롬프트**로:
```cmd
certutil.exe -addstore -f "CA" "C:\경로\Microsoft Windows Code Signing PCA 2024.crt"
```
(`"Root"`가 아니라 **`"CA"`** — 중간 인증 기관 저장소를 가리키는
certutil 키워드)

GUI로 하는 경우: 받은 `.crt` 파일 우클릭 → **인증서 설치** → 저장소 위치
**로컬 컴퓨터** → "인증서 종류에 따라 자동으로 저장소 선택" 유지 → 마침
(이 옵션을 그대로 두면 Windows가 알아서 중간 인증 기관 저장소로 넣어줌 —
저장소를 수동으로 "신뢰할 수 있는 루트 인증 기관"으로 지정하지 말 것)

**이미 `"Root"`에 잘못 넣었다면** 삭제 후 다시 `"CA"`로 추가:
```cmd
certutil.exe -delstore "Root" "Microsoft Windows Code Signing PCA 2024"
certutil.exe -addstore -f "CA" "C:\경로\Microsoft Windows Code Signing PCA 2024.crt"
```

### 3-2. 오프라인(Layout) 설치본을 쓰는 경우 — 나머지 인증서 3개 추가

SSMS 공식 다운로드 페이지의 "오프라인 설치(Layout)" 옵션으로 받으면
`Certificates` 폴더가 함께 포함되는데, 그 안의 아래 3개도 같이 설치:

```cmd
certutil.exe -addstore -f "Root" "[Layout경로]\certificates\manifestRootCertificate.cer"
certutil.exe -addstore -f "Root" "[Layout경로]\certificates\manifestCounterSignRootCertificate.cer"
certutil.exe -addstore -f "Root" "[Layout경로]\certificates\vs_installer_opc.RootCertificate.cer"
```

(`certmgr.exe`로 해도 동일)
```cmd
certmgr.exe -add "[Layout경로]\certificates\manifestRootCertificate.cer" -n "Microsoft Root Certificate Authority 2011" -s -r LocalMachine root
certmgr.exe -add "[Layout경로]\certificates\manifestCounterSignRootCertificate.cer" -n "Microsoft Root Certificate Authority 2010" -s -r LocalMachine root
certmgr.exe -add "[Layout경로]\certificates\vs_installer_opc.RootCertificate.cer" -n "Microsoft Root Certificate Authority 2010" -s -r LocalMachine root
```

### 3-3. 설치 시 인터넷 접근 자체를 시도하지 않도록 플래그 지정

```cmd
vs_SSMS.exe -noWeb
```

폐쇄망 서버라면 단일 설치파일보다 **오프라인 Layout으로 먼저 전체를
받아서** 위 인증서들과 함께 반입하는 방식을 권장.

### 3-4. 인증서 설치 확인

```
mmc.exe
→ 파일 → 스냅인 추가/제거 → 인증서 → 컴퓨터 계정 → 로컬 컴퓨터 → 마침
→ 인증서(로컬 컴퓨터) → 신뢰할 수 있는 루트 인증 기관 → 인증서
→ 위에서 추가한 인증서들이 "발급 대상"에 보이는지 확인
→ (필요시) 중간 인증 기관 폴더도 함께 확인
```

### 3-5. 그 외 확인 사항

- **서버 시간/시간대가 정확한지** 확인 — 틀어져 있으면 인증서 자체는
  정상이어도 유효기간 검증에서 같은 에러가 남
  ```cmd
  w32tm /query /status
  ```
- 완전 폐쇄망이 아니라 방화벽으로 일부만 막힌 경우, 아래 아웃바운드만
  열어줘도 Windows가 자동으로 루트 인증서를 갱신하면서 해결되는 경우가 있음
  - `www.microsoft.com`
  - `ctldl.windowsupdate.com`
  - `crl.microsoft.com`

## 4. 참고

- [Microsoft 공식 문서 — Install certificates for SSMS](https://learn.microsoft.com/en-us/ssms/install/install-certificates)
- [mssqltips — SSMS Offline Installer: Complete Installation Guide](https://www.mssqltips.com/sqlservertip/11598/ssms-22-offline-installation/)
- [Microsoft Q&A — Failed Silently when SSMS v22 layout offline installation](https://learn.microsoft.com/en-us/answers/questions/5787424/failed-silently-when-ssms-v22-layout-offline-insta)



windows2019 - ssms 22 설치 이슈 

1. 설치 시 아래와 같은 이슈 발생 
[14d8:0005][2026-10-01T20:14:40] NoWeb or OfflineFilePath specified, skipping latest installer feed check.
[14d8:0005][2026-10-01T20:14:40] Existing client is unsupported: C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe does not exist.
[14d8:0005][2026-10-01T20:14:40] Using Offline package: C:\os-setup\temp\SSMS_Offline_4_22\SSMS_Offline\vs_installer.opc
[14d8:0005][2026-10-01T20:14:40] Saving Certificates to layout folder
[14d8:0005][2026-10-01T20:15:25] Certificate is invalid: C:\os-setup\temp\SSMS_Offline_4_22\SSMS_Offline\vs_installer.opc
[14d8:0005][2026-10-01T20:15:25] Error: Unable to verify the certificate: InvalidCertificate
[14d8:0005][2026-10-01T20:15:25] Error 0x80131509: Signature verification failed. Error: Unable to verify the integrity of the installation files: the certificate could not be verified.
   위치: Microsoft.VisualStudio.Setup.OpcVerifier.Verify(Stream packageStream, String layoutLocation, Boolean skipSavingCertificate)
   위치: Microsoft.VisualStudio.Setup.Bootstrapper.Bootstrapper.VerifyLayoutPackage(Stream packageStream)
[14d8:0005][2026-10-01T20:15:26] 설치 파일의 무결성을 확인할 수 없습니다. 패키지 서명을 확인할 수 없습니다.
[14d8:0005][2026-10-01T20:15:26] Bootstrapper failed with known error.


2. 원인 분석
폐쇄망 환경으로 인해 설치 프로그램이 MS 인증서의 유효성을 확인하기 위한 CRL(인증서 폐기 목록) 서버에 접속하지 못해 발생하는 보안 검증 오류로 판단.

3. 조치 내역 (모두 수행했으나 동일 증상 발생)
1) .NET Framework 4.8 업데이트 완료 (버전 요구사항 충족)
2) MS 루트 및 중간 인증서 수동 등록 완료 (신뢰 체인 구축)
3) 인터넷 옵션 → 서버/게시자 인증서 해지 확인(CRL) 설정 해제 완료
