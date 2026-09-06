# ==============================================================================  
# [Host Config] DVPGIWPA01M 환경 설정 파일 
# OS: Windows Server 2022 / 역할: iWP AP 서버  
# ==============================================================================

# ------------------------------------------------------------------------------  
# 1. 소프트웨어별 설치 경로 설정 (Installation Paths)  
# ------------------------------------------------------------------------------  
# [IIS / FTP / .NET Framework]   
# -> Windows OS Feature 기능을 사용하여 설치되므로 별도의 경로 설정이 필요 없습니다.

# [JDK] install_jdk.ps1 참조  
# 설치 대상: oracle_jdk_1.7.0_80_64b  
# 가이드 주신 대로 공통 경로를 유지합니다.  
$global:JAVA_HOME = "C:\Program Files\Java\jdk1.7.0_80"

# [Oracle Client] install_oracle_client.ps1 참조  
# 설치 대상: oracle_client_19.3.0.0  
$global:ORACLE_OWNER = "iwpprod:Administrators"
$global:ORACLE_BASE = "C:\app\oracle"  
$global:ORACLE_HOME = "C:\app\oracle\oracle_client_19.3"
