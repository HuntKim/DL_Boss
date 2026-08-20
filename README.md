oot@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]#
[root@dkhosmanagedw02 sw-modules]# ./setup_sw.sh
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] =========================================================
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02]  SW 자동 설치 작업을 시작합니다. (Host: dkhosmanagedw02)
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02]  로그 파일 저장 위치: /tmp/os-setup/log/setup_sw_dkhosmanagedw02_20260820_181435.log
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] =========================================================
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] CONFIG_DIR = /tmp/os-setup/linux/config
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 호스트 전용 환경설정 로드 완료: dkhosmanagedw02.env
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 설치 대상 SW 리스트: oracle_jdk_1.8.0_202_64b,oracle_client_19.3.0.0
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] --------------------------------------------------
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] [PROCESS] oracle_jdk_1.8.0_202_64b
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02]  TYPE: oracle_jdk | VER: 1.8.0_202_64b | MODULE: install_jdk.sh
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02]  ▶ [oracle_jdk_1.8.0_202_64b] 모듈 호출을 시작합니다.
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] COMMON_ENV==/tmp/os-setup/linux/config/linux_common.env
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] CONFIG_DIR = /tmp/os-setup/linux/config
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 호스트 전용 환경설정 로드 완료: dkhosmanagedw02.env
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] JAVA_HOME = /usr/java  (공통 설정 linux_common.env 사용)
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] === JDK 설치 모듈 시작 (타입: oracle_jdk, 버전: 1.8.0_202_64b, 경로: /usr/lib/jvm) ===
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] DIR_NAME==oracle_jdk_1.8.0_202_64b
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 감지된 OS: RHEL9 (패키지 관리자: dnf)
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] Oracle JDK 설치 진행...
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] =======NORM_REQUEST_VER=1.8.0.202,ORACLE_DIR_VER=1.8.0_202===========
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 버전 파싱 결과: SW_VERSION=1.8.0_202_64b -> CORE_VERSION=1.8.0_202 / ARCH_SUFFIX=64b
[INFO]    2026-08-20 18:14:35 - [dkhosmanagedw02] 설치 여부 확인 (RPM 패키지 기준): jdk_1.8.0_202
[SUCCESS] 2026-08-20 18:14:37 - [dkhosmanagedw02] 요청 버전(1.8.0_202_64b)이 이미 RPM으로 설치되어 있습니다. 설치를 건너뜁니다: jdk1.8-1.8.0_202-fcs.x86_64
[SUCCESS] 2026-08-20 18:14:37 - [dkhosmanagedw02]  ▷ [oracle_jdk_1.8.0_202_64b] 모듈 실행이 완료되었습니다.
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] --------------------------------------------------
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] [PROCESS] oracle_client_19.3.0.0
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02]  TYPE: oracle_client | VER: 19.3.0.0 | MODULE: install_oracle.sh
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02]  ▶ [oracle_client_19.3.0.0] 모듈 호출을 시작합니다.
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 호스트 전용 환경설정 로드 완료: dkhosmanagedw02.env
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] === Oracle Client 설치 모듈 시작 (TYPE: oracle_client, 버전: 19.3.0.0, ORACLE_HOME: /oracle/client) ===
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] DIR_NAME==oracle_client_19.3.0.0
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] ORACLE_HOME = /oracle/CLIENT/oracle  (호스트 전용 설정 TARGET_ORACLE_HOME 사용)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] ORACLE_BASE = /oracle/CLIENT  (호스트 전용 설정 TARGET_ORACLE_BASE 사용)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] STAGE_DIR = /oracle/stage  (호스트 전용 설정 TARGET_STAGE_DIR 사용)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] UNIX_GROUP_NAME = dba  (호스트 전용 설정 TARGET_UNIX_GROUP_NAME 사용)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] INVENTORY_LOCATION = /oracle/oraInventory  (호스트 전용 설정 TARGET_INVENTORY_LOCATION 사용)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 기존 설치 파일이 없습니다 (/oracle/CLIENT/oracle/bin/sqlplus). 신규 설치를 진행합니다.
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 필수 dnf 패키지 설치 검증을 시작합니다.
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] OS_VERSION 원본 문자열: Red Hat Enterprise Linux release 9.2 (Plow)
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 감지된 메이저 버전: 9
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 감지된 OS: RHEL 9 계열 (Red Hat Enterprise Linux release 9.2 (Plow))
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] CV_ASSUME_DISTID로 사용할 값: OL8
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] #################### 실행 대상 목록 ####################
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] Repository 패키지 (30개): unzip bc binutils compat-openssl11 elfutils-libelf fontconfig glibc glibc-devel ksh libaio libasan liblsan libX11 libXau libXi libXrender libXtst libxcrypt-compat libgcc libibverbs libnsl librdmacm libstdc++ libxcb libvirt-libs make policycoreutils policycoreutils-python-utils smartmontools sysstat
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] ######################################################
[INFO]    2026-08-20 18:14:37 - [dkhosmanagedw02] 패키지 설치 시도 중... (1/3)
Updating Subscription Management repositories.
Unable to read consumer identity

