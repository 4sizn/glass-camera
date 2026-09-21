# QUADRA Glass Camera — Product Requirements Document

버전: 1.4 · 작성일: 2026-09-20 · 상태: 사용자 실물 이미지 목표 반영, 실물 타당성 및 성능 검증 대기  
대상: Android / iOS 실시간 카메라 앱  
독자: 제품·모바일·그래픽스·컴퓨터비전·QA 담당자 및 코딩 에이전트

## 1. 문서 권한과 제품 목표

이 문서는 QUADRA Glass Camera의 범위, 광학 모델, 데이터 계약, 품질 기준, 구현 순서에 관한 단일 SSOT다. 기존 「동물 유리효과 만들기」 대화에서 합의한 내용을 통합하고, 구현 시 모호했던 좌표·단위·검증 기준을 보강했다. 과거 답변과 충돌하면 이 문서를 따른다. 런타임의 실제 재질 수치는 버전 관리되는 calibration JSON이 SSOT이며, 이 문서는 그 의미와 검증 규칙을 정의한다. 수치를 앱·셰이더·설정 화면에 중복 하드코딩하지 않는다.

목표는 스마트폰 카메라 앞에 실제 QUADRA 패턴 유리를 놓았을 때의 광학적 특성을 최대한 재현하는 것이다. 사각 셀 내부의 비선형 굴절, 셀 경계의 상 변화, 두께, 표면 곡률, 거리 의존성, 미세 색분산과 반사, 제조 편차를 하나의 일관된 모델로 설명한다. 동물의 눈·털·윤곽과 배경이 셀마다 다르게 굴절되어 ‘패턴 유리 너머로 촬영한’ 결과를 목표로 한다.

완전한 물리 재현을 보장하지는 않는다. 단일 카메라 영상에는 가려진 표면, 화면 밖 장면, 카메라 쪽 반사 환경이 없으며 P0/P1은 이를 명시적인 근사로 처리한다. 회절, 편광, 파동광학, 다중 내부 반사와 실제 장면에 생기는 caustics, 다중시점 복원은 범위 밖이다. QUADRA라는 명칭만으로 제조사·제품·유리 양면 형상을 확정하지 않는다. 확보한 실물의 제조사, SKU, 로트, 방향을 캘리브레이션 자산에 기록한다.

### 1.1 기준의 상태

| 구분 | 의미 |
|---|---|
| MUST | 해당 우선순위 완료에 필수인 구현·검증 요구사항 |
| 초기값 | 개발을 시작하기 위한 가설. 실측값이나 측정 성능이 아님 |
| 목표 | 출시 게이트로 제안한 수치. 실제 통과 보고서가 있어야 달성으로 기록 |
| calibrated | 실물 데이터, 검증 결과, 승인된 재질 버전이 함께 존재하는 상태 |

이 문서 작성으로 앱 구현, 실물 캘리브레이션 또는 성능 측정이 완료된 것은 아니다. 새로운 수치 변경은 변경 사유·데이터·영향받는 요구사항 ID를 PR에 기록한다.

## 2. 사용자 경험과 범위

앱 실행 → 카메라 권한 → QUADRA 실시간 프리뷰 → 유리 조절·전후면 전환·초점 조절 → 셔터 → 고해상도 처리 → 사진 저장 흐름을 제공한다. 최초 권한 거부·제한 상태에는 설정 안내를 제공한다. 저장 중 진행 상태를 표시하고 완료 후에만 성공을 알린다. 기본 화면에는 프리뷰, 셔터, 전후면 전환, 최근 사진 접근과 ‘유리 조절’ 버튼을 둔다. 두께·굴곡·셀 크기는 사용자용 슬라이더로 제공하고, depth confidence·상세 캘리브레이션 정보는 개발 진단 화면에 둔다.

| 우선순위 | 포함 범위 | 완료 의미 |
|---|---|---|
| P0 / 기술 MVP | 두 플랫폼 카메라, QUADRA height field·normal·이중 굴절·두께·경계·고정 seed 편차, 두께·굴곡·셀 크기 및 상세 형태 슬라이더, ConstantDepth, 고해상도 촬영·저장, JSON 로딩, 진단 뷰 | 동작하는 광학 기반 카메라. 실물 재현 검증 전 prototype으로 표시 |
| P1 / 실물 재현 릴리스 | Hardware/Estimated depth adapter, depth-aware tracing, RGB dispersion, Fresnel·반사 근사·imperfections, 실물 다중 거리 calibration 및 fitting | 실측·홀드아웃·성능·시각 평가를 통과한 calibrated QUADRA |
| P2 / 확장 | 다른 패턴, 자유 형상 편집·프리셋 공유, 동영상, Live Photo, RAW 파이프라인 | 별도 설계·요구사항·예산 승인 후 착수 |

P0부터 실물 샘플 확보와 촬영 지그 준비를 병행한다. P1 캘리브레이션을 끝내지 않은 제품을 ‘실제 QUADRA와 검증된 일치’로 표현하지 않는다. 동물 인식·배경 분할·얼굴 변형 모델, SNS·계정·클라우드 처리는 MVP에 필요하지 않다.

### 2.1 사용자 조절 패널 — P0 필수

프리뷰를 보면서 range slider를 드래그하여 효과를 조절한다. 기본 패널은 ‘두께’, ‘굴곡’, ‘셀 크기’ 세 항목을 제공하고, 펼칠 수 있는 상세 패널에 ‘모서리 둥글기’, ‘경계 굴곡’을 제공한다. 슬라이더에는 현재 값·단위·최솟값·최댓값을 표시하며 숫자 직접 입력, 한 단계 증감, 항목별 초기화와 전체 초기화를 지원한다. 물리 모델을 다시 계산하며 단순 UV strength 변경으로 대체하지 않는다.

| 표시 이름 | 파라미터 및 의미 | 초기 UI 범위 / step | prototype 기본값 |
|---|---|---|---|
| 두께 | optical.baseThicknessMm, 양 기준면 사이 두께 | 3~15mm / 0.1mm | 7mm |
| 굴곡 | surface.back.heightMm, 셀 중심 요철 높이 | 0~3mm / 0.05mm | 1mm |
| 셀 크기 | cell.pitchMm, 반복 셀의 가로·세로 간격 | 10~40mm / 0.5mm | 22×22mm |
| 모서리 둥글기 | surface.back.exponent, superellipse 지수 | 2~8 / 0.1 | 6 |
| 경계 굴곡 | surface.back.edgeAmplitudeMm, 경계 인접 요철 높이 | 0~0.5mm / 0.01mm | 0.1mm |

범위는 앱의 초기 조절 설계이며 실물 제품의 제조 규격이 아니다. 출하 전 조합별 유효성·성능을 검증하여 지원 구간을 확정한다. ‘굴곡’은 엄밀한 곡률 단위가 아니라 요철 높이 조절이다. 셀 크기와 함께 실제 gradient와 곡률이 달라진다. 굴곡 0에서도 경계 굴곡이 남을 수 있으며, 평판 비교는 두 값을 모두 0으로 설정한다. 둥글기 지수 2는 원형에 가깝고 8은 사각형에 가까우므로 화면에 양 끝 의미를 함께 표시한다.

셀 크기는 기본 가로·세로 비율 잠금이다. base pitch가 (px,py)일 때 표시 크기 s는 sqrt(px·py)이며 변경 시 두 축에 s/s_base를 동일하게 곱한다. prototype의 정사각형은 두 축이 같은 mm 값이다. 상세 패널에서 비율 잠금을 풀면 가로·세로를 각각 같은 범위로 조절한다. pitch 변경 시 glass origin과 pose를 고정하여 패턴이 같은 원점에서 확대·축소되게 한다. seed를 재생성하지 않는다.

### 2.2 변경 적용·복원·보존

- slider 입력은 최신 값으로 병합하고 프레임 경계에서 검증된 재질을 원자적으로 교체한다. 매 input마다 shader compile이나 카메라 재시작을 하지 않는다. 첫 변경의 표시 목표는 input→display p95≤100ms다.
- 모든 값 조합은 최소 국소 두께, surface 비교차, 유한 gradient 및 7절 교차 조건을 만족해야 한다. 결합 제약 때문에 불가능한 입력은 마지막 유효값을 유지하고 제한 이유를 표시한다. 사용자 모르게 다른 슬라이더 값을 바꾸지 않는다. 유효한 TIR 자체는 오류로 취급하지 않는다.
- 보정 재질 원본 JSON은 변경하지 않는다. UserMaterialOverrides를 별도로 저장하고 baseMaterialHash와 합성하여 effectiveMaterialHash를 계산한다. 조절 중에는 ‘사용자 조절’ 상태를 표시하며 원본의 실물 검증 상태를 그대로 상속하지 않는다. 전체 초기화는 원본 재질 값·seed를 정확히 복원한다.
- 마지막 유효 설정은 로컬에 저장하고 앱 재실행 시 복원한다. 저장은 드래그 종료 또는 debounce 시 수행한다. base 재질 버전 변경 시 override 호환성을 검증하고 불가능하면 기본값으로 복원하며 안내한다.
- 셔터는 화면에 마지막으로 제출된 유효 snapshot의 설정을 고정한다. 촬영 처리 중 조절은 다음 preview와 다음 촬영에만 반영된다. 저장 metadata에는 base/effective hash, overrides, seed를 함께 기록한다.
- screen reader로 항목 이름·현재 값·단위를 읽고 step 단위 증감을 지원한다. 조절 패널을 펼쳐도 프리뷰와 셔터를 사용할 수 있어야 한다.

## 3. 요구사항 및 Acceptance Criteria

각 행의 AC는 자동화 시험 또는 명시된 실기기·실물 시험 증거로 검증한다. 수치의 측정 방법은 11~13절이 정의한다.

