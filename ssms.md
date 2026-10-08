# Windows Server 2022 - SSMS 22 설치 오류 

> Windows Server 2022에 SSMS(SQL Server Management Studio) 22 설치 중 발생한 오류

## 1. 증상(로그)

1. dd_bootstrapper_20261008103901

[2b84:0001][2026-10-08T10:39:01] Assembly version: 4.8.60.55523.

[2b84:0001][2026-10-08T10:39:01] Creating new ExperimentationService

[2b84:0001][2026-10-08T10:39:01] Telemetry property VS.ABExp.Flights : 

[2b84:0001][2026-10-08T10:39:01] Command line arguments = --noWeb,--quiet,--norestart,--wait,--env,_SFX_CAB_EXE_PACKAGE:C:\os-setup\temp\SSMS_22\SSMS_22\vs_SSMS.exe _SFX_CAB_EXE_ORIGINALWORKINGDIR:C:\os-setup\windows\sw_modules

[2b84:0001][2026-10-08T10:39:01] C2R signature did not exist or could not be read: 

[2b84:0001][2026-10-08T10:39:01] Parent process name = vs_SSMS

[2b84:0001][2026-10-08T10:39:01] Parent process product version = 18.8.12023.21

[2b84:0001][2026-10-08T10:39:01] CampaignId = 

[2b84:0001][2026-10-08T10:39:01] Warning: ResponseId not available in 'vs_setup_bootstrapper.config'. Trying to parse filename.

[2b84:0001][2026-10-08T10:39:01] Warning: loading config settings: -update --update --layout -offline --offline --locale --layout --originalworkingdir --installLayoutPath --env

[2b84:0001][2026-10-08T10:39:01] Trying to get response file path from layout.

[2b84:0001][2026-10-08T10:39:01] Returning response file path as: C:\os-setup\temp\SSMS_22\SSMS_22\Response.json.

[2b84:0001][2026-10-08T10:39:01] DownloadURL = https://aka.ms/ssms/22/release/installer

[2b84:0001][2026-10-08T10:39:01] InstallLocation = C:\Program Files (x86)\Microsoft Visual Studio\Installer

[2b84:0001][2026-10-08T10:39:01] OfflineFilePath = C:\os-setup\temp\SSMS_22\SSMS_22\vs_installer.opc

[2b84:0001][2026-10-08T10:39:01] LayoutLocation = 

[2b84:0001][2026-10-08T10:39:01] ExecutableArguments = /finalizeInstall install --layoutPath "C:\os-setup\temp\SSMS_22\SSMS_22" --in "C:\os-setup\temp\SSMS_22\SSMS_22\Response.json" --noWeb --quiet --norestart --locale ko-KR --activityId "b54fbd65-0fd3-4a2e-9011-ebb9877cfbfd"

[2b84:0001][2026-10-08T10:39:01] OSVersion = Microsoft Windows NT 10.0.20348.0

[2b84:0001][2026-10-08T10:39:01] Starting to detect the existing VS and .NET...

[2b84:0001][2026-10-08T10:39:01] Finished detecting the existing VS and .Net

[2b84:0009][2026-10-08T10:39:01] NoWeb or OfflineFilePath specified, skipping latest installer feed check.

[2b84:0009][2026-10-08T10:39:01] Existing client is unsupported: C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe does not exist.

[2b84:0009][2026-10-08T10:39:01] Using Offline package: C:\os-setup\temp\SSMS_22\SSMS_22\vs_installer.opc

[2b84:0009][2026-10-08T10:39:01] Saving Certificates to layout folder

[2b84:0009][2026-10-08T10:39:46] Certificate is invalid: C:\os-setup\temp\SSMS_22\SSMS_22\vs_installer.opc

[2b84:0009][2026-10-08T10:39:46] Error: Unable to verify the certificate: InvalidCertificate