This system is not registered with an entitlement server. You can use subscription-manager to register.

Last metadata expiration check: 1:39:09 ago on Thu 20 Aug 2026 04:35:29 PM KST.
Package unzip-6.0-56.el9.x86_64 is already installed.
Package bc-1.07.1-14.el9.x86_64 is already installed.
Package binutils-2.35.2-37.el9.x86_64 is already installed.
Package elfutils-libelf-0.188-3.el9.x86_64 is already installed.
Package fontconfig-2.14.0-2.el9_1.x86_64 is already installed.
Package glibc-2.34-275.el9_8.x86_64 is already installed.
Package glibc-2.34-275.el9_8.i686 is already installed.
Package glibc-devel-2.34-275.el9_8.x86_64 is already installed.
Package ksh-3:1.0.6-15.el9.x86_64 is already installed.
Package libaio-0.3.111-13.el9.x86_64 is already installed.
Package libX11-1.7.0-7.el9.x86_64 is already installed.
Package libXau-1.0.9-8.el9.x86_64 is already installed.
Package libXi-1.7.10-8.el9.x86_64 is already installed.
Package libXrender-0.9.10-16.el9.x86_64 is already installed.
Package libXtst-1.2.3-16.el9.x86_64 is already installed.
Package libxcrypt-compat-4.4.18-3.el9.x86_64 is already installed.
Package libgcc-11.5.0-14.el9.x86_64 is already installed.
Package libgcc-11.5.0-14.el9.i686 is already installed.
Package libibverbs-44.0-2.el9.x86_64 is already installed.
Package libnsl-2.34-83.el9.7.x86_64 is already installed.
Package libstdc++-11.5.0-14.el9.x86_64 is already installed.
Package libstdc++-11.5.0-14.el9.i686 is already installed.
Package libxcb-1.13.1-9.el9.x86_64 is already installed.
Package make-1:4.3-8.el9.x86_64 is already installed.
Package policycoreutils-3.5-1.el9.x86_64 is already installed.
Package policycoreutils-python-utils-3.5-1.el9.noarch is already installed.
Package smartmontools-1:7.2-6.el9.x86_64 is already installed.
Dependencies resolved.
================================================================================
 Package                        Arch     Version              Repository   Size
================================================================================
Installing:
 compat-openssl11               x86_64   1:1.1.1k-5.el9_8.4   Appstream   1.5 M
 libasan                        x86_64   11.5.0-14.el9        Appstream   407 k
 liblsan                        x86_64   11.5.0-14.el9        Appstream   185 k
 librdmacm                      x86_64   61.0-2.el9           BaseOS       79 k
 libvirt-libs                   x86_64   11.10.0-12.3.el9_8   Appstream   5.5 M
 sysstat                        x86_64   12.5.4-11.el9        Appstream   487 k