| ID | 우선순위 | MUST 요구사항 | Acceptance Criteria |
|---|---|---|---|
| UX-001 | P0 | Android/iOS 실행 즉시 카메라 진입 | 권한 허용 상태에서 프리뷰 표시. 거부·철회·카메라 사용 중 오류에서 크래시 없이 복구 안내 |
| UX-002 | P0 | 전후면·회전·초점 상태 처리 | 지원 카메라 전환 20회 및 네 방향 회전에서 패턴 비율·프레이밍 정상. 전면 저장 미러 정책 일치 |
| UX-003 | P0 | 두께·굴곡·셀 크기 및 상세 형태 range slider | 2.1절 min/max/step·숫자 입력·단위·비율 잠금·항목/전체 초기화 동작. input→display p95≤100ms |
| MAT-002 | P0 | 사용자 override와 조합 유효성 관리 | 원본 JSON 불변, invalid 조합 거부, 마지막 설정 재실행 복원, 사용자 조절 상태 표시 및 전체 초기화 hash 복원 |
| CAP-003 | P0 | 조절 설정의 preview/capture 일치 | 드래그 도중 셔터 후 추가 변경에도 capture snapshot 불변. 저장 metadata의 effective hash와 실제 사용 재질 일치 |
| CAM-001 | P0 | native camera frame와 메타데이터 공급 | timestamp, crop, orientation, color space, intrinsics 또는 추정 여부가 모든 프레임에 존재 |
| OPT-001 | P0 | glass 좌표와 화면 좌표 분리 | 같은 프레이밍의 720p·1080p·고해상도 입력에서 셀 위치가 정규화 좌표 기준 일치 |
| OPT-002 | P0 | superellipse 기반 연속 height field | 높이·gradient·normal 진단 뷰 제공. 셀 경계 height/gradient 연속성과 최소 두께 검사 통과 |
| OPT-003 | P0 | gradient로 surface normal 계산 | CPU 기준 중앙차분과 GPU normal의 각도 오차 p95 ≤0.5°, 최대 ≤2° |
| OPT-004 | P0 | Air→Glass→Air 이중 굴절과 내부 진행 | identity·평행 평판·경사 입사·TIR 시험 통과. 단일 normal×strength UV offset으로 대체하지 않음 |
| OPT-005 | P0 | cell boundary curvature | 경계 밴드 폭·진폭 변경이 height와 ray에 반영. 검은 격자 오버레이로 경계를 대체하지 않음 |
| OPT-006 | P0 | deterministic manufacturing variation | 동일 seed/material/좌표의 재실행과 preview/capture에서 같은 편차. 시간에 따른 무작위 흔들림 없음 |
| DEP-001 | P0 | DepthSource 추상화 및 Constant fallback | 센서 없는 양 플랫폼에서 1.2m 기본 깊이로 촬영 가능. renderer에 플랫폼 depth 분기 없음 |
| DEP-002 | P1 | hardware/estimated depth 정렬·검증 | metric depth와 confidence·유효 마스크·timestamp 제공. 상대 깊이는 scale 확인 없이 meter로 사용하지 않음 |
| DEP-003 | P1 | depth-aware sampling | 다중 거리 평면·전경 경계 시험 통과. invalid/stale depth에서 정의된 fallback, NaN 및 경계 번짐 억제 |
| OPT-007 | P1 | RGB별 IOR 재추적 | 모든 IOR 동일 시 단색 trace와 일치. 실제 데이터 없는 과장된 무지개 테두리 금지 |
| OPT-008 | P1 | 양 경계 Fresnel·TIR·에너지 가중치 | 계수 0~1, 합 ≤1. reference/capture 정확식. preview 근사는 양 방향 전 입사각에서 절대오차≤0.01 및 최종 RGB 예산 통과 |
| OPT-009 | P1 | ReflectionSource와 근사 등급 명시 | none/low-frequency-frame 동작, camera-side 환경 추정 한계를 기록. 반사 강도 0에서 transmission 보존 |
| OPT-010 | P1 | 약한 표면 결함과 roughness | seed 고정, 유리 좌표에 부착. amplitude 0에서 기준 결과로 복귀; temporal shimmer 시험 통과 |
| OPT-011 | P1 | 공간 가변 PSF·유한 aperture·sampling 검증 | 17절 single-ray 대비 ablation, PSF/MTF 측정 및 footprint filtering 기준 통과 |
| OPT-012 | P0/P1 | 표면 내부 인공 seam 방지 | 셀 대각선 및 경계의 gradient 수렴 시험 통과 |
| CAL-004 | P0 착수/P1 | 실물 타당성과 불확실성 검증 | G0 후 M2/M3 착수. 반복측정 오차·식별성·지원 조건·미관측 비율 보고 |
| VIS-001 | P0 목표/P1 승인 | 제공 이미지의 셀별 국소 선명도·윤곽 어긋남·유리 표면감 재현 | 18절 A/B/C 비교 및 시각 체크 모두 통과. 일괄 blur·모자이크·얼굴 보정으로 대체 금지 |
| VIS-002 | P1 | reference-look의 반사·하이라이트 표현 | 공유 surface normal로 environment/light preset 반사. none은 비교용이며 reference-look 완료로 인정하지 않음 |
| VIS-003 | P1 | 시간적으로 안정된 유리와 반사 | 정지·좌우 이동·접근/후퇴 시험. glass seed 고정, 불연속적인 반사 점프·프레임 random 없음 |
| CAL-001 | P1 | 실물 다중 거리 paired dataset | 20/50/100/200cm마다 reference/distorted, 메타데이터·mask·split·파일 hash 완비 |
| CAL-002 | P1 | confidence 포함 displacement 측정 | flow 방향·단위 명시, 반복 checkerboard 오대응 제거, 거리별 유효 영역 비율 보고 |
| CAL-003 | P1 | 제약 있는 fitting 및 홀드아웃 검증 | 11절 품질 목표 통과. train/validation 분리 및 거리별 오차 보고서 재현 가능 |
| MAT-001 | P0 | versioned calibration JSON SSOT | 스키마 검증, 범위 오류 거부, 미지원 버전 안전 처리, 재질 hash 기록. prototype/calibrated 구분 |
| API-001 | P0 | GlassRenderer/GlassMaterial API와 backend 분리 | 동일 fixture를 Android/iOS backend에 주입 가능. UI가 shader 상수나 GPU 자원 수명 관리 안 함 |
| CAP-001 | P0 | preview와 high-resolution capture 분리 | still 입력 해상도로 재렌더. preview 스크린샷 확대 금지. 12MP 지원 기기에서 12MP 경로 검증 |
| CAP-002 | P0 | 셔터 상태 snapshot 및 안전한 저장 | material/seed/pose/depth policy를 고정하고 부분 파일 미노출. 실패 시 재시도 가능, 성공 파일 decode 가능 |
| PERF-001 | P0/P1 | 실시간·고해상도 예산 충족 | 12절 기기별 p50/p95·발열·메모리 결과 첨부, 해당 등급 기준 통과 |
| NFR-001 | P0 | 온디바이스 개인정보 보호 | 카메라·depth·사진을 기본 네트워크 전송하지 않음. 불필요한 위치·마이크 권한 요청 없음 |
| NFR-002 | P0 | 수명·오류·접근성 | 백그라운드/복귀 50회, 저장 실패·메모리 부족 시험 통과. 셔터 접근성 이름·포커스·상태 안내 |

## 4. 전체 아키텍처

```text
Application / UI / CaptureCoordinator
          │
          ├── AndroidCameraAdapter / IOSCameraAdapter
          │       └── CameraFrame + CameraGeometry + ColorMetadata
          ├── DepthSource: Constant / Hardware / Estimated
          │       └── synchronized, registered DepthFrame
          ├── MaterialRepository → validated Calibration JSON
          └── immutable RenderSnapshot
                         │
                  GlassRenderer
                         ├── glass transform / cell model
                         ├── procedural height → gradient → normals
                         ├── entry intersection → Snell → exit intersection → Snell
                         ├── scene/depth intersection → camera sample coordinates
                         ├── RGB dispersion / Fresnel / ReflectionSource
                         └── imperfections / linear-light composite / output transfer
                                     │
                      GraphicsBackend: Metal / Android GLES
                             ┌───────┴────────┐
                          Preview        Capture render
                                          → encode → photo storage
```

Glass Domain의 광학 수식·재질·좌표 계약은 플랫폼 비종속으로 유지한다. 공통 CPU reference와 동일한 golden fixture를 두 shader backend의 기준으로 삼는다. 기본 구현 선택은 iOS Metal, Android OpenGL ES 3.x이며 Android Vulkan은 측정상 필요할 때 backend로 추가한다. UI 프레임워크는 도메인 계약에 영향을 주지 않는다. SDK/library 버전은 구현 저장소에서 고정한다.

프리뷰는 latest-frame-wins, 대기 RGB 프레임 최대 2개로 latency 누적을 방지한다. GPU texture와 CPU buffer 수명은 fence/완료 callback으로 관리한다. preview 전체 프레임 CPU readback은 금지하고, 캡처 인코딩 및 진단에 필요한 readback만 허용한다. color conversion은 native YUV 범위·matrix·transfer metadata를 따른다.

## 5. 좌표, 단위, 셀 모델

### 5.1 표준 좌표

도메인 길이 단위는 meter, 각도는 radian, IOR은 무차원이다. JSON의 Mm/Deg 접미사가 있는 필드는 loader에서 한 번만 변환한다. 카메라 좌표는 x 오른쪽, y 아래, z 전방인 right-handed 좌표로 통일한다. pinhole 중심 O=(0,0,0)에서 scene 방향으로 역방향 ray를 추적한다. 광학 가역성에 근거한 tracing이며 실제 광자는 반대 방향으로 이동한다.

픽셀 p=(i+0.5,j+0.5,1)에 대해 d=normalize(K⁻¹p). K는 현재 입력 이미지의 crop·scale·회전을 반영한 intrinsics다. 미러는 명시된 display/output transform 단계에서 적용하며 glass 좌표를 임의 반전하지 않는다. 유리의 기본 자세는 카메라에 고정된 평면이며 AR world anchoring은 범위 밖이다.

CameraGeometry는 raw sensor→rectified image→crop→display/output 변환을 제공한다. rectified 렌더 공간과 원본 sampler 사이의 lens distortion mapping을 보존한다. lens correction을 두 번 적용하지 않는다. intrinsics를 FOV로 추정한 기기는 geometryQuality=estimated로 기록하고 정확 교정 기기와 구분한다.

### 5.2 유리 좌표와 물리적인 셀

T_cameraFromGlass는 유리 local 좌표를 camera 좌표로 변환한다. 기본 유리 front 기준 평면은 카메라 전방 0.08m에 둔다. 이는 초기 UX 값이며 실제 촬영 지그에서 camera-to-glass 거리를 측정해야 한다. 유리 자세는 재질 자체의 물성에 포함하지 않고 RenderSnapshot의 scene 설정으로 관리한다.

local 위치 (x,y)에 대해 g=((x-originX)/pitchX,(y-originY)/pitchY), cellID=floor(g), q=fract(g)-0.5. q 범위는 [-0.5,0.5)이며 음수 좌표에도 floor 규칙을 적용한다. pitch는 meter, 셀 ID는 signed integer다. 높이를 미분할 때 q 기준 미분을 pitch로 나누어 meter 기준 gradient로 변환한다.

화면에 셀 개수를 고정하고 싶은 UX는 pitch·pose·FOV에서 계산되는 별도 preset으로 표현한다. render 해상도가 바뀌었다고 물리 pitch를 변경하지 않는다. 정사각 셀이 화면 aspect ratio 때문에 직사각형으로 찌그러지지 않아야 한다.

## 6. QUADRA procedural surface와 제조 편차

### 6.1 실행 가능한 초기 height field

local front/back 표면을 z_f(x,y)=h_f(x,y), z_b(x,y)=t0+h_b(x,y)로 정의한다. t0는 기준 두께이며 실제 국소 z 두께는 z_b-z_f다. 초기 모델은 카메라 쪽 평면 front와 scene 쪽 요철 back을 사용한다. 실물의 요철 방향이나 양면 형상이 다르면 측정 결과로 교체한다. 동일 normal을 두 경계에 복사하지 않는다.

다음 함수는 초기 basis이며 특정 실물 QUADRA의 측정 형상이라고 주장하지 않는다.