[2b84:0009][2026-10-08T10:39:46] Error 0x80131509: Signature verification failed. Error: Unable to verify the integrity of the installation files: the certificate could not be verified.

   위치: Microsoft.VisualStudio.Setup.OpcVerifier.Verify(Stream packageStream, String layoutLocation, Boolean skipSavingCertificate)

   위치: Microsoft.VisualStudio.Setup.Bootstrapper.Bootstrapper.VerifyLayoutPackage(Stream packageStream)

[2b84:0009][2026-10-08T10:39:46] 설치 파일의 무결성을 확인할 수 없습니다. 패키지 서명을 확인할 수 없습니다.

[2b84:0009][2026-10-08T10:39:46] Bootstrapper failed with known error.

2. dd_vs_SSMS_decompression_log

[10/8/2026, 10:39:0] === Logging started: 2026/10/08 10:39:00 ===

[10/8/2026, 10:39:0] Executable: C:\os-setup\temp\SSMS_22\SSMS_22\vs_SSMS.exe v18.8.12023.21

[10/8/2026, 10:39:0] --- logging level: standard ---

[10/8/2026, 10:39:0] Directory 'C:\Users\os_admin\AppData\Local\Temp\7\4d8dbb6dd534d20b4ef51d6a133d\' has been selected for file extraction

[10/8/2026, 10:39:0] Extracting files to: C:\Users\os_admin\AppData\Local\Temp\7\4d8dbb6dd534d20b4ef51d6a133d\

[10/8/2026, 10:39:0] Extraction took 453 milliseconds

[10/8/2026, 10:39:0] Executing extracted package: 'vs_bootstrapper_d15\vs_setup_bootstrapper.exe ' with commandline ' --noWeb --quiet --norestart --wait  --env "_SFX_CAB_EXE_PACKAGE:C:\os-setup\temp\SSMS_22\SSMS_22\vs_SSMS.exe _SFX_CAB_EXE_ORIGINALWORKINGDIR:C:\os-setup\windows\sw_modules"'

[10/8/2026, 10:39:46] The entire Box execution exiting with result code: 0x0

[10/8/2026, 10:39:46] Launched extracted application exiting with result code: 0x138b

[10/8/2026, 10:39:46] === Logging stopped: 2026/10/08 10:39:46 ===ac

## 2. 원인

로그 상 실패 지점은 `Microsoft.VisualStudio.Setup.OpcVerifier.Verify` →
`VerifyLayoutPackage`에서 `vs_installer.opc`의 전자서명을 검증하다가
`InvalidCertificate`로 끝나는 부분이다. 겉보기엔 "인증서를 못 믿어서"
실패하는 것처럼 보이지만, 로그의 **시간 간격**이 진짜 원인을 가리킨다.

- 이번 2022 서버: `Saving Certificates to layout folder` (10:39:01) →
  `Certificate is invalid` (10:39:46) — **정확히 45초**
- 과거 2019 서버(아래 적어두신 사례): `Saving Certificates to layout
  folder` (20:14:40) → `Certificate is invalid` (20:15:25) — **역시 45초**

OS 버전이 다른 두 서버에서 똑같이 45초가 걸렸다는 건, 이 구간에서 뭔가를
"계산"하다 실패한 게 아니라 **네트워크 요청을 보내고 타임아웃이 찰 때까지
기다리다 실패**했다는 뜻이다.

이 네트워크 요청은 로컬에 인증서가 있는지와 무관하게, Windows의 인증서
체인 검증 엔진(CAPI2/CryptoAPI, OpcVerifier는 이를 .NET `X509Chain`으로
호출)이 체인에 포함된 인증서들의 **폐기 여부(Revocation)를 CRL/OCSP
서버에 "온라인으로" 재확인**하려고 시도하는 단계에서 발생한다. Root/중간
인증서를 로컬에 다 등록해 둬도, 이 폐기 확인 자체는 검증할 때마다 매번
네트워크로 나가려고 시도한다. 폐쇄망이라 이 요청이 응답 없이 막혀 있으면
(명시적으로 거부되는 게 아니라 조용히 드롭되는 구성이 흔함), 인증서 1개당
기본 15초·누적 최대 20초 같은 기본 타임아웃을 다 채우고서야 "폐기 여부를
확인할 수 없음" 상태로 넘어가고, OpcVerifier는 이 상태를 그냥
`InvalidCertificate`로 처리해버린다.