Upgrading:
 binutils                       x86_64   2.35.2-72.el9        BaseOS      4.6 M
 elfutils-debuginfod-client     x86_64   0.194-1.el9          BaseOS       43 k
 elfutils-devel                 x86_64   0.194-1.el9          Appstream    49 k
 elfutils-libelf                x86_64   0.194-1.el9          BaseOS      201 k
 elfutils-libelf-devel          x86_64   0.194-1.el9          Appstream    79 k
 elfutils-libs                  x86_64   0.194-1.el9          BaseOS      268 k
 libX11                         x86_64   1.8.12-1.el9         Appstream   652 k
 libX11-common                  noarch   1.8.12-1.el9         Appstream   197 k
 libXrender                     x86_64   0.9.10-16.el9_8.1    Appstream    32 k
 libibverbs                     x86_64   61.0-2.el9           BaseOS      487 k
 libnsl                         x86_64   2.34-275.el9_8       BaseOS       74 k
 libselinux                     x86_64   3.6-3.el9            BaseOS       88 k
 libselinux-utils               x86_64   3.6-3.el9            BaseOS      194 k
 libsemanage                    x86_64   3.6-5.el9_6          BaseOS      121 k
 libsepol                       x86_64   3.6-3.el9            BaseOS      331 k
 numactl-libs                   x86_64   2.0.19-3.el9         BaseOS       30 k
 policycoreutils                x86_64   3.6-5.el9            BaseOS      245 k
 policycoreutils-python-utils   noarch   3.6-5.el9            Appstream    82 k
 python3-libselinux             x86_64   3.6-3.el9            Appstream   192 k
 python3-libsemanage            x86_64   3.6-5.el9_6          Appstream    81 k
 python3-policycoreutils        noarch   3.6-5.el9            Appstream   2.1 M
 smartmontools                  x86_64   1:7.2-10.el9         BaseOS      563 k
 unzip                          x86_64   6.0-60.el9           BaseOS      182 k
Installing dependencies:
 pcp-conf                       x86_64   6.3.7-8.el9_8.4      Appstream    37 k
 pcp-libs                       x86_64   6.3.7-8.el9_8.4      Appstream   653 k

Transaction Summary
================================================================================
Install   8 Packages
Upgrade  23 Packages

