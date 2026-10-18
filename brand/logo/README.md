# Cloud OS Tech Service — 로고 시안

삼성전자 DS Cloud VM 게스트 OS 운영 유지보수·관제 사업("Cloud OS Tech
Service")을 대표하는 로고 시안. 각 PNG는 아이콘 + 워드마크 조합(흰색
배경, 3배 해상도)이고, 라이브로 색상을 바꿔보거나 다크/모노크롬/앱
아이콘 버전까지 보려면 디자인 캔버스를 참고.

- 디자인 캔버스(편집 가능): https://claude.ai/artifact/T17axZ2Xfwwr14RWeUwnan

## 시안 목록

### 1. `option1-pulse-cloud.png` — Pulse Cloud
클라우드 윤곽 안에 모니터링 펄스(심전도형 선)를 통과시킨 마크. "클라우드
위에서 돌아가는 Guest OS를 실시간으로 관제한다"는 컨셉을 가장 직관적으로
보여줌.
- Base `#1B2A4A`(인디고 네이비) / Accent `#2DD4C8`(시안)
- 폰트: Space Grotesk

### 2. `option2-shield-monogram.png` — Shield Monogram
쉴드(뱃지) 안에 열린 원형 "C" 모노그램. 관제보다 "안정적으로 지켜준다
(SLA, 장애 대응)"는 신뢰감을 강조.
- Base `#23262B`(차콜) / Accent `#F2994A`(앰버)
- 폰트: IBM Plex Sans

### 3. `option3-orbit-server.png` — Orbit Server
서버(VM) 스택을 점선 궤도가 도는 원형 뱃지. "24시간 돌면서 지켜본다"는
관제 이미지에 가장 가깝고, 원형이라 즐겨찾기/프로필 아이콘으로도 활용
용이.
- Base `#0F3D3E`(딥 틸) / Accent `#FF7A59`(코랄)
- 폰트: Manrope

### 4. `option1b-pulse-cloud-stacked.png` — Pulse Cloud (워드마크 2단)
1안과 동일한 마크, 워드마크만 2줄로 재배치:
```
CLOUD
OS Tech Service
```
- 색상/폰트는 1안과 동일(Base `#1B2A4A` / Accent `#2DD4C8`, Space Grotesk)

### `option1b/` — Pulse Cloud (워드마크 2단) 4종 배경 투명 PNG
위 4번 시안의 사용처별 버전. 전부 여백이 투명(alpha=0)인 PNG — 캔버스에
흰 배경이 깔려 있지 않아 어떤 바탕 위에든 바로 올릴 수 있음. "CLOUD" /
"OS Tech Service" 두 줄은 아이콘 옆에서 서로 중앙 정렬.

- `option1b-main.png` — 기본 조합(남색 아이콘 + 남색/회색 워드마크), 밝은 배경용
- `option1b-dark.png` — 흰색 아이콘 + 흰색/연회색 워드마크, 남색 라운드 카드 위에
  배치된 상태로 내보냄(어두운 배경에 바로 쓰는 완성형)
- `option1b-dark-nobg.png` — 위와 동일한 흰색 아이콘·워드마크이지만 카드 없이
  여백만 투명 — 자체적으로 어두운 배경(사진, 커스텀 색상 등) 위에 직접 올릴 때 사용.
  흰 배경 위에서 열면 흰색 로고 부분은 안 보이는 게 정상(투명 PNG라서 그런 것).
- `option1b-monochrome.png` — 아이콘·워드마크 전부 남색 단색 아웃라인, 팩스/각인/
  단색 인쇄용
- `option1b-appicon.png` — 워드마크 없이 아이콘만, 남색 라운드 사각 타일 위(앱
  아이콘·파비콘용 완성형)

## 참고

- 세 안 모두 삼성 고유 블루와는 다른 색 계열로 잡아, 삼성 내부가 아니라
  이 사업을 수행하는 독립 운영사로서의 브랜드 느낌을 의도함.
- PNG는 이 레포(cloud container)에 Google Fonts 접근이 막혀 있어, 실제
  브랜드 폰트 파일(npm `@fontsource/*` 패키지)을 받아 로컬 렌더링한
  것 — 디자인 캔버스에서 보는 것과 동일한 폰트/색상.