**[2026-10-08 업데이트] 3-1 레지스트리 적용 후에도 동일 — 원인 재정정**

3-1(타임아웃 단축)을 적용한 뒤 재시도한 결과: **45초 대기는 사라졌지만
"무결성/서명 확인 불가" 오류는 그대로 재현됨.** 이건 매우 중요한 신호다
— 느려서 실패한 게 아니라, **애초에 오프라인 상태로는 통과할 수 없는
검증을 하고 있다는 뜻**이다. 타임아웃을 줄이면 "더 빨리 포기하고
실패"할 뿐, 결과(실패) 자체는 바뀌지 않는다 — 지금 재현된 현상이 바로
그 증거다.

실제로 이건 Microsoft 쪽에서도 공식적으로 인정한 문제다. **2025년 6월
말 이후 새로 생성된 VS/SSMS 오프라인 Layout부터 패키지(.opc) 서명에 대한
폐기(Revocation) 확인이 필수로 바뀌었고, 오프라인 머신은 이 확인을 할
방법이 없어 설치가 거부**된다 (Microsoft Q&A에서 MS 직원이 직접 확인한
내용). 레이아웃을 만든(=인터넷 되는) 머신에서는 통과하지만, 그 레이아웃을
폐쇄망으로 그대로 옮겨서 설치하면 항상 이 오류가 재현된다. 추후
부트스트래퍼 3.15에 `--ignore-revocation` 플래그를 추가하겠다는 공지가
있었지만, 2025-11 기준 사용자 보고로는 아직 실제 배포되지 않은 것으로
확인됨 — 즉 **현재 시점에 Microsoft가 공식 지원하는 깔끔한 한 줄짜리
해결책은 없다.**

**이미 시도하신 "인터넷 옵션 → 서버/게시자 인증서 해지 확인(CRL) 해제"가
효과가 없었던 이유**도 여기서 설명된다: 그 옵션은 Internet
Explorer/WinINet 계층 및 구형 `WinVerifyTrust` 기반 서명 검사에 적용되는
설정이고, VS/SSMS 설치 부트스트래퍼의 OpcVerifier는 이와 별개인 .NET
`X509Chain`/CAPI2 엔진을 직접 호출하기 때문에 그 설정의 영향을 받지
않는다. 즉 인증서를 전부 올바르게(Root/CA 저장소 구분까지 맞춰서)
설치하고 CRL 체크도 껐는데도 동일하게 실패하는 것은 이 설정이 애초에
해당 검증 경로를 건드리지 못했기 때문이다.

## 3. 조치 명령

### 3-0. 사전 전제 (이미 완료됨 — 유지)

- `Microsoft Windows Code Signing PCA 2024` → **CA(중간 인증 기관)** 저장소
- Layout `certificates` 폴더의 루트 인증서 3종 → **Root** 저장소
- .NET Framework 4.8

위 3가지는 "인증서가 로컬에 존재"해야 하는 필수 전제이지만, 2번에서 설명한
네트워크 타임아웃 문제를 해결해주지는 않는다. 아래 3-1/3-2가 실제 증상을
없애는 조치다.

### 3-1. (핵심/신규) 인증서 폐기 확인(CRL/OCSP)의 네트워크 조회 타임아웃을 최소화