Total download size: 20 M
Downloading Packages:
(1/31): liblsan-11.5.0-14.el9.x86_64.rpm         74 kB/s | 185 kB     00:02
(2/31): libasan-11.5.0-14.el9.x86_64.rpm        163 kB/s | 407 kB     00:02
(3/31): sysstat-12.5.4-11.el9.x86_64.rpm        194 kB/s | 487 kB     00:02
(4/31): pcp-conf-6.3.7-8.el9_8.4.x86_64.rpm     3.6 MB/s |  37 kB     00:00
(5/31): pcp-libs-6.3.7-8.el9_8.4.x86_64.rpm      26 MB/s | 653 kB     00:00
(6/31): compat-openssl11-1.1.1k-5.el9_8.4.x86_6  26 MB/s | 1.5 MB     00:00
(7/31): librdmacm-61.0-2.el9.x86_64.rpm         4.5 MB/s |  79 kB     00:00
(8/31): python3-libsemanage-3.6-5.el9_6.x86_64. 9.2 MB/s |  81 kB     00:00
(9/31): python3-libselinux-3.6-3.el9.x86_64.rpm  11 MB/s | 192 kB     00:00
(10/31): libX11-common-1.8.12-1.el9.noarch.rpm   17 MB/s | 197 kB     00:00
(11/31): elfutils-devel-0.194-1.el9.x86_64.rpm  5.2 MB/s |  49 kB     00:00
(12/31): policycoreutils-python-utils-3.6-5.el9 9.3 MB/s |  82 kB     00:00
(13/31): libX11-1.8.12-1.el9.x86_64.rpm          33 MB/s | 652 kB     00:00
(14/31): elfutils-libelf-devel-0.194-1.el9.x86_  11 MB/s |  79 kB     00:00
(15/31): libvirt-libs-11.10.0-12.3.el9_8.x86_64  36 MB/s | 5.5 MB     00:00
(16/31): libXrender-0.9.10-16.el9_8.1.x86_64.rp 887 kB/s |  32 kB     00:00
(17/31): libselinux-3.6-3.el9.x86_64.rpm        8.6 MB/s |  88 kB     00:00
(18/31): libselinux-utils-3.6-3.el9.x86_64.rpm   15 MB/s | 194 kB     00:00
(19/31): libsemanage-3.6-5.el9_6.x86_64.rpm      15 MB/s | 121 kB     00:00
(20/31): python3-policycoreutils-3.6-5.el9.noar  25 MB/s | 2.1 MB     00:00
(21/31): numactl-libs-2.0.19-3.el9.x86_64.rpm   1.8 MB/s |  30 kB     00:00
(22/31): libsepol-3.6-3.el9.x86_64.rpm           13 MB/s | 331 kB     00:00
(23/31): elfutils-debuginfod-client-0.194-1.el9 5.7 MB/s |  43 kB     00:00
(24/31): elfutils-libelf-0.194-1.el9.x86_64.rpm  22 MB/s | 201 kB     00:00
(25/31): libibverbs-61.0-2.el9.x86_64.rpm        31 MB/s | 487 kB     00:00
(26/31): smartmontools-7.2-10.el9.x86_64.rpm     31 MB/s | 563 kB     00:00
(27/31): unzip-6.0-60.el9.x86_64.rpm             14 MB/s | 182 kB     00:00
(28/31): elfutils-libs-0.194-1.el9.x86_64.rpm    28 MB/s | 268 kB     00:00
(29/31): policycoreutils-3.6-5.el9.x86_64.rpm    25 MB/s | 245 kB     00:00
(30/31): libnsl-2.34-275.el9_8.x86_64.rpm       7.6 MB/s |  74 kB     00:00
(31/31): binutils-2.35.2-72.el9.x86_64.rpm       54 MB/s | 4.6 MB     00:00
--------------------------------------------------------------------------------
Total                                           7.1 MB/s |  20 MB     00:02
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Preparing        :                                                        1/1
  Upgrading        : libsepol-3.6-3.el9.x86_64                             1/54
  Upgrading        : libselinux-3.6-3.el9.x86_64                           2/54
  Running scriptlet: libselinux-3.6-3.el9.x86_64                           2/54
  Upgrading        : elfutils-libelf-0.194-1.el9.x86_64                    3/54
  Upgrading        : elfutils-libs-0.194-1.el9.x86_64                      4/54
  Upgrading        : elfutils-debuginfod-client-0.194-1.el9.x86_64         5/54
  Upgrading        : python3-libselinux-3.6-3.el9.x86_64                   6/54
  Upgrading        : libsemanage-3.6-5.el9_6.x86_64                        7/54
  Upgrading        : python3-libsemanage-3.6-5.el9_6.x86_64                8/54
  Upgrading        : elfutils-libelf-devel-0.194-1.el9.x86_64              9/54
  Upgrading        : libselinux-utils-3.6-3.el9.x86_64                    10/54
  Upgrading        : policycoreutils-3.6-5.el9.x86_64                     11/54
  Running scriptlet: policycoreutils-3.6-5.el9.x86_64                     11/54
  Upgrading        : python3-policycoreutils-3.6-5.el9.noarch             12/54
  Upgrading        : libibverbs-61.0-2.el9.x86_64                         13/54
  Upgrading        : numactl-libs-2.0.19-3.el9.x86_64                     14/54
  Upgrading        : libX11-common-1.8.12-1.el9.noarch                    15/54
  Upgrading        : libX11-1.8.12-1.el9.x86_64                           16/54
  Installing       : pcp-conf-6.3.7-8.el9_8.4.x86_64                      17/54
  Installing       : pcp-libs-6.3.7-8.el9_8.4.x86_64                      18/54
  Installing       : sysstat-12.5.4-11.el9.x86_64                         19/54
  Running scriptlet: sysstat-12.5.4-11.el9.x86_64                         19/54
