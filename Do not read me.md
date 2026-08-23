# Github: Fine-grained personal access tokens(~ Nov 21 2026)
***REMOVED-REVOKED-TOKEN***

# Linux 명령 및 기타
## 계정 생성
```bash
groupadd -g 1100 dba
groupadd -g 1200 appgroup


useradd -u 1100 -d /oracle -m -s /bin/bash -g dba -G vboxsf oracle
useradd -u 1200 -d /home/smprc -m -s /bin/bash -g appgroup -G dba smprc


useradd -u 1100 -g vboxsf -d /oracle -m -s /bin/bash oracle
sudo usermod -aG <그룹명> oracle       //vboxsf

smprc:appgroup

```

## hostname 변경
```bash
# 변경
sudo hostnamectl set-hostname test  // [변경할_호스트명]
# 확인
hostnamectl status
```

## 패키지
* RHEL
```
rpm -q 패키지명
# dnf 사용 시 (RHEL 8 이상)
dnf search 키워드							// 특정 패키지 검색
dnf list installed 패키지명				// 설치된 패키지 확인
dnf list available | grep 키워드			// 사용 가능한(아직 설치 안 된) 전체 패키지 목록

# yum 사용 시 (RHEL 7 이하)
yum list installed 패키지명				// 설치된 패키지 확인
yum list available						// 사용 가능한(아직 설치 안 된) 전체 패키지 목록

# 업그레이드 시 충돌하는 꾸러미를 교체하려면 명령줄에 '--allowerasing'을 추가
dnf upgrade --allowerasing /DATA/DATA/00.OS_SETUP/2.App/3.pkg/libstdc++-8.5.0-28.el8_10*.x86_64.rpm
dnf upgrade --allowerasing /DATA/DATA/00.OS_SETUP/2.App/3.pkg/libstdc++-devel-8.5.0-23.el8_10.alma.1.x86_64.rpm
dnf upgrade --allowerasing /DATA/DATA/00.OS_SETUP/2.App/3.pkg/perl-5.26.3-422.el8.0.1.x86_64.rpm

rsh-0.17-94.el8.x86_64.rpm        
apr-1.6.3-12.el8.rpm              
apr-util-1.6.1-9.el8.rpm          
perl-5.26.3-422.el8.x86_64.rpm    
smem-1.5-6.el8.noarch.rpm         
libstdc++-8.5.0-28.el8            
apr-1.6.3-12.el8.x86_64.rpm       
perl-5.26.3-422.el8.0.1.x86_64.rpm
smem-1.5-6.el8.noarch.rpm         
telnet-0.17-76.el8.x86_64.rpm
```

* Ubuntu
```
apt list --installed | grep 패키지명
```