관리자 권한 명령 프롬프트에서:
```cmd
reg add "HKLM\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CertDllCreateCertificateChainEngine\Config" /v ChainUrlRetrievalTimeoutMilliseconds /t REG_DWORD /d 200 /f
reg add "HKLM\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CertDllCreateCertificateChainEngine\Config" /v ChainRevAccumulativeUrlRetrievalTimeoutMilliseconds /t REG_DWORD /d 500 /f
```
- `ChainUrlRetrievalTimeoutMilliseconds`: CRL/OCSP URL 1건당 타임아웃
  (기본값 없으면 15초) → 200ms로 단축
- `ChainRevAccumulativeUrlRetrievalTimeoutMilliseconds`: 체인 전체 누적
  타임아웃 (기본값 없으면 20초) → 500ms로 단축
- 재부팅 불필요, 적용 즉시 다음 인증서 검증부터 반영됨

이렇게 하면 폐쇄망에서 어차피 실패할 네트워크 조회를 0.2~0.5초 안에
포기하고 넘어가므로, 45초씩 걸리던 지연과 그로 인한 `InvalidCertificate`
판정이 사라질 가능성이 높다.

### 3-2. (보조) 자동 루트 인증서 업데이트 기능 자체를 비활성화

애초에 네트워크로 나가려는 시도 자체를 줄이는 보조 조치. 둘 중 하나:

- **GPO (도메인 환경)**: 컴퓨터 구성 → 관리 템플릿 → 시스템 →
  인터넷 통신 관리 → 인터넷 통신 설정 → **"자동 루트 인증서 업데이트
  끄기"** → 사용
- **로컬 레지스트리로 직접**:
  ```cmd
  reg add "HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot" /v DisableRootAutoUpdate /t REG_DWORD /d 1 /f
  ```

### 3-3. 적용 후 빠르게 검증 (SSMS 재설치 전에 확인 가능)

```cmd
certutil -verify -urlfetch "C:\Windows\System32\notepad.exe"
```
- 3-1/3-2 적용 **전**에는 이 명령도 네트워크 조회를 시도하며 수 초~수십
  초가 걸림
- 적용 **후**에는 즉시 끝나야 함 — 이걸 확인한 다음 SSMS 설치를 재시도

### 3-4. 그래도 재현되면

- `%TEMP%\dd_bootstrapper_*.log`에서 `Saving Certificates`와
  `Certificate is invalid` 사이 시간 간격이 여전히 45초 전후인지 확인 —
  그대로면 3-1 레지스트리 값이 실제로 적용됐는지(`reg query`로 재확인),
  또는 다른 보안 소프트웨어(백신/EDR)가 자체적으로 같은 URL에
  재접속을 시도하고 있는지 점검