```text
u,v = 2 × rotate(-cellRotation, q - cellCenterOffset)
u,v = u/shapeScaleX, v/shapeScaleY
r = (abs(u)^n + abs(v)^n)^(1/n)
a = clamp(r, 0, 1)
S(a) = 6a^5 - 15a^4 + 10a^3
H_core = amplitudeM × (1-S(a))^curvaturePower

bx = clamp((0.5-abs(q.x))/edgeWidthCell, 0, 1)
by = clamp((0.5-abs(q.y))/edgeWidthCell, 0, 1)
W = S(bx) × S(by)
B(b) = 64b^3(1-b)^3
H_edge = edgeAmplitudeM × (B(bx)S(by) + B(by)S(bx))
H_cell = W × H_core + H_edge
```

초기 fitting n 범위는 4~8, 사용자 지원 범위는 2~8이며 curvaturePower≥1, edgeWidthCell∈(0,0.25]를 사용한다. 경계에서 H_edge의 값과 1차 미분을 0으로 만들고 W로 편차를 소멸시킨다. r=0의 gradient는 연속 극한인 0이다. 이전 min(edgeX,edgeY) 함수는 셀 안쪽 대각선에 미분 분기를 만들 수 있으므로 surface 생성에서 제외하고 edge mask 분류에만 사용한다. 새 tensor-product 함수도 실측 형상을 증명하지 않으며, fitting 실패 시 주기적 spline 또는 계측 height field로 교체한다. 임의 UV offset으로 오차를 숨기지 않는다.

국소 두께 최소값 0.5mm 이상, front/back 비교차, 표면 기울기 유한성을 loader와 샘플링 검사로 보장한다. 전체 표면은 셀 경계에서 적어도 C1 연속을 목표로 하고, 허용 수치 오차는 height 1µm, gradient 1e-3이다. 피사체 상의 급격한 변화는 곡률 및 광선 매핑에서 발생해야 하며 높이 균열로 만들지 않는다.

### 6.2 Surface normal

```text
gradH = (∂H/∂x, ∂H/∂y)
N_positiveZ = normalize(-gradH.x, -gradH.y, 1)
```

front와 back 각각 계산한 뒤 매 경계에서 N·incident≤0이 되도록 normal을 orient한다. analytic derivative를 기본으로 하고 CPU 기준은 중앙차분을 쓴다. 중앙차분 step은 pitch의 1e-3에서 시작해 수렴을 확인하며 pixel 크기에 종속시키지 않는다. normal map/LUT는 height field에서 만든 캐시이며 material hash·모델 버전·정밀도·seed를 cache key에 포함한다.

### 6.3 Deterministic manufacturing variation

cellID와 uint32 seed의 정수 hash로 curvature ±6%, height ±3%, center offset 각 축 ±1% pitch, rotation ±0.5°를 초기 범위로 둔다. 이 수치는 관찰 전 개발값이다. hash 알고리즘·unsigned overflow·음수 ID의 bit 표현을 명세 및 golden vector로 고정한다. GPU sin 기반 hash나 프레임 시간 random은 사용하지 않는다.

pitch 자체를 셀마다 무작위로 바꿔 tiling 균열을 만들지 않는다. variation을 연속 surface에 적용하고 필요 시 저주파 thickness noise를 추가한다. 여러 셀의 실측 분포에서 variance를 추정하며 임의 seed가 실물 셀 각각과 동일하다고 주장하지 않는다. 샘플별 일치가 필요하면 검증된 cell override를 별도 calibration 데이터로 보관한다.

## 7. 광학 모델

### 7.1 교차와 Snell 이중 굴절

1. camera ray를 glass local 공간으로 변환하고 front height surface와의 최초 양의 교차 P1을 구한다.
2. Air→Glass 굴절로 d1을 구한다.
3. P1+εd1에서 출발하여 back surface의 최초 유효 교차 P2를 구한다. 일정 z 두께를 ray 길이로 오인하지 않는다.
4. Glass→Air 굴절로 d2를 구한다.
5. P2와 d2를 camera 공간으로 변환하고 scene과 교차시켜 입력 카메라 영상의 sample 위치를 구한다.

```text
I: 진행 방향 unit vector, N: 입사 방향을 마주 보는 unit normal
eta = n_incident / n_transmitted
c = clamp(-dot(N,I), 0, 1)
k = 1 - eta²(1-c²)
if k < 0: total internal reflection (TIR)
T = normalize(eta I + (eta c - sqrt(k)) N)
```

