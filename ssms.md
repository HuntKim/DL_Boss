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



## 3. 조치 명령



## 4. 참고