Created symlink /etc/systemd/system/multi-user.target.wants/sysstat.service → /usr/lib/systemd/system/sysstat.service.
Created symlink /etc/systemd/system/sysstat.service.wants/sysstat-collect.timer → /usr/lib/systemd/system/sysstat-collect.timer.
Created symlink /etc/systemd/system/sysstat.service.wants/sysstat-summary.timer → /usr/lib/systemd/system/sysstat-summary.timer.

  Upgrading        : libXrender-0.9.10-16.el9_8.1.x86_64                  20/54
  Installing       : libvirt-libs-11.10.0-12.3.el9_8.x86_64               21/54
  Installing       : librdmacm-61.0-2.el9.x86_64                          22/54
  Upgrading        : policycoreutils-python-utils-3.6-5.el9.noarch        23/54
  Upgrading        : elfutils-devel-0.194-1.el9.x86_64                    24/54
  Upgrading        : binutils-2.35.2-72.el9.x86_64                        25/54
  Running scriptlet: binutils-2.35.2-72.el9.x86_64                        25/54
  Upgrading        : smartmontools-1:7.2-10.el9.x86_64                    26/54
  Running scriptlet: smartmontools-1:7.2-10.el9.x86_64                    26/54
  Upgrading        : libnsl-2.34-275.el9_8.x86_64                         27/54
  Upgrading        : unzip-6.0-60.el9.x86_64                              28/54
  Installing       : compat-openssl11-1:1.1.1k-5.el9_8.4.x86_64           29/54
  Installing       : liblsan-11.5.0-14.el9.x86_64                         30/54
  Installing       : libasan-11.5.0-14.el9.x86_64                         31/54
  Cleanup          : elfutils-devel-0.188-3.el9.x86_64                    32/54
  Cleanup          : elfutils-libelf-devel-0.188-3.el9.x86_64             33/54
  Cleanup          : policycoreutils-python-utils-3.5-1.el9.noarch        34/54
  Cleanup          : python3-policycoreutils-3.5-1.el9.noarch             35/54
  Running scriptlet: policycoreutils-3.5-1.el9.x86_64                     36/54
  Cleanup          : policycoreutils-3.5-1.el9.x86_64                     36/54
  Cleanup          : libselinux-utils-3.5-1.el9.x86_64                    37/54
  Cleanup          : python3-libsemanage-3.5-1.el9.x86_64                 38/54
  Cleanup          : libsemanage-3.5-1.el9.x86_64                         39/54
  Cleanup          : python3-libselinux-3.5-1.el9.x86_64                  40/54
  Running scriptlet: smartmontools-1:7.2-6.el9.x86_64                     41/54
  Cleanup          : smartmontools-1:7.2-6.el9.x86_64                     41/54
  Running scriptlet: smartmontools-1:7.2-6.el9.x86_64                     41/54
  Running scriptlet: binutils-2.35.2-37.el9.x86_64                        42/54
  Cleanup          : binutils-2.35.2-37.el9.x86_64                        42/54
  Running scriptlet: binutils-2.35.2-37.el9.x86_64                        42/54
  Cleanup          : elfutils-debuginfod-client-0.188-3.el9.x86_64        43/54
  Cleanup          : elfutils-libs-0.188-3.el9.x86_64                     44/54
  Cleanup          : libXrender-0.9.10-16.el9.x86_64                      45/54
  Cleanup          : libX11-1.7.0-7.el9.x86_64                            46/54
  Cleanup          : libselinux-3.5-1.el9.x86_64                          47/54
  Cleanup          : libX11-common-1.7.0-7.el9.noarch                     48/54
  Cleanup          : libsepol-3.5-1.el9.x86_64                            49/54
  Cleanup          : elfutils-libelf-0.188-3.el9.x86_64                   50/54
  Cleanup          : libnsl-2.34-83.el9.7.x86_64                          51/54
  Cleanup          : unzip-6.0-56.el9.x86_64                              52/54
  Cleanup          : libibverbs-44.0-2.el9.x86_64                         53/54
  Cleanup          : numactl-libs-2.0.14-9.el9.x86_64                     54/54
  Running scriptlet: numactl-libs-2.0.14-9.el9.x86_64                     54/54
  Verifying        : libasan-11.5.0-14.el9.x86_64                          1/54
  Verifying        : liblsan-11.5.0-14.el9.x86_64                          2/54
  Verifying        : sysstat-12.5.4-11.el9.x86_64                          3/54
  Verifying        : libvirt-libs-11.10.0-12.3.el9_8.x86_64                4/54
  Verifying        : compat-openssl11-1:1.1.1k-5.el9_8.4.x86_64            5/54
  Verifying        : pcp-conf-6.3.7-8.el9_8.4.x86_64                       6/54
  Verifying        : pcp-libs-6.3.7-8.el9_8.4.x86_64                       7/54
  Verifying        : librdmacm-61.0-2.el9.x86_64                           8/54
  Verifying        : python3-libselinux-3.6-3.el9.x86_64                   9/54
  Verifying        : python3-libselinux-3.5-1.el9.x86_64                  10/54
  Verifying        : python3-libsemanage-3.6-5.el9_6.x86_64               11/54
  Verifying        : python3-libsemanage-3.5-1.el9.x86_64                 12/54
  Verifying        : libX11-common-1.8.12-1.el9.noarch                    13/54
  Verifying        : libX11-common-1.7.0-7.el9.noarch                     14/54
  Verifying        : elfutils-devel-0.194-1.el9.x86_64                    15/54
  Verifying        : elfutils-devel-0.188-3.el9.x86_64                    16/54
  Verifying        : libX11-1.8.12-1.el9.x86_64                           17/54
  Verifying        : libX11-1.7.0-7.el9.x86_64                            18/54
  Verifying        : policycoreutils-python-utils-3.6-5.el9.noarch        19/54
  Verifying        : policycoreutils-python-utils-3.5-1.el9.noarch        20/54
  Verifying        : python3-policycoreutils-3.6-5.el9.noarch             21/54
  Verifying        : python3-policycoreutils-3.5-1.el9.noarch             22/54
  Verifying        : elfutils-libelf-devel-0.194-1.el9.x86_64             23/54
  Verifying        : elfutils-libelf-devel-0.188-3.el9.x86_64             24/54
  Verifying        : libXrender-0.9.10-16.el9_8.1.x86_64                  25/54
  Verifying        : libXrender-0.9.10-16.el9.x86_64                      26/54
  Verifying        : libselinux-3.6-3.el9.x86_64                          27/54
  Verifying        : libselinux-3.5-1.el9.x86_64                          28/54
  Verifying        : libselinux-utils-3.6-3.el9.x86_64                    29/54
  Verifying        : libselinux-utils-3.5-1.el9.x86_64                    30/54
  Verifying        : libsemanage-3.6-5.el9_6.x86_64                       31/54
  Verifying        : libsemanage-3.5-1.el9.x86_64                         32/54
  Verifying        : libsepol-3.6-3.el9.x86_64                            33/54
  Verifying        : libsepol-3.5-1.el9.x86_64                            34/54
  Verifying        : numactl-libs-2.0.19-3.el9.x86_64                     35/54
  Verifying        : numactl-libs-2.0.14-9.el9.x86_64                     36/54
  Verifying        : binutils-2.35.2-72.el9.x86_64                        37/54
  Verifying        : binutils-2.35.2-37.el9.x86_64                        38/54
  Verifying        : elfutils-debuginfod-client-0.194-1.el9.x86_64        39/54
  Verifying        : elfutils-debuginfod-client-0.188-3.el9.x86_64        40/54
  Verifying        : elfutils-libelf-0.194-1.el9.x86_64                   41/54
  Verifying        : elfutils-libelf-0.188-3.el9.x86_64                   42/54
  Verifying        : libibverbs-61.0-2.el9.x86_64                         43/54
  Verifying        : libibverbs-44.0-2.el9.x86_64                         44/54
  Verifying        : smartmontools-1:7.2-10.el9.x86_64                    45/54
  Verifying        : smartmontools-1:7.2-6.el9.x86_64                     46/54
  Verifying        : unzip-6.0-60.el9.x86_64                              47/54
  Verifying        : unzip-6.0-56.el9.x86_64                              48/54
  Verifying        : elfutils-libs-0.194-1.el9.x86_64                     49/54
  Verifying        : elfutils-libs-0.188-3.el9.x86_64                     50/54
  Verifying        : policycoreutils-3.6-5.el9.x86_64                     51/54
  Verifying        : policycoreutils-3.5-1.el9.x86_64                     52/54
  Verifying        : libnsl-2.34-275.el9_8.x86_64                         53/54
  Verifying        : libnsl-2.34-83.el9.7.x86_64                          54/54
