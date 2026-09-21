# Validation record — 2026-09-21

Status: **working iOS prototype; reference visual acceptance is still open.**

## Executed checks

| Check | Actual result |
|---|---|
| iOS 17 deployment target, Xcode 26.6 build | Passed, unsigned and developer-signed |
| Physical installation / launch | Passed on connected iPhone 15 Pro, iOS 26.6.1 |
| Simulator UI flow | Passed: adjust relief, reset, original comparison, capture, Photos save |
| Physical iPhone, current v2 surface / Chihuahua fixture | Passed: square aspect, controls/reset, original comparison, capture and actual Photos save |
| Physical iPhone, sample → live → front camera | Passed: camera return, front switch, enabled shutter and live preview without an error alert (`FrontCameraTests.xcresult`) |
| Physical camera UI flow | Passed: live frames, shutter, adjust controls during processing, export completion |
| Physical output | 3024×4032 JPEG, 12,192,768 pixels; decoded after copying from app container |
| Physical still render time | 0.319 s, one capture; includes renderer setup, excludes Photos insertion and sensor exposure |
| Capture snapshot | Saved relief 1.7 mm / pitch 33.5 mm / thickness 11.1 mm while post-shutter slider moved to about 0.6 mm relief; saved effective hash preserves shutter state |
| Analytic normals vs finite difference | p95 0.02798°, maximum 0.03427° |
| Parallel plate CPU analytic vs GPU double refraction | maximum 0.000120 px at 300×400 |
| Matched-IOR identity | Passed, normalized error < 1e-6 |
| 300×400 vs 900×1200 map, current v3 surface | maximum 0.00122 px at 1200-pixel height |
| Fixed seed | Repeated GPU height and gradient probes identical |
| 8 extreme parameter combinations | Finite bounded UVs; this is not a first-root/calibration accuracy test |
| Material JSON/hash | Codable round trip, edit changes hash, reset restores hash passed |
| Current default out-of-source coverage | 2.460%; clamped at edges. 0 invalid/TIR at default test geometry |

## Evidence

- `artifacts/optics-check.txt`: numeric GPU test output.
- `artifacts/SimulatorTests.xcresult`: successful sample/Photos UI test.
- `artifacts/DeviceTests.xcresult`: successful physical camera UI test.
- `artifacts/DogDeviceTests.xcresult`: successful current-shader Chihuahua workflow on the physical iPhone, including Photos save.
- `artifacts/dog-iphone.jpg`: actual 447×447 output exported by the physical iPhone from the supplied Chihuahua input.
- `artifacts/device/device-validation.json`: actual sensor photo size, snapshot and render duration.
- `artifacts/device/device-original.jpg` and `device-result.jpg`: same physical camera exposure, before/after; original comparison is reduced to 1440 high, result retains 12 MP.
- `artifacts/device-test-attachments/`: live and post-capture device screenshots.
- `artifacts/comparison.html`: user's exact Chihuahua input, same-shader output and the new dog target side by side.
- `artifacts/dog-original.png`, `dog-quadra.png`: 447×447 original/result, no AI replacement or detail generation.

The physical camera test scene was a blue figurine on a desk, **not a cat**. Its photo validates the camera/export path, not the user's final cat-photo appearance criterion. That camera test wrote locally inside this app. Photos insertion was subsequently verified on the physical iPhone with the user's Chihuahua fixture and the current v2 shader.

## Unpassed release requirements

No paired real-glass dataset, measured material geometry, PSF/MTF fit, depth sensing, device p50/p95/thermal report or user visual acceptance exists yet. The source edge-clamp rate exceeds the PRD's proposed 1% calibrated ROI target. The app is portrait-only and uses estimated camera intrinsics with constant scene depth. These are explicit prototype limitations, not waived acceptance criteria.

The initial superellipse renderer visibly resembled separate inflated buttons. The current renderer uses a continuous tensor-product plate with broad tilted facets and rounded joins. It produces surface-derived refraction and reflected lighting but has not been fitted to a manufactured QUADRA sample. Reflective room lights are a synthetic preset.

## User feedback and revision

The user rejected study 01/02 as weaker in refraction and glass texture than the supplied target. Study 03 uses `rolled-plate-v2`: stronger directional facets, a shallow per-cell crown for local magnification, 2.85 mm relief, 28 mm pitch and 7.4 shoulder sharpness. It is tuned on the user's newly supplied Chihuahua image; controls, sample rendering and camera rendering use this same material and shader. The final visual target has not been signed off by the user.

The 12 MP device evidence above belongs to the earlier prototype surface. Numeric checks were rerun after the v2 surface change. Keep those two kinds of evidence distinct.

The 6 visual checks from PRD §18 — local detail, broken contours, core/edge sharpness, attached highlights, broad reflection and restrained microtexture — require comparison and user approval. Successful numerical checks and build results do not pass them automatically.

## Cell-boundary correction — study 04

The user reported that image detail was being pinched or chewed at cell borders. `rolled-plate-v2` forced the profile slope to zero at every join, introducing thin strips of near-unrefracted scene between tilted facets. Study 04 (`rolled-plate-v3`) rounds the shared piecewise-linear profile across each vertex instead, retaining the mean neighboring slope at the join. The rounded transition is wider; relief, pitch, seed and lighting parameters are unchanged.

