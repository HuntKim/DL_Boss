# os-setup

B Cloud 베어메탈 → A Cloud VM 마이그레이션 프로젝트의 "단계 2": Assessment
(`../Assessment`, 단계 1)에서 조사된 자료를 기준으로 신규 VM에
계정/그룹, OS 파라미터, 스토리지, 디렉터리 권한을 구성한다.

기존 `os-setup-main`의 SW 설치 모듈(`sw_modules`, JDK/Oracle Client 등)은
계속 `os-setup-main`에서 별도로 관리되고, 이 폴더는 그와 분리된 새 구현이다.

- [`linux/README.md`](linux/README.md) - RHEL/Ubuntu, 이 세션에서 실제
  실행 테스트까지 완료
- [`windows/README.md`](windows/README.md) - Windows Server, PowerShell
  실행 환경이 없어 코드 리뷰로만 검증 (실서버 검증 필요)

두 쪽 모두 같은 설계 원칙을 따른다:
1. **CSV를 쓰지 않는다** - 호스트별 데이터는 `config/env/<hostname>.*`
   파일에 직접 선언한다.
2. **manifest 기반 롤백** - 각 생성/적용 스크립트는 "실제로 만든 것"만
   기록해두고, 롤백은 그 기록만 근거로 되돌린다(env 정의를 직접 순회하며
   삭제하지 않음 - 개발 중 실제로 시스템 그룹이 삭제되는 사고를 겪은 뒤
   확립된 원칙).
3. **네이티브 설정 형식 사용** - OS 파라미터는 Linux는 sysctl.conf/
   limits.conf, Windows는 .reg 형식 그대로 사용해 커스텀 파싱을 최소화한다.
4. **계정/그룹, OS 파라미터, 스토리지, 디렉터리 권한을 4개의 독립된
   단계**로 분리하고, 각 단계마다 적용(gen/apply) · 롤백 · 검증(verify)
   스크립트를 모두 제공한다.