Installed products updated.

Upgraded:
  binutils-2.35.2-72.el9.x86_64
  elfutils-debuginfod-client-0.194-1.el9.x86_64
  elfutils-devel-0.194-1.el9.x86_64
  elfutils-libelf-0.194-1.el9.x86_64
  elfutils-libelf-devel-0.194-1.el9.x86_64
  elfutils-libs-0.194-1.el9.x86_64
  libX11-1.8.12-1.el9.x86_64
  libX11-common-1.8.12-1.el9.noarch
  libXrender-0.9.10-16.el9_8.1.x86_64
  libibverbs-61.0-2.el9.x86_64
  libnsl-2.34-275.el9_8.x86_64
  libselinux-3.6-3.el9.x86_64
  libselinux-utils-3.6-3.el9.x86_64
  libsemanage-3.6-5.el9_6.x86_64
  libsepol-3.6-3.el9.x86_64
  numactl-libs-2.0.19-3.el9.x86_64
  policycoreutils-3.6-5.el9.x86_64
  policycoreutils-python-utils-3.6-5.el9.noarch
  python3-libselinux-3.6-3.el9.x86_64
  python3-libsemanage-3.6-5.el9_6.x86_64
  python3-policycoreutils-3.6-5.el9.noarch
  smartmontools-1:7.2-10.el9.x86_64
  unzip-6.0-60.el9.x86_64