The previous five source taps and capped footprint were replaced by linear-light mipmaps and up to 8× hardware anisotropic filtering. The larger one-sided map derivative is used at a fold to avoid canceling the footprint. This is a local filtering approximation, not integrated nonlinear ray/PSF calibration.

- `artifacts/boundary-before-dog.png` / `boundary-after-quadra.png`: same 447×447 Chihuahua and material control values, before/after the renderer correction.
- `artifacts/boundary-comparison.html`: visual comparison.
- `artifacts/boundary-optics-check.txt`: all numerical checks pass, including two new regressions. Shared-join gradient error < 0.000001; 31/34 sampled joins retain a nonzero slope. A 16:1 compressed checker converges to its expected linear-light average; 1:1 checker detail is preserved. Both have maximum sRGB byte error 0.
- Current material SHA-256: `407fb1384a4e65705f27572184871688d073edb1d7f0034e76dcb5dc473ed6d2`.
- `artifacts/BoundaryDeviceTests.xcresult`: all three physical iPhone 15 Pro UI tests pass with study 04: live camera/full-resolution export, sample controls/Photos save, sample → live → front camera.
- `artifacts/boundary-device-validation.json` and `boundary-device-result.jpg`: new study-04 sensor capture, 3024×4032, 0.330 s single still render, sample=false and matching effective/base hashes. This is an execution check, not a sustained performance benchmark.
- `artifacts/boundary-dog-iphone.jpg`: new 447×447 Chihuahua result copied from the actual app export after successful Photos insertion. Device screenshots are in `artifacts/boundary-device-attachments/`.

The before/after render reduces artificial seam strips; physical magnification, compression and folded features are still present. Visual acceptance against the user's manufactured-glass reference remains open.

## Unobstructed semicircular controls

Replaced the over-preview range panel with a permanent control deck below the image. Thickness, relief, cell size and roundness are directly selectable next to original comparison; the remaining controls are available by scrolling the same strip. A semicircular scale supports tap/drag and VoiceOver adjustment, displays the current value/unit and valid endpoints, and retains capture/camera-switch/reset controls. Thickness/relief endpoints account for the existing plate constraint so a normal drag cannot trigger an invalid-material popup.

`artifacts/DialDeviceTests.xcresult`: all three tests pass on the connected iPhone 15 Pro. The updated sample test checks all four primary tabs are hittable, each arc drag changes its value, selectors and dial remain below the preview, preview bounds stay identical when switching parameters, the coupled minimum thickness produces no error, and original comparison/Photos save still work. Live full-resolution capture and front-camera switching also pass.

`artifacts/protractor-controls-iphone.png` is the actual device screenshot, visually inspected after the test. The correction changes the control UI, not the current v3 optical model. Hardware tests cover this device; broader Dynamic Type and small-screen layout testing remains outstanding.

The primary selector order was subsequently changed to cell size → relief → roundness → thickness, with cell size selected on launch. Additional controls follow these primary tabs. Presentation order is independent of material serialization, so this change preserves saved values and material hashes. The existing four-control interaction/comparison/Photos test passes again on iPhone (`artifacts/DialOrderDeviceTests.xcresult`).

## Filtered video recording

The app now writes portrait 1080×1440 H.264 MP4 directly from Metal into a Core Video pixel-buffer pool, with AAC microphone audio when authorized. Video/audio retain capture timestamps. Live glass parameter changes use the same renderer as preview and still export. Encoding is serialized with bounded pending input buffers. Stopping drains pending frames and finalizes a temporary file before moving it to Documents; Photos insertion, sharing and retry use that completed file. Backgrounding automatically finishes the current recording, with a background task for finalization. Camera switching and original comparison are disabled while recording; denied microphone permission produces a muted indicator.

- `artifacts/VideoDeviceTests.xcresult`: all five tests passed on iPhone 15 Pro: existing photo/controls/front-camera flows, rear-camera video with live pitch adjustment/Photos save/opening the recent-capture sheet, and front-camera video finalized by backgrounding. These tests did not verify visible playback pixels; the subsequent user report exposed that gap.
- `artifacts/VideoFinalDeviceTests.xcresult`: both video tests passed again after explicit GPU output usage, sRGB video color metadata and larger mode-button touch targets were applied.
- `artifacts/video-check.txt`: the shared recorder produced a fully decodable 1080×1440, 2.0 s silent fixture with increasing frame timestamps; 59/60 submitted frames in the final local run. Before/after changing pitch mid-recording, mean normalized RGB error against the same still-rendering input was 0.00335 / 0.00384. Restart and no-frame cleanup passed. The fixture is `artifacts/video-shader-check.mp4`.
- `artifacts/video-device-inspection.jsonl`: original physical-device exports decoded completely. Rear camera: 199 frames / 6.634 s, approximately 30 fps, nonzero audio. Front/background: 134 frames / 5.017 s, approximately 26.71 fps, nonzero audio. Audio/video track start times match and end times differ by under 6 ms. These two clips precede the final sRGB tagging correction; functional video tests were subsequently repeated as noted above.
- `Tools/InspectVideo.swift` checks frame timestamp order, complete decoding, video dimensions, audio PCM samples, and track timing, and exports a representative decoded frame. Device recording/playback screenshots are in `artifacts/video-final-device-attachments/`.
- `artifacts/video-final-inspection.jsonl`: the final sRGB-tagged device clips also decode completely. Rear: 252 frames / 8.4 s; front/background: 150 frames / 5.0 s. Both short runs averaged 30 fps at 1080×1440, with nonzero decoded microphone audio and audio/video end differences below 1 ms. Files are `video-final-rear.mp4` and `video-final-front.mp4`.