- 완전히 막힌 폐쇄망이 아니라 특정 구간만 막혀 있다면, 아래 아웃바운드를
  열어주는 쪽이 근본적으로 더 깔끔할 수 있음 (3-1/3-2는 "막혀 있어도
  빨리 포기하게" 하는 조치이지 "막힌 걸 뚫는" 조치는 아님)
  - `ctldl.windowsupdate.com`, `crl.microsoft.com`, `ocsp.msocsp.com`

### 3-5. [신규] 3-1/3-2로도 해결 안 될 때 — 현실적인 선택지

2번 "원인" 업데이트대로, 이건 타임아웃 튜닝으로 해결되는 문제가 아니라
**완전 폐쇄망에서는 SSMS 22의 오프라인 Layout 자체가 구조적으로 설치가
안 되는 Microsoft 쪽 변경사항**이다. 아래 중 하나를 선택해야 한다.

**(a) SSMS 버전을 20/19로 다운그레이드 (가장 현실적/권장)**

SSMS 22부터 VS 통합 번호체계로 바뀌면서 이 강화된 폐기 확인 로직이 같이
들어간 것으로 보임. SSMS 20/19는 2025년 6월 변경 이전 부트스트래퍼를
쓰므로 이 문제 자체가 없음. v22의 신규 기능이 꼭 필요한 게 아니라면,
이 프로젝트에서 Oracle 19c→11g 때와 같은 논리로(폐쇄망 호환성을 위해
구버전으로) **SSMS 20 오프라인 설치본으로 교체**하는 것을 1순위로 권장.

**(b) 로컬 CRL 미러 구성 (구조적으로 가장 깔끔하지만 운영 부담 있음)**

"폐기 확인을 끄는" 게 아니라 "폐기 확인이 실제로 성공하도록" 만드는
방법. 인터넷 되는 PC에서 인증서가 실제로 참조하는 CRL 배포 지점(CDP)
URL을 확인:
```cmd
certutil -dump "Microsoft Windows Code Signing PCA 2024.crt"
```
(출력 중 "CRL Distribution Point" 항목의 URL 확인)

그 URL에서 실제 `.crl` 파일을 받아 폐쇄망 내부의 웹서버에 올려두고,
대상 서버의 `hosts` 파일(또는 내부 DNS)에서 해당 도메인
(`crl.microsoft.com`, `www.microsoft.com` 등)을 그 내부 웹서버로
리다이렉트. CRL은 보통 1~4주 주기로 만료되므로, 주기적으로 인터넷
PC에서 다시 받아 갱신해야 함(수동/스크립트).

**(c) 설치 시점에만 한시적으로 아웃바운드 예외 허용**

정책상 가능하다면, SSMS 설치 1회만 `crl.microsoft.com`,
`www.microsoft.com`, `ocsp.msocsp.com`, `ctldl.windowsupdate.com`로의
아웃바운드를 임시로 열어주고(방화벽/프록시 예외) 설치 완료 후 다시
차단. 가장 적은 작업량으로 끝나지만 보안팀 승인이 필요.

**(d) 인터넷 되는 머신에서 SSMS를 미리 설치한 VM/이미지를 복제**

SSMS 자체는 설치 후에는 네트워크 체크를 다시 하지 않으므로, 인터넷이
되는 동일 OS 버전 VM에 SSMS 22를 먼저 설치한 뒤 그 VM을 템플릿/이미지로
만들어 폐쇄망에 배포하는 방법도 있음 (단, 이미 운영 중인 서버라면
적용하기 어려움).

## 4. 참고

- [Microsoft 공식 문서 — Install certificates for SSMS](https://learn.microsoft.com/en-us/ssms/install/install-certificates)
- [mssqltips — SSMS Offline Installer: Complete Installation Guide](https://www.mssqltips.com/sqlservertip/11598/ssms-22-offline-installation/)
- [Microsoft Q&A — Failed Silently when SSMS v22 layout offline installation](https://learn.microsoft.com/en-us/answers/questions/5787424/failed-silently-when-ssms-v22-layout-offline-insta)
- [Microsoft Q&A — Which certificate does the VS installer use for verification of vs_installer.opc](https://learn.microsoft.com/en-us/answers/questions/2287345/which-certificate-does-the-vs-installer-use-for-ve)
- [rusanu.com — Fix slow application startup due to code sign validation (ChainUrlRetrievalTimeoutMilliseconds 설명)](https://rusanu.com/2009/07/24/fix-slow-application-startup-due-to-code-sign-validation/)
- [admx.help — Turn off Automatic Root Certificates Update (GPO/레지스트리 경로)](https://admx.help/?Category=Windows_10_2016&Policy=Microsoft.Policies.InternetCommunicationManagement::CertMgr_DisableAutoRootUpdates)
- [Microsoft Q&A — Visual Studio 2019 installer no longer allows offline install, MSFT says a revocation check stops it](https://learn.microsoft.com/en-in/answers/questions/5549685/visual-studios-2019-installer-no-longer-allows-me) — 2025-06 이후 오프라인 Layout에 폐기 확인이 필수로 바뀐 것을 MS가 직접 인정한 스레드. `--ignore-revocation` 플래그(3.15) 예고는 2025-11 기준 미배포.
- [Microsoft Developer Community — Visual Studio offline layout fails vs_installer.opc certificate verification](https://developercommunity.microsoft.com/t/11103126)

