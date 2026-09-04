# os-setup
- 2026 종량제 내재화 OS Setup 스크립트 저장소

### Target OS
- RHEL 8.6, RHEL 8.10, RHEL 9.2, Windows 2022

### 디렉토리 구조
```
/os-setup/
  ├── scripts/                                    # 스크립트 및 설정 영역
  │   ├── linux/                                  # [Linux 영역]
  │   │   ├── config/                             # 전역 및 호스트별 설정 파일
  │   │   │   ├── Linux_user_gen.csv              # 계정 생성 정보
  │   │   │   ├── Linux_filesystem_gen.csv        # 파일시스템/마운트 정보
  │   │   │   ├── os_param_applly.csv             # OS 파라미터 설정 정보
  │   │   │   ├── sw_mapping_linux.txt            # Linux 서버별 SW 매핑 정보
  │   │   │   ├── linux_common.env                # 전역 기본값 및 공통 로그 함수
  │   │   │   ├── env/                            # [호스트별 개별 환경 설정]
  │   │   │   │   └── host1.env                   # 특정 호스트 전용 설정
  │   │   │   └── tnsnames/                       # [호스트별 oracle client용 tnsnames.ora 설정]
  │   │   │       └── host1.tnsnames.ora          # 특정 호스트 전용 설정
  │   │   ├── init.sh                             # OS Setup 파일 및 구조 자동 배포 스크립트 
  │   │   ├── account/                            # [계정 관리]
  │   │   │   ├── Linux_user_gen.sh               # 계정 생성 스크립트
  │   │   │   ├── Linux_user_rollback.sh          # 계정 생성 롤백 스크립트
  │   │   │   └── Linux_user_verify.sh            # 계정 생성 검증 스크립트
  │   │   ├── file-system/                        # [파일시스템 관리]
  │   │   │   ├── Linux_filesystem_gen.sh         # 마운트/디스크 설정 스크립트
  │   │   │   ├── Linux_filesystem_rollback.sh    # 마운트/디스크 설정 롤백 스크립트
  │   │   │   └── Linux_filesystem_verify.sh      # 마운트/디스크 설정 검증 스크립트
  │   │   ├── os-parameter/                       # [OS 파라미터 설정]
  │   │   │   ├── os_param_apply.sh               # OS 파라미터 설정 스크립트
  │   │   │   ├── os_param_rollback.sh            # OS 파라미터 설정 롤백 스크립트
  │   │   │   └── os_param_verify.sh              # OS 파라미터 설정 검증 스크립트
  │   │   ├── monitoring/                         # [COTS 모니터링 설정]
  │   │   │   └── setup_monitoring.sh             # exporter, collector 설정 스크립트
  │   │   └── sw_modules/                         # [SW 자동 설치]
  │   │       ├── setup_sw.sh                     # [메인] SW 설치 제어 스크립트
  │   │       ├── install_python.sh               # Python 설치 모듈
  │   │       └── ... (기타 모듈)
  │   │
  │   └── windows/                                # [Windows 영역]
  │       ├── config/                             # 전역 및 호스트별 설정 파일
  │       │   ├── windows_user_gen.csv            # 계정 생성 정보
  │       │   ├── sw_mapping_windows.txt          # Windows 서버별 SW 매핑 정보
  │       │   ├── windows_common.ps1              # 전역 기본값 및 공통 로그 함수
  │       │   └── env/                            # [호스트별 개별 환경 설정]
  │       │       └── host3.ps1                   # 특정 호스트 전용 설정
  │       ├── init.ps1                            # OS Setup 파일 및 구조 자동 배포 스크립트 
  │       ├── account/                            # [계정 관리]
  │       │   ├── windows_user_gen.ps1            # 계정 생성 스크립트
  │       │   ├── windows_user_rollback.ps1       # 계정 생성 롤백 스크립트
  │       │   └── windows_user_verify.ps1         # 계정 생성 검증 스크립트
  │       ├── monitoring/                         # [COTS 모니터링 설정]
  │       │   └── setup_monitoring.ps1            # exporter, collector 설정 스크립트
  │       └── sw_modules/                         # [SW 자동 설치]
  │           ├── setup_sw.ps1                    # [메인] SW 설치 제어 스크립트
  │           ├── install_jdk.ps1                 # JDK 설치 모듈
  │           └── ... (기타 모듈)
  │
  └── files/                                      # 설치 파일 저장 영역 (sw_mapping.txt에 기재될 sw-version과 동일한 디렉토리로 생성)
      ├── linux/                                  # Linux용 설치 바이너리/압축파일
      │   ├── python_3.10.9_32b/
      │   └── python_3.10.9_64b/
      └── windows/                                # Windows용 설치 바이너리/압축파일
          ├── sw_version_32b/
          └── sw_version_64b/
```