Short clips validate these flows, not long-session thermal behavior, low-storage recovery under forced disk exhaustion, perceptual lip sync, or real-glass reference acceptance. The optical model remains `rolled-plate-v3`.

## Audio-only recent-capture playback correction

The user's 20.402 s recording contained 612 decodable 1080×1440 video frames and nonzero microphone audio (`artifacts/video-user-inspection.jsonl`). The missing picture was in the recent-capture sheet: setting the optional parent player at the same time as presenting the sheet could initialize `VideoPlayer` with nil, while `onAppear` played the subsequently assigned player without an attached video surface. Reopening the old sheet displayed video, confirming the first-presentation state problem.

The sheet now owns a nonoptional player in `RecentVideoPlayer`; display, play and pause use that same instance. The view reserves flexible display space. Recording, encoded files and the glass shader are unchanged.

- `artifacts/VideoPlaybackBeforeFix.xcresult`: the strengthened physical-device test failed because the first playback image stayed black for 10 seconds; reopening passed.
- `artifacts/VideoPlaybackAfterFix.xcresult`: the same test passed on iPhone 15 Pro after the correction, including recording, Photos save, visible first playback and visible playback after reopening. It samples the central image region, excluding controls, against the lit camera test scene; a completely dark real scene is outside this test's precondition.
- `artifacts/video-playback-after-attachments/`: actual corrected device playback screenshot, inspected in addition to the automated pixel check.

The earlier video UI tests asserted the sheet title and share button only, so they did not establish visible playback. Their original pass results remain recorded above with this limitation clarified.

## Cross Large and Diamond patterns

Cross Large is based on the crossed-rib glass family, closely related in appearance to Quadra. [Seves' manufacturer catalog, p. 34](https://www.sevesglassblock.com/wp-content/uploads/2018/02/SmartArchitecture_catalog.pdf) describes horizontal flutes on one face and vertical flutes on the opposite face, creating a larger checkered pattern. [Mulia's Quadra product](https://muliaglass.com/en/product/quadra-190-x-190-x-95-mm/) and [Mulia's geometry-series catalog](https://muliaglass.com/wp-content/uploads/2024/12/Catalog-Mulia-Glass-Block-November-24.pdf) provide related product references. No manufactured surface measurements were available.

The Cross Large implementation uses broad, regular alternating facets along both axes with smoothly shared joins. It belongs to the same square-cell family as the existing Quadra; it is not a repeated plus-sign mask. Diamond rotates the patterned height field and its analytic gradient by 45 degrees, keeping the scene upright. Both are effective single patterned back surfaces within the existing prototype optical model, not reconstructions of hollow glass blocks and their four optical interfaces. The original Quadra shader behavior, material JSON and default hash remain unchanged.

The pattern row occupies its own space below the preview. Selecting a pattern retains all dial values, returns from original comparison to glass, and persists across launches. Still snapshots contain the pattern in their material/hash; video samples use the selected pattern for each frame. Full reset restores Quadra.

- `artifacts/pattern-optics-check.txt`: both patterns pass analytic-normal checks (maximum 0.03427 degrees), material/hash round trips, distinct refraction, default maps without invalid rays, and eight control extremes each. Preview/export normalized-map errors are below 0.0024 pixels at 1200 pixels high. Cross Large's two-facet repeat and Diamond's rotated gradients are checked. Existing optics/seam/filtering checks also pass.
- `artifacts/pattern-video-check.txt`: all three patterns were recorded in one 3 s, 90-frame H.264 clip. Decoded video versus the same still renderer has normalized RGB mean error of 0.00334 / 0.00332 / 0.00373 for Quadra / Cross Large / Diamond. Pitch changes also carry through the recording, and writer restart/empty cleanup still pass.
- `artifacts/pattern-cross-large-quadra.png` and `artifacts/pattern-diamond-quadra.png`: same 447×447 user Chihuahua input rendered with the two added patterns, visually inspected.
- `artifacts/PatternsDeviceTests.xcresult`: all three selected tests pass on the connected iPhone 15 Pro. Both patterns are selectable below the preview without shifting its bounds; dial settings survive pattern switches; both save photos; Diamond survives relaunch; reset restores Quadra. Existing four-dial/original-comparison/photo checks pass. Switching Cross Large → Diamond while recording, Photos insertion, visible first video playback and reopening also pass. Screenshots are in `artifacts/pattern-device-attachments/`.