Installed:
  compat-openssl11-1:1.1.1k-5.el9_8.4.x86_64   libasan-11.5.0-14.el9.x86_64
  liblsan-11.5.0-14.el9.x86_64                 librdmacm-61.0-2.el9.x86_64
  libvirt-libs-11.10.0-12.3.el9_8.x86_64       pcp-conf-6.3.7-8.el9_8.4.x86_64
  pcp-libs-6.3.7-8.el9_8.4.x86_64              sysstat-12.5.4-11.el9.x86_64

Complete!
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] yum 패키지 설치 명령이 성공적으로 완료되었습니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 필수 패키지 개별 설치 상태를 최종 점검합니다.
[WARN]    2026-08-20 18:14:56 - [dkhosmanagedw02] REQUIRED_PACKAGES가 정의되어 있지 않아 TARGET_PKGS(30개) 목록으로 검증을 대체합니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: unzip
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: bc
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: binutils
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: compat-openssl11
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: elfutils-libelf
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: fontconfig
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: glibc
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: glibc-devel
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: ksh
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libaio
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libasan
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: liblsan
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libX11
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libXau
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libXi
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libXrender
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libXtst
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libxcrypt-compat
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libgcc
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libibverbs
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libnsl
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: librdmacm
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libstdc++
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libxcb
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: libvirt-libs
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: make
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: policycoreutils
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: policycoreutils-python-utils
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: smartmontools
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02]  [OK] 패키지 설치됨: sysstat
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 모든 필수 패키지가 성공적으로 설치 및 검증되었습니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 디렉토리 생성 및 권한을 설정합니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 디렉토리 생성 완료: /oracle/CLIENT/oracle
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 디렉토리 생성 완료: /oracle/oraInventory
chown: invalid group: ‘oracle:dba’
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] Oracle 설치 파일 준비 작업을 시작합니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 설치파일zip 탐색 URL: https://osmanaged.samsungds.net/os_setup/files/linux/oracle_client_19.3.0.0/
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 탐색된 ZIP 파일명: LINUX.X64_193000_client_home.zip
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 대상 파일 확인: LINUX.X64_193000_client_home.zip
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 다운로드 URL: https://osmanaged.samsungds.net/os_setup/files/linux/oracle_client_19.3.0.0/LINUX.X64_193000_client_home.zip
[oracle] bash_profile 환경변수 등록 중...
[oracle] Client 설치 파일 다운로드 중... (https://osmanaged.samsungds.net/os_setup/files/linux/oracle_client_19.3.0.0/LINUX.X64_193000_client_home.zip)
bash: log_error: command not found
[ERROR]   2026-08-20 18:14:56 - [dkhosmanagedw02] Oracle 설치 파일 압축 해제 중 오류가 발생했습니다.
[ERROR]   2026-08-20 18:14:56 - [dkhosmanagedw02]  ▷ [oracle_client_19.3.0.0] 모듈 실행이 실패했습니다. (exit code: 1)
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] =========================================================
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 설치 결과 요약: 성공 1건 / 실패 1건
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] 성공 목록: oracle_jdk_1.8.0_202_64b
[ERROR]   2026-08-20 18:14:56 - [dkhosmanagedw02] 실패 목록: oracle_client_19.3.0.0
[ERROR]   2026-08-20 18:14:56 - [dkhosmanagedw02] dkhosmanagedw02 일부 SW 설치가 실패했습니다.
[INFO]    2026-08-20 18:14:56 - [dkhosmanagedw02] =========================================================
[root@dkhosmanagedw02 sw-modules]#