첫 경계 eta=nAir/nGlass, 두 번째 eta=nGlass/nAir다. 초기 nAir=1.0003, nGlass=1.52, 탐색 범위 1.45~1.60, t0 초기 탐색 범위 3~15mm다. 이 범위는 제품의 실제 사양을 뜻하지 않으며 계측 결과가 우선한다. 굴절·Fresnel 물리 기준은 [PBRT의 Specular Reflection and Transmission](https://www.pbr-book.org/4ed/Reflection_Models/Specular_Reflection_and_Transmission)을 참고한다.

surface intersection은 height bound와 cell traversal로 후보 구간을 찾고 최초 교차부터 safeguarded Newton/bisection으로 해결한다. 구간 끝의 부호만으로 접선 교차·다중 root를 배제하지 않는다. 초기 반복 예산 preview 8회·capture 16회는 시작값이며 reference는 수렴까지 계산한다. surface residual 10µm만으로 합격하지 않고 reference 대비 source sampling 오차를 capture p95≤0.1px, preview p95≤0.25px로 확인한다. 단위는 해당 출력 크기에 대응하는 pixel이다. ray origin ε는 scale/FP 정밀도로 정하고 self-intersection·얇은 표면 건너뜀을 시험한다. 비수렴 목표≤0.1%이며 TIR·화면 밖·scene miss와 구분한다. NaN ray sampling은 금지한다. P0 TIR은 명시된 reflection fallback, P1은 reflection weighting을 사용한다. 실시간 다중 내부 반사는 기본 제외하되 17절 reference에서 생략 오차를 측정한다. 측정된 재질의 교차를 풀지 못하면 solver 또는 지원 도메인을 수정한다.

### 7.2 ConstantDepth와 camera sampling

ConstantDepth의 값 Z는 카메라 optical center 기준 camera-z plane 거리이며 기본 1.2m다. Z>P2.z이어야 한다.

```text
s = (Z-P2.z)/d2.z
Q = P2 + s d2
p_sample = project(K,Q)  // rectified source pixel
uv_sample = rectifiedToSource(p_sample)
```

d2.z≤0 또는 s≤0은 invalid다. no-glass 위치와의 차이를 pixel displacement로 기록한다. 먼 장면에서 유리 뒤의 물리적 횡변위가 증가할 수 있지만 화면 pixel displacement가 거리에 선형 비례하거나 항상 커진다는 규칙은 적용하지 않는다. 원근투영과 평판의 평행 출사 효과를 포함한 계산 결과를 따른다. 과거 설명의 ‘멀수록 더 크게 이동’은 일반적인 pixel 규칙으로 채택하지 않는다.

### 7.3 Depth-aware refraction

DepthFrame은 camera-z meter를 표준으로 쓴다. range 또는 disparity 센서는 intrinsics·extrinsics·scale을 이용해 변환한다. source RGB에 정렬된 depth에서 Q(s)의 투영 위치 깊이와 Q.z의 차를 계산하여 scene 교차를 탐색한다. 초기 구현은 constant plane hit로 시작한 4~8회 제한 ray marching/root refinement이며 confidence가 있는 첫 가시 교차를 선택한다. depth discontinuity를 가로질러 값을 평균하지 않는다.

고해상도 depth를 만들어낸다고 가정하지 않는다. 저해상도 depth를 edge-aware upsampling하고 불확실성을 유지한다. 장면 가림 해제·화면 밖 영역은 원 영상에 없는 색이므로 실제 복원이 불가능하다. 작은 hole은 같은 표면의 인접 valid sample, 큰 hole은 ConstantDepth 재추적, source 바깥은 clamp-to-edge와 부드러운 edge attenuation을 초기 정책으로 사용한다. invalid 비율과 fallback 종류를 로그에 남긴다. 피부·눈·털이 전경 경계에서 길게 끌리지 않는지 검증한다.

### 7.4 RGB chromatic dispersion

P1은 nR≤nG≤nB인 정상 분산 초기 모델을 사용한다. 각 채널에 대해 두 경계의 굴절·표면 교차를 다시 계산하고 각각 해당 채널을 샘플링한다. 파장별 측정값이 없으면 nR=nG=nB를 기본으로 하며 색 테두리를 임의 strength로 추가하지 않는다. 세 IOR은 calibration JSON에서 관리한다. green ray 기준 미분 근사는 reference 대비 허용 오차를 만족할 때만 preview 최적화로 허용한다.

### 7.5 Fresnel·reflection approximation

P1 reference/capture는 비편광 dielectric Fresnel 정확식을 기본으로 사용한다. Snell의 cosθi, cosθt를 재사용하여 Rs=((n1 cosθi-n2 cosθt)/(n1 cosθi+n2 cosθt))², Rp=((n1 cosθt-n2 cosθi)/(n1 cosθt+n2 cosθi))², F=(Rs+Rp)/2로 계산한다. grazing limit와 TIR은 F=1로 안정 처리한다. Schlick F0=((n1-n2)/(n1+n2))², F=F0+(1-F0)(1-cosθi)^5는 preview에서 측정상 이득이 있고 OPT-008을 통과할 때만 허용한다. 임계각 근처를 제외하여 합격시키지 않는다.

첫 반사만 단순 합성할 때 전송 가중치는 T=(1-F1)(1-F2)A, 첫 표면 반사 R=F1, A는 Beer–Lambert absorption이다. C=T·Cscene+R·Creflection으로 합성한다. 생략한 내부 반사 에너지를 임의 밝기 증폭으로 보상하지 않으며 T+R≤1을 유지한다. absorption coefficient 단위는 m⁻¹, A=exp(-sigmaA·length(P2-P1)). 색 합성은 linear RGB에서 수행하고 출력에 한 번만 transfer/tone mapping을 적용한다.

ReflectionSource는 none, lowFrequencyCamera, environmentMap을 분리한다. 실물 비교 reference는 별도로 촬영한 camera-side environmentMap 또는 검은 차광막을 사용한다. 계측 환경이 없는 optical-validation 모드는 none을 쓰고 Fresnel transmission 감소는 유지한다. 사용자 이미지의 시각 목표를 위한 reference-look 모드는 18절의 명시적인 environment/light preset으로 반사·하이라이트를 제공하며 현재 환경의 정확한 복원이라고 주장하지 않는다. lowFrequencyCamera는 실물과 무관한 무늬를 만들 수 있으므로 사용자 옵션에만 두고 calibrated 기준에서 제외한다. 검증용 재질과 시각 프리셋의 provenance를 분리한다.

### 7.6 Imperfections

micro scratch, dust, smudge, thickness noise, surface roughness를 독립 amplitude와 seed로 제어한다. thickness 변화는 height field에, 미세 형상은 gradient/roughness에, dust/smudge는 투과·산란 근사에 적용하여 중복 효과를 막는다. 모두 glass 좌표에 고정하고 해상도별 anti-aliasing 및 bandwidth 제한을 적용한다. 강도 0 baseline을 항상 제공하며 실측되지 않은 결함의 calibrated 기본값은 0이다.

## 8. DepthSource 정책

| Source | 입력·계약 | 선택 및 fallback |
|---|---|---|
| Constant | camera-z meter 상수, confidence를 measured로 표시하지 않음 | 모든 기기에서 P0 기본, invalid depth의 최종 fallback |
| Hardware | 센서 depth/disparity, intrinsics/extrinsics, timestamp, mask | RGB와 동시 사용이 검증된 기기·렌즈에서 우선 |
| Estimated | 온디바이스 ML depth와 confidence, metric scale 정보 | hardware 미지원 시 사용. 상대 깊이만 있으면 scale 검증 전 Constant 유지 |

자동 선택은 Hardware→metric Estimated→Constant 순서다. Depth-RGB timestamp 차는 preview 기본 허용 33ms, capture 50ms이며 이를 넘으면 stale로 처리한다. valid 영역 비율 70% 미만이 5프레임 연속이면 전체 fallback으로 전환한다. 복귀는 30프레임 연속 정상 후 200ms 동안 sample displacement를 완만하게 전환한다. 전환 중에도 각 endpoint는 물리 trace 결과여야 한다. pixel confidence cutoff는 source별 validation에서 정하고 capability profile에 기록한다.

Estimated depth 추론은 별도 제한 큐에서 실행하고 목표 15Hz 이상, RGB 렌더링을 기다리게 하지 않는다. 동기화·motion 보정이 불확실하면 이전 depth를 무기한 재사용하지 않는다. 전후면·렌즈 전환 시 depth history와 intrinsics cache를 폐기한다.

## 9. Calibration JSON SSOT와 API

### 9.1 JSON 예시 — 실측값 아님

다음 블록은 loader/fixture 구현용 prototype 예시다. 이전 대화의 1.518, 7.4mm, 22.1mm 등의 예시 수치도 실물 측정으로 승격하지 않는다. 아래 값으로 제품 정확성을 주장하지 않는다.

```json
{
  "schemaVersion": "1.0.0",
  "materialId": "quadra-prototype-v1",
  "modelVersion": "superellipse-boundary-v2",
  "status": "prototype",
  "sample": { "manufacturer": null, "sku": null, "lot": null, "orientation": "flat-front" },
  "optical": {
    "iorAir": 1.0003,
    "iorRGB": [1.52, 1.52, 1.52],
    "baseThicknessMm": 7.0,
    "minThicknessMm": 0.5,
    "absorptionPerM": [0.0, 0.0, 0.0]
  },
  "cell": { "pitchMm": [22.0, 22.0], "originMm": [0.0, 0.0] },
  "surface": {
    "front": { "model": "plane", "heightMm": 0.0 },
    "back": {
      "model": "superellipse-boundary-v2",
      "exponent": 6.0,
      "heightMm": 1.0,
      "curvaturePower": 1.0,
      "shapeScale": [1.0, 1.0],
      "edgeWidthCell": 0.08,
      "edgeAmplitudeMm": 0.10
    }
  },
  "variation": {
    "seed": 20260920,
    "hashVersion": "uint32-v1",
    "curvatureFraction": 0.06,
    "heightFraction": 0.03,
    "centerOffsetCell": 0.01,
    "rotationDeg": 0.5
  },
  "imperfections": {
    "seed": 17,
    "roughness": 0.0,
    "scratchStrength": 0.0,
    "dustStrength": 0.0,
    "smudgeStrength": 0.0,
    "thicknessNoiseMm": 0.0
  },
  "calibration": {
    "datasetId": null,
    "datasetSha256": null,
    "distancesMm": [200, 500, 1000, 2000],
    "distanceReference": "glass-back-base-plane",
    "fitToolVersion": null,
    "validationReportId": null,
    "validationMetrics": null
  }
}
```

JSON Schema를 코드로 작성하고 unknown major version, NaN/Infinity, 음수 두께, invalid pitch, 범위 밖 seed, 비지원 model/hashVersion을 거부한다. minor extension의 무시 가능 여부를 명시한다. calibrated 상태는 실제 sample identity·dataset hash·fitting version·validation report·metrics가 모두 있어야 허용한다. 예시 hashVersion은 구현 시 알고리즘과 golden vector를 함께 등록해야 한다.

같은 material ID/version의 내용을 덮어쓰지 않는다. canonical JSON의 SHA-256을 계산해 capture metadata와 캐시 key에 기록한다. 손상된 asset은 last-known-good 재질로 복구하고 진단 이벤트를 남긴다. calibration JSON은 표면·물성만 소유하며 camera pose, exposure, quality tier, reflection 근사 선택은 RenderSnapshot/runtime policy가 소유한다.

### 9.2 사용자 override 계약

MaterialControlSchema는 각 조절 항목의 material path, 단위, min/max/step, UI 이름, 매핑 방식을 소유하는 versioned 자산이다. UI와 validator는 같은 schema를 사용하고 범위를 중복 하드코딩하지 않는다. 기본값은 calibration JSON에서 읽는다. 보정값이 UI 범위 밖이면 preset 로딩 전에 control schema를 호환되게 갱신하거나 편집 미지원 상태를 명시하며 조용히 clamp하지 않는다.

```typescript
interface UserMaterialOverrides {
  baseMaterialHash: string;
  controlSchemaVersion: string;
  baseThicknessMm?: number;
  backHeightMm?: number;
  cellPitchMm?: readonly [number, number];
  backExponent?: number;
  backEdgeAmplitudeMm?: number;
}

interface MaterialResolver {
  resolve(base: GlassMaterial, overrides: UserMaterialOverrides):
    { ok: true; material: GlassMaterial; effectiveHash: string } |
    { ok: false; parameter: string; reason: string };
}
```

resolver는 공개 단위를 SI로 변환하고 variation까지 포함한 최종 surface의 제약을 검사한다. 정상 결과만 GlassRenderer.setGlassMaterial에 전달한다. hash는 유효 물성·형상·seed·모델 버전의 canonical 표현으로 계산하므로 동일 설정은 같은 hash를 갖는다. 빈 override 또는 원본과 같은 값은 base material과 같은 effective hash를 반환한다. 사용자 조절 여부는 별도 provenance로 보존한다. 원본 복원 시 calibrated 표시는 원본이 calibrated일 때만 복구한다.

### 9.3 플랫폼 중립 API 계약

아래는 언어 선택과 무관한 TypeScript 형태의 계약이다. TextureHandle 등은 backend가 소유하는 opaque handle이며, 구현 시 구체 타입으로 정의한다.

```typescript
interface GlassMaterial {
  readonly id: string;
  readonly schemaVersion: string;
  readonly modelVersion: string;
  readonly contentHash: string;
  readonly optical: OpticalProperties; // SI로 변환된 물성
  readonly surface: GlassSurface;
  readonly cell: CellGeometry;
  readonly variation: CellVariationProfile;
  readonly imperfections: ImperfectionProfile;
}

interface CameraFrame {
  texture: TextureHandle;
  timestampNs: bigint; // 공통 monotonic clock으로 변환
  geometry: CameraGeometry;
  color: ColorMetadata;
  releaseAfterGpuComplete(): void;
}

interface DepthFrame {
  depthMeters: TextureHandle; // camera-z, RGB rectified 공간
  confidence: TextureHandle;
  validMask: TextureHandle;
  timestampNs: bigint;
  source: "constant" | "hardware" | "estimated";
  metricScaleValidated: boolean;
  registration: DepthRegistration;
}

interface DepthSource {
  capabilities(): DepthCapabilities;
  acquireFor(frame: CameraFrame): DepthFrame | null;
  reset(): void;
  dispose(): void;
}

interface ReflectionSource {
  acquireFor(frame: CameraFrame): ReflectionFrame | null;
  approximation: "none" | "lowFrequencyCamera" | "environmentMap";
}

interface GlassRenderer {
  setGlassMaterial(material: GlassMaterial): void;
  setDepthSource(source: DepthSource): void;
  setReflectionSource(source: ReflectionSource): void;
  renderPreview(frame: CameraFrame, snapshot: RenderSnapshot,
                target: RenderTarget): RenderReceipt;
  renderCapture(frame: CameraFrame, snapshot: RenderSnapshot,
                target: RenderTarget): Promise<RenderReceipt>;
  dispose(): void;
}
```

RenderSnapshot은 immutable이며 baseMaterialHash, effectiveMaterialHash, UserMaterialOverrides, seed, glassPose, cameraGeometry, depth selection/fallback, reflection policy, quality tier, output crop/mirror, capture timestamp를 포함한다. render는 공유 mutable 설정을 다시 읽지 않는다. RenderReceipt에는 사용 재질 hash, 실제 입력·출력 크기, depth source/age, fallback 비율, GPU 시간, warning/error를 담는다.

renderer 상태는 한 render queue에서 직렬화한다. setter는 다음 snapshot부터 반영하며 진행 중 capture를 변경하지 않는다. unsupported format/material, surface miss, depth unavailable, context loss, out-of-memory, encode/storage failure는 분리된 typed error로 반환한다. depth unavailable 자체는 정상 fallback 경로이며 촬영 실패로 보지 않는다.

## 10. Android/iOS adapter와 preview/capture

| 영역 | Android | iOS |
|---|---|---|
| 카메라 | CameraX Preview·ImageCapture 중심, 필요한 메타데이터/깊이는 검증된 Camera2 adapter | AVFoundation video/photo output |
| GPU | OpenGL ES 3.x backend; Vulkan은 후속 선택 | Metal backend |
| 입력 | GPU surface/YUV와 crop/rotation/color metadata | CVPixelBuffer·Metal texture와 calibration metadata |
| 깊이 | 실제 device capabilities와 동시 스트림 지원 검사 | 지원 구성에서 AVDepthData 및 photo depth |
| 저장 | MediaStore와 원자적 완료 처리 | Photos의 필요한 최소 권한과 저장 완료 처리 |

CameraX 지원 해상도와 동시 use case 조합은 기기별로 협상한다. [CameraX configuration](https://developer.android.com/media/camera/camerax/configuration), [CameraX architecture](https://developer.android.com/media/camera/camerax/architecture)를 구현 기준으로 확인한다. Android depth는 모든 기기에 존재하지 않으므로 [CameraCharacteristics](https://developer.android.com/reference/android/hardware/camera2/CameraCharacteristics)의 capability를 확인한다. iOS는 [AVDepthData](https://developer.apple.com/documentation/avfoundation/avdepthdata)와 [AVCapturePhoto.depthData](https://developer.apple.com/documentation/avfoundation/avcapturephoto/depthdata)의 좌표·왜곡·가용성을 처리한다. AR depth 라이브러리와 별도 camera session의 동시 사용을 지원된다고 가정하지 않는다.

초기 지원 기준은 Android 10+ 및 GLES 3.0, iOS 16+ 및 Metal 지원 기기로 제안한다. 이는 API 존재만으로 성능을 보장하는 선언이 아니다. M0에서 실제 최소·중간·상위 기기를 지정하고 OS/SDK 지원표를 고정한다. 특정 렌즈의 hardware depth 미지원은 전체 앱 미지원 사유가 아니다.

### 10.1 Preview

기본 내부 렌더 해상도는 최대 1920×1080 상당, 30fps다. low tier는 1280×720 상당을 허용한다. sensor→display의 aspect/crop transform을 보존한다. 셀 크기·seed·pose는 프레임 해상도 변화에 영향받지 않는다. superellipse와 고주파 결함은 footprint에 맞춰 anti-aliasing한다.

### 10.2 High-resolution capture

1. 셔터 시점에 재질과 scene 설정을 snapshot으로 고정한다.
2. native still 요청으로 실제 지원 사진 해상도를 받는다. 해상도 협상 결과를 metadata에 기록한다.
3. 해당 still의 intrinsics/crop/orientation/color와 동기 depth를 사용한다. preview depth를 timestamp·등록 확인 없이 붙이지 않는다.
4. still 입력을 optical model에 다시 넣어 native 해상도로 렌더링한다. 4032×3024 입력이면 해당 해상도로 계산하며 preview 확대를 금지한다.
5. JPEG sRGB를 P0 기본으로 저장하고 HEIC는 capability·색 검증 후 추가한다. EXIF 방향을 pixels 또는 tag 중 한 곳에서만 적용한다. 위치정보는 사용자 opt-in 없이는 넣지 않는다.

메모리 부족 시 output tile rendering을 허용한다. 각 tile은 전체 이미지 좌표와 동일 material을 쓰고, source sample이 tile 밖으로 굴절될 수 있으므로 전체 source 접근 또는 conservative displacement halo를 확보한다. tile 경계에서 셀 origin을 재설정하지 않는다. 동일 프레이밍으로 downsample한 capture와 preview의 ray mapping 차이 p95≤0.5 preview pixel을 목표로 한다. 실제 연속 프레임 사이의 움직임·노출 차이를 이 지표에 섞지 않고 동일 fixture로 검증한다.

capture queue는 기본 1개다. 처리 중 셔터 상태를 표시하고 GPU 자원을 제한하여 프리뷰 정지가 길어지지 않게 한다. 다른 aspect ratio 사진을 저장할 경우 촬영 전 최종 crop 영역을 표시한다. 전면 기본은 보이는 대로 저장하며 사용자가 선택한 mirror 정책을 preview/capture에 동일 적용한다.

## 11. 실물 QUADRA 캘리브레이션

### 11.1 촬영 및 데이터 계약

카메라·유리·pattern을 고정하는 지그를 사용한다. 유리만 제거/삽입하여 camera와 pattern을 움직이지 않고 reference(유리 없음)와 distorted(유리 있음)를 촬영한다. checkerboard 칸 크기를 mm로 측정하고 유리 pitch·기준 두께·요철 면·camera-to-glass 거리·기울기를 별도로 측정한다. focus, exposure, white balance, lens, zoom, stabilization 설정을 쌍 내부에서 고정한다. ISP 차이와 렌즈 왜곡을 교정하고, 기하 fitting 때 반사·포화·motion blur를 mask한다.

glass back 기준 평면→checkerboard 평면의 optical-axis 거리를 D=0.20/0.50/1.00/2.00m로 설정한다. 해당 거리는 DepthSource의 camera-z와 다르다. 지그의 front 거리와 t0, pose를 포함해 camera-z로 변환한다. 측정 오차 목표는 D ±1mm, 유리 pitch·두께 ±0.1mm이며 실제 장비 정밀도를 메타데이터에 기록한다.

거리별 최소 3회 paired repeat, checkerboard를 알려진 위치로 이동한 3개 phase, 최소 5×5개의 완전한 유리 셀을 확보한다. 최소 36쌍이며 반복·phase·거리 ID를 보관한다. 촬영 실패는 데이터 수에 포함하지 않는다. 초점·기울기·조명별 확장 데이터는 추가로 수집한다. 반사·roughness fitting용으로 알려진 조명 환경과 균일 배경을 별도 촬영한다.

각 pair manifest에는 dataset/sample/pair ID, 파일 hash, timestamp, resolution, K/distortion/crop, glass pose, D와 측정 불확실성, exposure/focus/WB, checker square 크기, mask, split을 저장한다. 원본과 보정본을 구분하고 개인 사진은 동의 없는 calibration 데이터로 사용하지 않는다.

### 11.2 Optical flow와 displacement field

캘리브레이션 기준은 inverse sampling map이다. distorted pixel p가 reference의 어느 위치 q를 읽는지 B(p)=q-p로 정의한다. renderer의 p_sample-p와 직접 비교한다. reference→distorted forward flow F(q)를 구한 경우 q+F(q)=p이므로 일반적으로 B(p)=-F(p)가 아니다. 역매핑·confidence 처리 또는 distorted→reference flow를 직접 계산한다.

checkerboard corner correspondence를 먼저 잡고 dense optical flow를 보조로 사용한다. 반복 무늬 오대응은 coded border·고유 마커·여러 phase와 forward/backward consistency로 제거한다. [OpenCV optical flow API](https://docs.opencv.org/4.13.0/dc/d6b/group__video__track.html)를 구현 도구로 사용할 수 있으나 flow 자체를 ground truth로 무조건 신뢰하지 않는다. 셀 경계·상 겹침·가림 영역은 confidence를 낮추거나 제외하고 별도 지표로 보고한다.

유리 삽입으로 카메라가 이동한 경우 전역 정합을 먼저 검증한다. 굴절 자체를 homography로 제거하지 않도록 외부 고정 마커로 pose 이동을 추정한다. flow는 native pixel 단위, 같은 rectified camera 좌표에서 저장한다. 셀 평균은 phase 정합 후 수행하며 평균과 cell별 variance를 모두 유지한다.

### 11.3 Parameter fitting

물성·shape와 camera pose가 서로 보상하는 비식별성을 제한한다. pitch·두께·camera-to-glass 거리·K를 먼저 계측해 고정 또는 강한 prior로 사용한다. IOR과 height를 동시에 무제약 최적화하지 않는다. 다음 순서로 fitting한다.

1. camera intrinsics/distortion, pattern pose, 유리 grid origin·pitch·orientation 정합.
2. 공통 평균 shape의 height, exponent, curvaturePower, edge profile 최적화.
3. 계측 prior 안에서 IOR·t0 미세 조정, 다중 거리 공동 fitting.
4. cell별 residual에서 variation 분포 또는 sample override 추정.
5. 별도 radiometric 데이터로 RGB IOR·absorption·roughness·reflection 근사 조정.

```text
L = λflow × mean_D [ Σp w(D,p) ρ(Bsim(D,p)-Bobs(D,p)) / Σp w(D,p) ]
  + λcorner × robust corner reprojection loss
  + λphoto × masked linear-RGB photometric loss
  + λprior × measured-parameter uncertainty penalty
  + λsurface × continuity/thickness/slope constraints
```

ρ는 Huber loss를 사용하고 초기 delta는 1080p 환산 1px다. 거리별 동등 가중치를 기본으로 하여 유효 pixel 수가 많은 거리만 지배하지 않게 한다. 단계 1~3은 λphoto=0으로 시작한다. 모든 λ·bounds·optimizer seed·종료 조건·도구 버전을 기록한다. 반사 근사가 광학 shape 오차를 흡수하지 않도록 geometry와 radiometry fitting을 분리한다. 제약 위반은 hard reject한다.

각 거리에서 repeat/phase 단위로 train/validation/test를 60/20/20%에 가깝게 분할하되 pair 전체를 같은 split에 둔다. 작은 데이터에서 정확한 비율보다 독립 capture 확보를 우선한다. 인접 pixel 임의 분할은 금지한다. 추가 leave-one-distance-out 검증으로 미사용 거리 일반화를 보고한다. 최종 네 거리 재학습 후 독립 test pair는 fitting에 사용하지 않는다.

### 11.4 캘리브레이션 acceptance 목표

모든 displacement metric은 전체 이미지 긴 변 1920px로 정규화한 pixel 단위로 계산한다. EPE=||Bsim-Bobs||₂다. 전체 평균만이 아니라 각 거리와 core/edge 영역을 별도로 보고한다. edge는 e<edgeWidthCell로 정의한다.

| 지표 | P1 목표 |
|---|---|
| 거리별 유효 mask coverage | 전체 비교 ROI ≥70%, edge band ≥50%; 제외 사유와 map 제출 |
| 홀드아웃 EPE | 거리별 median≤1.5px, p95≤4px |
| edge band EPE | 거리별 p95≤6px |
| 단순 UV-offset baseline 대비 | 같은 test 데이터 mean EPE ≥30% 개선; baseline도 train에서만 fitting |
| 미사용 거리 검증 | mean EPE가 동일 거리 포함 모델 대비 25% 넘게 악화되지 않음 |
| 체커보드 외 자연 장면 | 눈·털·윤곽·배경을 포함한 최소 10개 정적 scene fixture 확인 |
| 블라인드 시각 평가 | 10명 이상×10개 paired scene에서 단순 UV baseline 대비 실물에 가까운 선택률 ≥70%; 신뢰구간도 보고 |

이 목표는 실측 결과가 없는 상태에서 정한 출시 목표다. 달성 불가 시 데이터 신뢰도→좌표 정합→surface family 순으로 원인을 분석한다. 필요하면 basis를 확장하고 버전을 올린다. 기준을 조용히 완화하거나 train 오차를 test 성능으로 보고하지 않는다. calibrated 승격은 graphics·CV·QA 담당자의 결과 검토를 필요로 한다.

## 12. 성능 목표 및 비기능 요구사항

### 12.1 측정 조건과 예산

M0에서 Android low/mid/high 최소 3대, iOS 최소 지원/최근 기기 최소 2대를 정하고 hardware depth 지원·미지원 구성을 모두 포함한다. release build, 고정 밝기, 실온 23±2°C, 충전하지 않는 상태, 2분 warm-up 후 10분 연속 프리뷰를 기본으로 한다. 각 기기·OS·렌즈·tier·재질·depth mode별 p50/p95, frame drop, GPU 시간, 메모리, thermal 상태를 남긴다. 센서 입력이 실제 30fps를 지원하는 노출 조건에서 측정한다.

| 항목 | 목표 |
|---|---|
| mid/high preview | 1080p 상당 30fps, 10분 평균 ≥29fps, p95 frame interval≤40ms, drop≤2% |
| low preview | 720p 상당 30fps, 같은 interval/drop 기준 |
| GPU rendering p95 | 1080p≤20ms, 720p≤16ms; P1 기능 포함 tier를 별도 기록 |
| 전체 camera-to-display latency p95 | ≤100ms; timestamp 추정과 외부 high-speed 측정 구분 |
| 첫 프리뷰 p95 | 권한 허용 완료 후 cold start≤2초; 권한 대화 시간 제외 |
| capture 12MP p95 | 셔터→저장 완료 mid/high≤3초, low≤5초; 20회 시험 |
| capture 중 preview 정지 | ≤300ms 목표, 불가한 native camera 구성은 별도 명시·지원 등급 조정 |
| process memory 목표 | preview≤250MiB, 12MP capture peak≤600MiB; OS 도구 측정 방식 기록 |
| 안정성 | background/resume 50회·capture 100회에서 crash/손상 파일 0, warm-up 이후 메모리 증가≤20MiB |

렌더 단계별 시간 합산이 실제 병렬 파이프라인 end-to-end latency를 대신하지 않는다. estimated depth 추론 시간·주기·열 비용을 별도로 보고한다. 12MP 미지원 기기는 최대 해상도를 보고하며 12MP 성능 통과로 분류하지 않는다.

### 12.2 적응 품질과 안정성

발열·GPU 시간 초과 시 imperfections sampling→reflection 해상도→dispersion 근사→preview 해상도 순으로 비용을 줄인다. 이중 굴절·두께·height 기반 normal·material seed는 유지한다. 마지막에는 알려진 720p fallback으로 전환하고, OS thermal critical에서는 저장을 마무리한 뒤 카메라를 안전하게 중지한다. 품질 복귀에 hysteresis를 둔다. capture는 preview tier를 무조건 상속하지 않고 별도 예산에서 reference에 가까운 품질로 실행한다.

개인정보: RGB/depth/사진은 기본 온디바이스 처리, telemetry에 이미지·위치·생체 추정값 금지. diagnostics export는 사용자가 명시적으로 선택한다. 저장·읽기 권한은 플랫폼의 최소 범위만 요청하고 마이크는 동영상 범위 확장 전에는 사용하지 않는다.

접근성: 셔터·전환·저장 상태의 screen reader label, 충분한 터치 영역, 상태를 색만으로 구분하지 않는 UI를 제공한다. 오류: 공간 부족·권한 철회·GPU context loss·카메라 interrupt·백그라운드 전환에서 자원을 해제하고 재진입을 지원한다. 저장 성공은 encoding 및 사진 저장소 완료 확인 후에만 표시한다.

재현성: 앱·shader·모델·JSON·dataset hash와 quality tier를 보고서에 남긴다. platform 간 bit-identical RGB는 요구하지 않지만 동일 ray map의 p95 차이≤0.25px, 동일 linear input의 RGB MAE≤1/255를 golden fixture 기준 목표로 한다. 작은 색차와 기하 오류를 분리해 판정한다.

## 13. 검증 전략과 필수 fixture

| 시험 | 조건 | 기대 결과 |
|---|---|---|
| Identity | 양면 평면, absorption/reflection off, nGlass=nAir | 원 입력과 mapping≤0.1px 차이 |
| Parallel slab | 두 평행 표면, nGlass>nAir, 경사 입사 | 출사 ray가 입사 ray와 평행, lateral shift는 CPU 해석값과 일치 |
| Normal incidence | 평면에 수직 ray | 횡변위 0, 불필요한 색수차 없음 |
| Thin flat slab | 평면 t→0 | displacement→0; 요철 두께 제약은 별도 |
| Snell/TIR | 알려진 각도·IOR | n1 sinθ1=n2 sinθ2 오차≤1e-5, TIR 시 invalid sqrt 없음 |
| Gradient | core·edge·corner·음수 cell ID | 6절 continuity 및 OPT-003 각도 기준 통과 |
| Constant vs plane depth | 같은 Z plane texture | 두 tracing 경로 map 차이 p95≤0.25px |
| Depth discontinuity | 전경 0.5m/배경 2m, hole·stale·scale 오류 | 경계 혼합 억제, fallback mask·source 정상 |
| Seed·resolution | 동일 frame·material 반복 및 해상도 변경 | 패턴 고정, source coordinate 기준 일치 |
| Capture tiles | tiled/untiled 동일 still | tile 경계 오차≤1/255, ray map≤0.1px |
| Preview/capture | 동일 source·FOV·crop | 10절 p95≤0.5 preview pixel |
| Cross-platform | 동일 linear texture와 K/JSON | 12절 mapping/color 허용 오차 통과 |
| Range controls | 항목별 min/default/max·step·직접 입력, 조합 경곗값 및 고정 seed 무작위 200조합 | 유효 조합은 NaN/표면 교차 없이 렌더, invalid는 마지막 유효값 보존. 동일 물성이 양 플랫폼에 적용 |
| Range persistence/capture | 드래그→셔터→추가 변경→재실행→전체 초기화 | capture snapshot 고정, 설정 복원, 원본 hash 복귀, preview/capture mapping 기준 통과 |
| Range responsiveness | 지원 기기별 30초 연속 드래그 | 입력 지연 p95≤100ms 및 기존 tier frame/drop 기준 유지, shader 재컴파일·카메라 재시작 없음 |
| Real sample | 네 거리 독립 paired data | 11절 품질 게이트 통과 |

CPU reference는 double precision 기준으로 만들고 GPU 결과와 displacement/normal/mask를 비교한다. reference가 production shader를 그대로 호출하도록 만들어 동어반복 시험이 되지 않게 한다. flat slab·Snell 시험은 별도 해석식으로 검증한다. identity/flat slab에서 reflection을 끄는 조건과 실제 제품 reflection 설정을 구분한다.

개발 진단 뷰는 cell ID, height, normal, entry/exit point, thickness, ray direction, sample UV, displacement magnitude, depth confidence/age, invalid 이유, Fresnel F1/F2, GPU timing을 제공한다. 시각 결과가 틀릴 때 RGB만 보고 파라미터를 조정하지 않는다.

## 14. 단계별 구현 순서와 완료 조건

| 단계 | 구현 및 산출물 | 의존성 | 완료 조건 |
|---|---|---|---|
| M0 계약·실물 준비 | 지원 기기표, 좌표/단위 fixture, JSON Schema, 샘플·지그·데이터 계획 | 없음 | 모든 초기값/prototype 상태 표기, 양 플랫폼 camera/GPU capability 확인 |
| M1 광학 reference | cell/height/gradient, 두 표면 교차, Snell, ConstantDepth, CPU debug maps | M0 | identity·평판·normal·TIR·연속성 시험 통과 |
| G0 실물 타당성 선행 검증 | 17절 고정 이미지 reference, shape 후보·PSF·반사 분리, 네 거리 preliminary fit | M0/M1 | 독립 validation으로 11·17절 게이트 통과 또는 모델 재설계. 실물 없음이면 미통과 |
| M2 양 플랫폼 vertical slice | native frame→GPU→QUADRA preview, JSON loader, deterministic seed, range panel·override resolver | M1/G0 | Android/iOS 각각 UX-001~003, MAT-002, CAM-001, OPT-001~006/012, DEP-001, API-001 통과 |
| M3 P0 촬영 완성 | still pipeline, snapshot, tile render, 저장/복구, 10분 성능 시험 | M2 | CAP-001~003, MAT-001, P0 PERF/NFR 및 range 조합·응답성 시험 통과; P0 데모 및 시험 보고서 |
| M4 실물 geometry fit | 네 거리 paired dataset, inverse flow, constrained fit, 홀드아웃 보고서 | M1; 촬영 준비는 M0부터 병행 | CAL-001~003의 geometry 목표 통과 또는 모델 수정 후 재검증 |
| M5 P1 depth·광학 세부 | Hardware/Estimated, PSF/footprint, RGB dispersion, Fresnel, reflection, imperfections | M3/M4 | DEP-002~003, OPT-007~012와 관련 fixture 통과 |
| M6 P1 릴리스 검증 | calibrated JSON freeze, 양 플랫폼 재검증, 시각 평가·열·capture·접근성 | M4/M5 | 모든 P0/P1 MUST 및 기기별 게이트 통과, 알려진 한계 문서화 |
| M7 P2 기획 | 추가 재질·영상·Live Photo·RAW의 별도 PRD | M6 | 비용·저장·오디오·메타데이터·새 성능 목표를 합의한 후 구현 시작 |

각 단계 PR은 요구사항 ID, 코드/자산 버전, 검증 명령 또는 실기기 절차, 실제 측정 결과, 남은 실패를 포함한다. 샘플 없이 M0/M1 및 독립 camera capability spike는 진행할 수 있으나 G0와 양 플랫폼 본개발 M2/M3는 통과 처리하지 않는다. 사용자가 미검증 prototype 개발을 선택하면 예외 사유를 기록하고 실물 재현 검증과 분리한다. 최적화는 reference 정확성 확보 후 진행한다.

## 15. 위험, 미확정 값, 변경 규칙

| 항목 | 현재 결정/제한 | 해소 시점 |
|---|---|---|
| 실제 QUADRA SKU·표면 방향 | 미측정; 초기 flat-front 모델만 존재 | M0 확보, M4 검증 |
| 실물 IOR·두께·pitch·높이 | JSON 예시는 초기값; 측정 prior가 우선 | M4 |
| 형상 비식별성 | 계측 고정·다중 거리·홀드아웃으로 억제 | M4 |
| 반사 환경 부재 | optical-validation은 none/계측 환경, reference-look은 명시적 조명 프리셋; 현재 환경 복원은 미보장 | G0/M5 |
| 단안 깊이 scale | metric 검증 불가하면 ConstantDepth | M5 |
| 가려진 장면·화면 밖 색 | 명시적 sampling fallback, 실제 복원 불가 | P1 한계로 유지 |
| 광학 오차 목표 달성 여부 | 아직 미측정. 데이터/모델 수정 후 재시험 | M4/M6 |
| 최소 기기·성능 달성 | 초기 지원 기준, 실기기표와 결과 필요 | M0/M3/M6 |

SSOT 변경은 이 문서의 버전·요구사항 ID와 calibration schema/model version을 함께 검토한다. 물성 변경, 모델 변경, 품질 최적화를 서로 구분하고 그 변경이 필요한 fixture만 재검증한 뒤 전체 릴리스 게이트를 수행한다. 인터넷 normal map, 자의적인 UV strength, 반사 overlay만으로 실물 오차를 맞춘 구현은 OPT-002/004 및 CAL-003 완료로 인정하지 않는다.

## 16. 릴리스 Definition of Done

- P0: 양 플랫폼에서 권한→실시간 QUADRA→두께·굴곡·셀 크기 조절→고해상도 촬영→저장이 완주하고, 이중 굴절·결정적 seed·재질 SSOT·설정 복원·안정성·성능 검증 결과가 존재한다.
- P1: 실제 샘플 provenance, 네 거리 calibration dataset, fitting 재현 설정, 독립 test 결과, calibrated JSON, 시각 평가 및 기기별 성능 보고서가 모두 존재한다.
- 사용자 결과물은 preview 확대가 아닌 still 원해상도 렌더이며, material/geometry/depth/색 처리의 일관성이 확인된다.
- 모든 미지원 기능과 근사 한계를 지원표에 명시하고, 실패한 MUST 요구사항을 숨긴 채 완료 처리하지 않는다.

## 17. 공학 재검토 — 실물 재현을 위한 설계 보강

### 17.1 판정과 최적화 목적

v1.2는 광학 기반 prototype의 방향으로는 타당했지만 실물에 가장 가까운 최적 설계라고 판단할 증거가 부족했다. 특히 변위장만으로 흐림까지 평가할 수 없고, superellipse와 셀 경계 형상을 먼저 확정하면 잘못된 표면을 정밀하게 구현할 위험이 있었다. 본 절은 v1.3의 필수 보강 규정이며 참조 품질·오차 예산의 구체화에 적용한다.

최적화 목적은 ‘검증된 촬영 조건에서 실물 오차를 최소화하면서 12절 모바일 시간·메모리 예산을 충족’하는 것이다. 품질과 비용 사이의 Pareto 후보를 비교하고 가장 작은 검증 통과 모델을 선택한다. 무조건 많은 효과나 ray 수를 추가하는 것은 목표가 아니다. 실제 샘플·기기·데이터가 없는 현재 상태에서 최적성 또는 실물 동등성을 확정하지 않는다.

| 기존 문제 | 영향 | 수정 결정 |
|---|---|---|
| single-ray displacement 중심 | 흐림·상 겹침·방향성 번짐을 놓침 | aperture/PSF 비교와 MTF 평가 추가 |
| min 기반 경계 높이 | 내부 대각선에서 인공 normal seam 가능 | tensor-product basis로 변경, model v2 |
| 추정 형상 고정 | 잘못된 lenslet을 미세 조정하는 비용 | 계측 shape 후보 비교 후 선택 |
| 현재 RGB를 반사 환경으로 사용 | 실물에 없는 반사 패턴 | 기본 none, 계측 환경으로 검증 |
| 앱 완성 뒤 실물 fitting | 핵심 품질 실패를 늦게 발견 | G0를 본개발 선행 게이트로 이동 |
| 정밀한 목표 숫자만 존재 | 측정 불확실성보다 작은 오차를 주장 | 반복측정 noise floor·오차 예산·검증 범위 추가 |

### 17.2 실물·카메라 모델 식별

G0에서 flat-front/pattern-back, pattern-front/flat-back, 양면 요철 후보를 실물과 대조한다. 부호·요철 방향을 관찰 없이 고정하지 않는다. 가능하면 비접촉 profilometry 또는 투명재에 적합한 계측으로 셀 단면과 양면 형상을 측정한다. 촬영 기반 추정만 가능한 경우 IOR·두께·높이의 동시 식별 한계를 보고한다. 형상 계측이 없다면 파라미터를 ‘실제 물성 측정값’이 아닌 ‘영상에 맞춘 유효값’으로 표시한다.

카메라 optical center/entrance pupil과 유리 사이 거리, focus 상태, 실제 focal length와 F-number를 기록한다. 휴대폰 외장 렌즈 커버에서 잰 거리를 그대로 optical center 거리로 쓰지 않는다. 측정 불가능한 offset은 제한된 nuisance parameter로 fitting하고 uncertainty를 기록한다. EIS·OIS·focus breathing·ISP crop 변경은 고정하거나 frame별 geometry에 반영한다.

후보 모델은 (A) superellipse v2, (B) 주기 경계조건을 갖는 tensor-product spline, (C) 계측 height field다. height field가 기준이며 normal/LUT는 파생 캐시로 유지한다. B/C는 control point spacing·보간법·단위·height asset hash를 versioned model 계약에 추가한다. 수직벽·overhang처럼 height field로 표현 불가능한 형상이 의미 있게 존재하면 reference mesh를 비교하고 현재 도메인의 적용 한계를 선언한다.

평판 굴절에서도 관측 광선 구조가 단순 pinhole과 달라질 수 있다는 점은 [Agrawal 등의 flat refractive geometry 연구](https://www.cs.cmu.edu/~ILIM/projects/IM/aagrawal/cvpr12/FlatRefraction.html)를 참고한다. 해당 연구는 QUADRA 형상의 직접 검증 근거가 아니다. [굴절 표면을 명시적으로 모델링하는 연구](https://arxiv.org/abs/1909.10820)는 surface geometry 기반 calibration의 참고 자료로 사용한다.

### 17.3 변위뿐 아니라 공간 가변 PSF 재현

pixel 하나의 중앙 ray는 광선 위치만 제공한다. 유한 aperture, surface microstructure, pixel footprint는 여러 경로의 기여를 만들 수 있으므로 실물의 선명도까지 확인해야 한다. reference는 pixel sub-sample과 entrance pupil sample을 분리하여 적분한다. pupil ray 생성은 측정/근사 camera model을 따르며 임의 cone으로 바꾸지 않는다. 렌즈·aperture 모델링 근거는 [PBRT Realistic Cameras](https://www.pbr-book.org/3ed-2018/Camera_Models/Realistic_Cameras), 표면 roughness에 의한 반사·투과 분포는 [PBRT Rough Dielectric BSDF](https://www.pbr-book.org/4ed/Reflection_Models/Rough_Dielectric_BSDF)를 참고한다.

reference 비교는 먼저 알려진 고해상도 평면 target에서 수행한다. 임의 3D 장면의 단일 RGB는 다른 pupil/view 방향의 radiance를 제공하지 않으므로 multi-ray 처리 자체가 누락된 장면을 복원한다고 주장하지 않는다. RGB-D는 관측된 Lambertian 표면을 근사적으로 재투영하는 입력이며 반짝이는 털·투명체·가림 해제는 별도 한계다.

데이터에는 checkerboard 외에 random-dot/coded pattern, slanted-edge, 고립된 점·가느다란 선 target을 추가한다. 반복 무늬 오대응을 줄이고 셀 중심·edge·corner의 PSF 폭, 주축 방향, MTF를 거리·focus별로 측정한다. 이동 무늬가 겹치거나 번지는 pixel은 단일 flow로 억지 설명하지 않고 PSF/image formation 평가에 포함한다.

오프라인 reference는 16→64→256 samples/pixel 등으로 늘려 수렴을 확인한다. 예시 sample 수는 고정 합격조건이 아니다. 증가 전후 linear RGB MAE≤0.5/255와 PSF second-moment 변화≤1%를 목표로 하며 수렴한 결과를 기준으로 삼는다. 모바일은 single-ray+검증된 공간 가변 PSF/LUT와 제한된 multi-ray를 비교하여 비용·오차에 따라 선택한다.

입력 RGB에는 이미 실제 camera blur·denoise·sharpen·tone mapping이 포함되어 있다. simulated full PSF를 다시 convolution하여 카메라 blur를 두 번 넣지 않는다. reference의 ‘유리 없음’ PSF와 ‘유리 있음’ PSF를 함께 측정하여 추가 transfer를 fitting한다. 단순 양의 blur kernel로 설명 불가능한 경우 억지 deconvolution을 추가하지 말고 지원 한계와 residual을 보고한다. RAW 센서/선형 데이터를 실험용으로 확보하는 것은 허용하며 앱의 RAW 기능 P2와 구분한다.

### 17.4 Sampling·복사량·누락 경로

왜곡 map의 Jacobian 또는 ray differential로 source footprint를 추정하고 minification에는 mip/anisotropic 또는 EWA 근사 filtering을 사용한다. 무조건 bilinear 한 번으로 처리하면 fine checker·털에서 aliasing이 생길 수 있다. image resampling Jacobian의 determinant를 임의 밝기 배율로 곱하지 않는다. 표면 거칠기, aperture, pixel anti-aliasing을 서로 다른 항으로 관리하여 중복 blur를 방지한다.

양쪽 공기가 같은 매질인 transmission path의 radiance convention을 reference와 통일한다. 단일 interface의 eta²를 최종 RGB에 중복 적용하지 않는다. 반사·투과·흡수 가중치와 측정 exposure를 분리한다. 피부/털의 specular radiance가 다른 시점에서 같다고 가정한 부분도 근사로 기록한다.

reference에서는 내부 반사 bounce 수를 증가시켜 ghost/brightness 변화가 품질 예산 이하인지 평가한다. 실시간 생략은 그 결과로 정당화한다. TIR이나 다중 반사가 실물의 지배적 특징이면 임의 검정/반사색 fallback으로 calibrated 합격 처리하지 않는다. wave optics는 계속 범위 밖이지만 해당 효과가 관찰 품질을 지배하면 범위 한계를 명시한다.

calibrated 평면 테스트의 screen-outside·disocclusion 비율은 ROI의 1% 이하를 초기 목표로 둔다. 일반 자연 장면은 비율과 영향을 별도 보고하고 보이지 않는 영역을 flow mask에서 뺐다고 성공으로 해석하지 않는다. 기존 coverage 기준은 최소 데이터량 기준이며 정확도 증명의 충분조건이 아니다. 전체 ROI 이미지와 invalid overlay를 반드시 제출한다.

### 17.5 측정 불확실성과 품질 예산

모든 이하 수치는 개발 목표이며 현재 측정 결과가 아니다. 측정 장비 정밀도와 반복 촬영 오차를 먼저 확인한다. intrinsics·pose·distance·flow의 uncertainty를 bootstrap 또는 Monte Carlo perturbation으로 최종 displacement에 전파한다. confidence interval과 sensitivity Jacobian의 singular value/parameter correlation을 보고한다. 식별 불가 parameter는 고정·prior 또는 유효 parameter로 축소한다.

| 오차 계층 | 초기 목표 / 판정 |
|---|---|
| 동일 지그 repeat noise floor | inverse-map EPE median≤0.5px @긴 변1920; 초과하면 지그·focus·flow부터 개선 |
| 수치 solver | capture p95≤0.1px, preview≤0.25px; 해당 출력 기준 |
| GPU 근사 vs 수렴 reference | map p95≤0.25px @1920, linear RGB MAE≤1/255 |
| 실물 geometric fidelity | 11.4절 거리별 EPE·edge EPE 기준 유지; CI와 coverage 병기 |
| 실물 PSF 폭 | center/edge/corner 각 축 second-moment 폭 오차≤max(0.5px, 실측 폭의 15%) @1920 |
| 실물 MTF | 고정 exposure·ISP 조건의 MTF50 상대오차≤15%, 측정 가능한 SNR 영역만 사용하고 제외율 보고 |
| 정적 temporal stability | 고정 RGB/depth/pose에서 map jitter p95≤0.1px, 같은 seed 출력 반복 일치 |

위 항목의 p95를 독립이라고 가정해 단순 합산/RSS하지 않는다. end-to-end holdout 결과가 최종 판정이며 solver·geometry·PSF·depth·ISP를 분리한 ablation으로 원인을 찾는다. photo loss는 noise scale로 정규화하고 geometric/photometric loss의 λ 및 단위를 명시한다. 허용 오차보다 관측 불확실성이 크면 ‘통과’가 아니라 ‘판정 불가’다.

split은 같은 capture burst 및 재장착 세션 전체를 묶어 분리한다. 동일 셀·동일 세션의 인접 프레임이 train/test에 섞이지 않게 한다. 같은 실물 한 장에서의 검증은 그 샘플 재현 범위에만 적용한다. 제품군 전체 재현을 주장하려면 최소 3개 독립 샘플과 가능한 서로 다른 로트를 확보하고 sample holdout을 수행한다. 제조 편차의 random seed는 실물 특정 셀 일치와 구분한다.

기본 네 거리를 유지하고 최소 하나의 미사용 중간 거리(예: 0.75m 또는 1.5m)를 별도 촬영한다. 지원 tilt 범위와 camera-to-glass pose·focus 범위를 시험 전에 정하고 각 endpoint와 중간점을 검증한다. 숫자로 된 지원 범위가 없으면 정면·검증된 고정 pose만 calibrated로 표시한다. 사용자 slider의 물리적 동작은 보장 대상으로 시험하되 각 설정이 존재하는 실물 QUADRA와 일치한다는 의미는 아니다.

### 17.6 G0와 최종 증거 패키지

G0는 앱 전체 UI를 만들기 전에 한 카메라·고정 target에서 수행한다. 네 거리와 독립 validation capture에 대해 (1) 단순 UV baseline, (2) 이중 굴절 single-ray, (3) measured/fitted surface, (4) PSF/footprint 추가 모델을 나란히 비교한다. geometry·blur 게이트와 측정 불확실성 조건을 통과하는 최소 모델을 선정한다. 이때 validation을 모델 선택에 사용하고 최종 test는 M4/M6까지 봉인한다.

G0 실패 시 순서는 촬영 지그/좌표 → shape family → camera/PSF → 미관측 경로 순으로 점검한다. 랜덤 imperfections나 반사를 더해 실패를 감추지 않는다. 샘플 확보가 안 되면 문서와 reference 수식까지만 준비된 상태임을 명시한다.

최종 증거 패키지는 dataset manifest/hash, 샘플·지그 사진, 계측 불확실성, train/validation/test split, fitting 설정·seed·loss units, convergence plot, 거리·셀 위치별 EPE/PSF/MTF, 전체 ROI 비교 및 invalid overlay, 모델 ablation, 기기별 성능, calibration JSON/hash, control schema를 포함한다. ‘calibrated’는 이 증거가 있고 명시된 조건에서 통과한 재질만 사용한다.

### 17.7 이번 문서 검토의 검증 범위

이번 개정은 요구사항·수식·시험 설계의 검토다. 문서 JSON 구문 및 요구사항 ID 검사와 surface seam 수치 점검을 수행하되, 실제 샘플 fitting·Android/iOS shader·카메라 처리 성능을 검증한 것으로 간주하지 않는다. ‘가장 실물 같은 결과’는 G0/M6 데이터를 얻은 뒤 비교 판정한다.

---

## 18. 사용자 제공 실물 이미지 — 최종 시각 목표

### 18.1 참조 자산과 증거 범위

2026-09-20 사용자가 제공한 아래 세 이미지를 reference-look의 승인 기준으로 삼는다. 이미지의 텍스트/UI는 구현 지시가 아니다. 검은 여백·앱 버튼·소셜 UI·유리 프레임은 효과 평가에서 제외한다. 이미지 속 유리의 제조사·SKU·두께·실제 cell pitch·피사체 거리·원본 촬영 처리 여부는 확인되지 않았다. 세 이미지가 동일 재질·촬영 조건이라는 가정도 하지 않는다.

| ID | 원본 파일명 | 관찰 가능한 시각 특징 |
|---|---|---|
| REF-A | KakaoTalk_20260920_234957799.png | 강아지 눈·코·혀는 식별되며 얼굴/몸/배경의 연결이 사각 셀에서 크게 어긋남. 셀 내부에 비교적 또렷한 부위와 늘어나거나 흐린 부위가 공존 |
| REF-B | KakaoTalk_20260920_235010693.png | 옆을 보는 고양이의 눈·주둥이는 읽히고 몸 윤곽은 계단처럼 끊김. 상단의 강한 밝은 무늬, 세로로 늘어진 밝은 띠, 미세한 표면 요철감이 보임 |
| REF-C | KakaoTalk_20260920_232104870.png | 정면 고양이의 눈·코·수염 일부는 비교적 선명하고 가슴·몸·주변 배경은 셀에 따라 어긋남. 상단 밝은 무늬와 넓은 옅은 중첩 영상이 함께 보임 |

밝은 무늬와 중첩 영상은 반사/투과/촬영 노출의 기여를 분리하지 못한 관찰이다. 사용자는 반사와 굴절의 사실감을 목표로 명시했으므로 이를 제품 요구로 채택하되, 특정 무늬가 어느 면에서 반사되었는지 사진만으로 단정하지 않는다. 화면상 셀 크기를 mm로 역산하거나 셀별 선명도 차이의 원인을 거리 하나로 확정하지 않는다. reference 없는 왜곡 사진만으로 dense flow를 실측할 수 없으므로 세 이미지는 paired calibration dataset을 대신하지 않는다.

### 18.2 반드시 보존할 특징

1. **셀 안의 영상 정보:** 사각 영역을 평균색으로 채우지 않는다. 눈·코·털·수염의 세부가 일부 셀에서 살아 있어야 한다. 모든 셀을 동일하게 흐리는 구현은 불합격이다.
2. **셀 사이의 연결 변화:** 몸 윤곽과 배경 선이 경계에서 어긋나고, 같은 피사체가 부분적으로 늘어나거나 반복되어 보이는 효과를 광선 매핑에서 만든다. 독립 tile을 무작위 이동하는 방식으로 대체하지 않는다.
3. **형상에 따른 비선형 변화:** 셀 중앙·가장자리·모서리의 확대/압축 및 선명도가 달라질 수 있어야 한다. core plateau·shoulder·boundary band의 폭과 shape를 G0에서 비교한다. 현재 superellipse는 후보이며 고정 정답이 아니다.
4. **연속된 유리 한 장의 인상:** 각 셀을 독립 투명 버튼처럼 두껍게 테두리 처리하지 않는다. 경계는 실제 surface와 하이라이트·굴절 변화로 읽히게 한다. 검은 격자선이나 균일한 흰 테두리를 합성하지 않는다.
5. **표면 하이라이트와 넓은 반사:** 밝은 환경 무늬가 유리 형상에 따라 나뉘거나 늘어지고, 약한 넓은 반사가 동물 영상과 함께 보여야 한다. reference-look에서 반사 제거 상태만으로 완료할 수 없다.
6. **절제된 미세 질감:** 표면의 잔물결·roughness가 보이되 노이즈/먼지가 화면 전체를 지배하지 않는다. 사진 압축이나 저해상도 흔적을 물리 유리 결함으로 그대로 복제하지 않는다.

동물 얼굴 영역만 따로 선명하게 만드는 semantic mask나 눈 확대·얼굴 재배치·생성형 복원을 기본 구현에 넣지 않는다. 셀과 얼굴의 상대 위치, 거리, 표면 형상으로 국소 선명도가 자연스럽게 결정되어야 한다. reference의 우연한 얼굴 정렬을 모든 피사체에 강제로 보장하지 않는다.

### 18.3 반사·굴절의 결합과 제어

reference-look의 기본 시각 프리셋에는 넓은 환경 밝기 분포와 면광원 형태의 하이라이트 입력을 제공한다. ReflectionSource environmentMap 계약에 합성된 조명 환경도 포함할 수 있으나 sourceKind를 measured/preset로 구분한다. preset 조명은 특정 실내를 정확히 복원한 것이 아니라 사용자 이미지의 표면감을 목표로 한 근사다.

반사 ray는 굴절에 쓰는 동일 surface와 oriented normal에서 계산하고, 같은 roughness·Fresnel 계약으로 합성한다. 화면 위 고정 흰색 무늬를 덧씌우지 않는다. 유리 pose 또는 환경 orientation을 바꿀 때 반사 위치와 모양이 연속적으로 바뀌어야 한다. 기본 glass는 카메라에 고정되므로 실제 세계 조명에 대한 tracking은 별도 pose 입력 없이는 보장하지 않는다. 움직임에서 센서 orientation을 사용하는 경우 좌표 기준·초기 정렬·drift를 검증한다.

UI의 상세 패널에는 P1에서 ‘반사 밝기’ 0~1, step 0.01 및 ‘조명 방향’ yaw -180~180°, step 1°를 제공한다. 밝기는 preset 환경 radiance의 정규화된 노출 제어이며 임의로 Fresnel 가중치를 증폭하는 계수가 아니다. 기본값은 G0 시각 비교 후 versioned LookPreset에서 확정한다. pose·reflection source/hash·노출·방향을 RenderSnapshot과 capture metadata에 보존한다. 두께·굴곡·셀 크기는 기존 P0 필수 조절을 유지한다.

실측 광학 material, UserMaterialOverrides, LookPreset은 별도 provenance를 가진다. base material이 calibrated여도 preset 조명으로 만든 최종 영상 전체를 실제 현재 환경과 일치한다고 표시하지 않는다. P1 완료는 검증용 optical-validation와 사용자용 reference-look을 모두 평가한다.

### 18.4 승인 방법

G0 비교판에는 같은 입력에 대한 원본, 단순 tile/UV baseline, 제안 renderer, 실물 paired 결과를 동일 크기로 배치한다. REF-A/B/C는 시각 특징의 참고로 별도 표시하며 서로 다른 고양이·강아지 사진 간 pixel EPE를 계산하지 않는다. 정량 오차는 동일 장면 paired 촬영에서만 측정한다.

VIS-001/002 시각 체크는 (a) 국소 세부 보존, (b) 셀 경계 윤곽 어긋남, (c) core/edge 선명도 차이, (d) 표면에 결합된 하이라이트, (e) 넓은 약한 반사, (f) 과장되지 않은 미세 질감의 여섯 항목이다. graphics 담당자와 사용자 또는 지정 제품 담당자가 나란히 비교해 항목별 통과/실패와 근거를 남긴다. 이 승인 기록은 11절 정량 지표를 대체하지 않는다.

VIS-003은 정지 10초, 좌우 이동 10초, 접근/후퇴 10초를 각각 기록한다. 동일 seed의 유리 질감이 매 프레임 바뀌거나 반사가 갑자기 다른 셀로 튀면 실패다. 움직이는 동물은 재현 가능한 장면과 분리하여 자연 장면 평가에 사용한다. 실제 정지 사진만으로 시간적 일치를 검증했다고 주장하지 않는다.

reference-look의 반사·질감이 준비되지 않은 P0는 ‘굴절 prototype’으로만 보고한다. 사용자 이미지 수준의 완료는 M6에서 VIS-001~003, PSF/geometry 검증 및 모바일 성능을 함께 통과한 경우다.

---

문서 이력: v1.4 — 사용자 실물 이미지 3종을 시각 목표로 등록, 국소 선명도·셀 윤곽·반사/하이라이트 승인 기준 및 LookPreset 추가. v1.3 — surface seam·Fresnel·G0·PSF·불확실성 보강. v1.2 — range slider와 override 추가. v1.1 — 광학·캘리브레이션·API·성능 명세 통합. 설계 수치는 실측 사양이 아니며 검증 후 갱신한다.