## OS별 Oracle Client 설치 필요 패키지
* 패키지 정리 (OS × 버전별)
* RHEL 8 — 19c 클라이언트 (19.3.0.0 / 19.25.0.0 공통)
	* 필수: bc, binutils, elfutils-libelf, elfutils-libelf-devel, glibc, glibc-devel, ksh, libaio, libaio-devel, libX11, libXau, libXi, libXrender, libXtst, libgcc, libnsl, librdmacm, libstdc++, libstdc++-devel, libxcb, libibverbs, make, policycoreutils, policycoreutils-python-utils, smartmontools, sysstat
  * 5단계 : X11 라이브러리(GUI 설치 이외 불필요)  libX11 libXau libXi libXrender libXtst libxcb fontconfig
	* 선택(클라이언트용):	libnsl2, libnsl2-devel, net-tools, ipmiutil
	```bash
	dnf install -y bc binutils elfutils-libelf elfutils-libelf-devel \
  glibc glibc-devel ksh libaio libaio-devel libX11 libXau libXi \
  libXrender libXtst libgcc libnsl librdmacm libstdc++ libstdc++-devel \
  libxcb libibverbs make policycoreutils policycoreutils-python-utils \
  smartmontools sysstat libnsl2 libnsl2-devel
  (RHEL 7과 달리 compat-libcap1, compat-libstdc++-33는 요구사항에서 빠졌습니다.)

* RHEL 9 — 19c 클라이언트 (19.19 이상, 즉 19.25.0.0 해당분)
	* 필수:	bc, binutils, compat-openssl11, elfutils-libelf, fontconfig, glibc, glibc-devel, ksh, libaio, libasan, liblsan, libX11, libXau, libXi, libXrender, libXtst, libxcrypt-compat, libgcc, libibverbs, libnsl, librdmacm, libstdc++, libxcb, libvirt-libs, make, policycoreutils, policycoreutils-python-utils, smartmontools, sysstat
	* 선택:	chkconfig, libnsl2, libnsl2-devel, net-tools, glibc-headers, ipmiutil
	```bash
	dnf install -y bc binutils compat-openssl11 elfutils-libelf fontconfig \
  glibc glibc-devel ksh libaio libasan liblsan libX11 libXau libXi \
  libXrender libXtst libxcrypt-compat libgcc libibverbs libnsl \
  librdmacm libstdc++ libxcb libvirt-libs make policycoreutils \
  policycoreutils-python-utils smartmontools sysstat libnsl2 libnsl2-devel
	```
	
[root@test 3.pkg]# dnf install ./perl-5.26.3-422.el8.0.1.x86_64.rpm
마지막 메타자료 만료확인 1:34:11 이전인: 2026년 07월 31일 (금) 오전 01시 21분 40초.
오류: 
 문제: 충돌하는 요청
  - perl-devel(x86-64) = 4:5.26.3-422.el8.0.1에 필요한 perl-4:5.26.3-422.el8.0.1.x86_64가 제공되지 않았습니다
  - perl-interpreter(x86-64) = 4:5.26.3-422.el8.0.1에 필요한 perl-4:5.26.3-422.el8.0.1.x86_64가 제공되지 않았습니다
  - perl-libs(x86-64) = 4:5.26.3-422.el8.0.1에 필요한 perl-4:5.26.3-422.el8.0.1.x86_64가 제공되지 않았습니다
(설치 할 수 없는 꾸러미를 건너 뛰려면 '--skip-broken'을 (를) 추가하십시오 또는 '--nobest'는 최적 후보의 꾸러미만 사용합니다)
[root@test 3.pkg]# 

perl-5.26.3-422.el8.0.1.x86_64.rpm을 설치하려고 하는데, 이 패키지가 제대로 동작하려면
perl-libs, perl-interpreter, perl-devel 같은 하위 모듈 패키지들도 
**동일한 버전(5.26.3-422.el8.0.1)**으로 함께 있어야 설치할 수 있다."

dnf upgrade --allowerasing perl-libs-5.26.3-422.el8.0.1.x86_64.rpm
dnf upgrade --allowerasing perl-interpreter-5.26.3-422.el8.0.1.x86_64.rpm
dnf upgrade --allowerasing perl-5.26.3-422.el8.0.1.x86_64.rpm
dnf upgrade --allowerasing perl-devel-5.26.3-422.el8.0.1.x86_64.rpm

=========== perl 위치 변경

"perl_5.26.3" 패키지라고 하신 걸 보면 배포판 repo의 표준 RPM(perl-5.26.x)이 아니라 소스 tarball을 직접 빌드하시는 경우로 보입니다. 이 기준으로 답변드리고, RPM 설치인 경우도 같이 짚어드릴게요.

1. 소스에서 빌드하는 경우 (perl-5.26.3.tar.gz)

기본 설치 위치는 /usr/local 밑입니다.

/usr/local/bin/perl
/usr/local/lib/perl5/5.26.3/
/usr/local/man/man1/, man3/

표준 빌드 절차:

bash
tar xzf perl-5.26.3.tar.gz
cd perl-5.26.3
./Configure -des -Dprefix=/usr/local
make
make test      # 선택사항
sudo make install
경로 변경 가능?

네, -Dprefix 옵션으로 원하는 위치를 지정하면 됩니다.

bash
./Configure -des -Dprefix=/opt/perl-5.26.3
make && sudo make install

이렇게 하면 실행 파일이 /opt/perl-5.26.3/bin/perl에 설치됩니다. 여러 버전을 공존시키고 싶을 때(시스템 기본 Perl은 그대로 두고) 이 방식을 많이 씁니다. 설치 후 PATH만 필요할 때 잡아주면 됩니다:

bash
export PATH=/opt/perl-5.26.3/bin:$PATH
2. RPM 패키지로 설치하는 경우

기본 위치는 배포판 정책에 고정되어 있습니다.

/usr/bin/perl
/usr/lib64/perl5/       (또는 /usr/share/perl5/)
/usr/share/man/man1/
경로 변경 가능?

RPM은 패키지가 **relocatable(재배치 가능)**로 빌드된 경우에만 가능합니다.

bash
rpm -qpi perl-5.26.3*.rpm | grep -i relocat

Relocations: (not relocatable)라고 나오면 경로 변경이 불가능합니다 — 대부분의 표준 Perl RPM이 여기 해당합니다. 재배치 가능한 패키지라면:

bash
rpm -ivh --prefix=/opt/perl perl-5.26.3*.rpm

혹시 이 Perl이 Oracle 관련 작업(OPatch나 특정 유틸리티가 요구하는 버전) 때문에 필요하신 거라면, 시스템 기본 Perl과 충돌 안 나게 소스 빌드 + 커스텀 prefix 방식을 추천드립니다. 어떤 용도로 쓰실 건지 알려주시면 그에 맞게 PATH/환경변수 설정까지 마저 안내해 드릴게요.


## 꼬띠 10.2 에서
./Configure -des -Dprefix=/usr/local \
  -Dccflags="-fcommon -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"


================================================================================================

LINUX (REDHAT)		

SW	VERSION	요청 사항 

openjdk	1.8.0_232	
openjdk	1.8.0_322	
openjdk	1.8.0.402	
openjdk	1.8.0.31	
oracle-jdk	1.8.0_202	
oracle-jdk	1.8.0_261	
oracle-jdk	8u172	
oracle-jdk	1.8.0_102	

Oracle Client	19c	
Oracle Client	19.25.0.0	
Oracle Client	19.3.0.0	
Oracle Client	19.0.0.0.0	
Oracle Client	11.2.0.4	
Oracle Client	11.2	


Python	3.10.9	RHEL 9
Node.js	22.16.0	RHEL 9

rsh	rsh-0.17-94.el8.x86_64.rpm	별도 파일 필요

perl	5.26.3	고객 요청 버전

apr		       	                                            dnf install
apr-util		                                            dnf install
telnet             	telnet-0.17-76.el8.x86_64	            dnf install
smem	            RHEL 8 : smem-1.5-6.el8.noarch       	dnf install
libstdc++6.0.i686	libstdc++-4.8.5-16.el7.i686          	dnf install
glibc		        glibc-2.17-196.el7_4.2.x86_64	        dnf install
glibc.i686	        glibc-2.17-196.el7_4.2.i686      	    dnf install
libtiff.so.3	    libtiff-3.9.4-10.el6_5.x86_64	        dnf install
libpng12.so.0       libpng-1.2.49-2.el6_7.x86_64	        dnf install

 

glibc             (64bit) & 
glibc.i686        (32bit)
libstdc++6.0.i686 (32bit) (또는 libstdc++.i686)
libpng12.so.0     (또는 libpng12)
libtiff.so.3      (또는 compat-libtiff3 / libtiff)
apr               (Apache Portable Runtime)
apr-util
smem
telnet

==========================================================

WINDOWS 	

SW	VERSION
oracle-jdk	1.7.0_80
oracle-jdk	1.8.0_265
oracle-jdk	8U45

.Net Framework	3.5
.Net Framework	4.0.30319
.Net Framework	4.5
.Net Framework	4.5.2
.Net Framework	4.7
.Net Framework	4.8
Oracle Client	11.2.0.4 (11gR2 64bit)
Oracle Client	19c

IIS (FTP 포함)	10.0 (OS 버전 기준)
Python	3.12.0
Visual Studio Code	1.108.1
SSMS	22



glibc
glibc.i686
libstdc++
libstdc++.i686
libpng12
libtiff
apr
apr-util
smem
telnet


export CV_ASSUME_DISTID=OL8   # 필요시
cd $ORACLE_HOME
./runInstaller -silent \
  -responseFile $ORACLE_HOME/install/response/clientsetup.rsp \
  oracle.install.option=INSTALL_DB_SWONLY \
  oracle.install.client.installType=Administrator
  ORACLE_HOSTNAME=$(hostname) \
  UNIX_GROUP_NAME=$UNIX_GROUP_NAME \
  INVENTORY_LOCATION=$INVENTORY_LOCATION \
  ORACLE_HOME=$ORACLE_HOME \
  ORACLE_BASE=$ORACLE_BASE
  
  
재설치 방법은 **"어느 단계에서 실패했는지"**와 **"어떤 에러였는지"**에 따라 접근이 달라지는데, 가장 주의할 점부터 말씀드리면 — Oracle deinstall 툴의 -silent 옵션은 실패한(불완전한) 설치에는 적용되지 않습니다. 즉 설치 중 에러로 중단된 상태라면 deinstall -silent로 바로 지우려 해도 안 먹히는 경우가 많아서, 아래처럼 접근하시는 게 안전합니다. 
Oracle

1단계 — 정리 시도 (deinstall)
bash
cd $ORACLE_HOME/deinstall
./deinstall

-silent 없이 대화형으로 실행해 보세요. 실패한 설치도 대화형 모드에서는 대부분 정상적으로 홈 정보를 읽어서 삭제를 진행해 줍니다.

2단계 — deinstall도 실패하면 수동 정리

설치가 아주 초기 단계(예: 압축 해제 직후, prerequisite 체크 단계)에서 죽었다면 deinstall 자체가 안 뜰 수도 있습니다. 이 경우 수동으로 지웁니다.

bash
# ORACLE_HOME 삭제
rm -rf $ORACLE_HOME

# oraInventory에 등록된 홈 정보 확인
cat /u01/app/oraInventory/ContentsXML/inventory.xml

inventory.xml에 방금 지운 ORACLE_HOME 경로가 <HOME NAME=... LOC=...> 형태로 남아있으면, 다음 재설치 시 "이미 등록된 홈"이라며 충돌 에러가 날 수 있습니다. 이 서버에 다른 Oracle 제품이 전혀 없고 이 Client가 유일한 설치였다면, oraInventory 자체를 통째로 지우는 게 가장 깔끔합니다.

bash
rm -rf /u01/app/oraInventory

(다른 Oracle Home이 이미 있는 서버라면 이 방법은 쓰지 마시고, inventory.xml에서 해당 <HOME> 태그만 골라서 지우거나 detachHome 옵션을 쓰셔야 합니다.)

3단계 — 클린 상태에서 재설치
bash
mkdir -p $ORACLE_HOME
cd $ORACLE_HOME
unzip -oq /경로/LINUX.X64_193000_client_home.zip

export CV_ASSUME_DISTID=OL8   # RHEL9에서 필요시
./runInstaller -silent \
  -responseFile $ORACLE_HOME/install/response/clientsetup.rsp \
  oracle.install.option=INSTALL_DB_SWONLY \
  ORACLE_HOSTNAME=$(hostname) \
  UNIX_GROUP_NAME=oinstall \
  INVENTORY_LOCATION=/u01/app/oraInventory \
  SELECTED_LANGUAGES=en \
  ORACLE_HOME=$ORACLE_HOME \
  ORACLE_BASE=$ORACLE_BASE
참고 — 실패 원인 로그 확인

같은 에러로 또 실패하지 않으려면, 지난번 실패 로그를 먼저 보시는 게 좋습니다.

bash
ls -lt /u01/app/oraInventory/logs/ | head
cat /u01/app/oraInventory/logs/installActions*.log | grep -i "error\|fail"

RHEL9.2면 커널 버전(5.14.0-70.22.1.el9_0 이상) 요건은 이미 충족하는 버전이라 그 부분 문제는 아닐 겁니다. 정확히 도와드리려면 설치 중 나온 에러 메시지 원문을 알려주시겠어요? (INS-로 시작하는 코드나 로그의 마지막 부분이면 좋습니다.) 그래야 지금처럼 일반적인 재설치 절차가 필요한 건지, 아니면 특정 prerequisite 문제라 그것만 고치면 되는 건지 정확히 짚어드릴 수 있습니다.
