# QUADRA Glass Camera

iOS 17+ native camera app. Open [QUADRA.xcodeproj](QUADRA.xcodeproj) in Xcode, choose a signing team and an iPhone, then Run. No package dependencies. Camera and images stay on device.

The supplied cat and dog photos are the visual targets; `sample-dog.jpg` is the user's exact Chihuahua input. The implementation is a **prototype**, not a claim that every animal, distance and lighting condition matches the target. The original PRD is preserved in `docs/`; Android and the PRD's calibrated-release gates are not implemented by this iOS build.

## Implemented

- AVFoundation live camera, front/back switch, tap to focus, permission/error states and foreground recovery.
- Photo/video mode, filtered 1080×1440 H.264 MP4 recording targeting 30 fps, microphone AAC audio when permitted, elapsed timer and stop button. Dial changes are recorded live. Backgrounding/interruption finishes the current video; local completion precedes Photos insertion. Recent videos support playback, sharing and save retry.
- One Metal implementation for preview and original-resolution still export. Preview uses at most one in-flight GPU command; geometry is cached between material changes.
- Continuous tensor-product glass height field with rounded joins, analytic normals, air → glass → air Snell refraction, exact dielectric Fresnel and a synthetic camera-side lighting preset. No averaged-color mosaic, drawn black grid, facial masks, or generated replacement animals.
- Shared slopes across cell joins and anisotropic mip filtering reduce pinched seams and aliasing while preserving broad facets and uncompressed detail.
- Three patterns below the preview: Quadra, Cross Large (regular broad crossed ribs) and Diamond (diagonal facets). Selection persists and applies to preview, captured photos and live video, including switches during recording. Pattern changes retain the dial settings; full reset restores Quadra.
- A semicircular drag dial below the preview, with primary tabs ordered by visible effect: cell size (initial selection), relief, roundness, thickness. Original comparison sits alongside; additional edge/reflection/lighting tabs scroll horizontally. Full reset and persisted overrides; no adjustment popup over the subject.
- Shutter takes the last submitted material snapshot. Subsequent slider changes do not change that photo. JPEG metadata records material/hash/seed, estimated geometry, constant depth and synthetic reflection provenance.
- Atomic local export before Photos insertion, retained result on Photos failure, retry/share, existing-photo import and a clearly labeled sample.

## Validate

```sh
# Build for an iPhone without signing
xcodebuild -project QUADRA.xcodeproj -scheme QUADRA \
  -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# GPU numerical checks (macOS with Metal)
swiftc -O QuadraCamera/GlassMaterial.swift QuadraCamera/GlassRenderer.swift \
  Tools/OpticsCheck.swift -o /tmp/quadra-check
/tmp/quadra-check

# Render the same shader on an ordinary cat photo
swiftc QuadraCamera/GlassMaterial.swift QuadraCamera/GlassRenderer.swift \
  Tools/RenderCheck.swift -o /tmp/quadra-render
/tmp/quadra-render

# Record/decode a fixture, check live material changes and writer restart
swiftc -O QuadraCamera/GlassMaterial.swift QuadraCamera/GlassRenderer.swift \
  QuadraCamera/VideoRecorder.swift Tools/VideoCheck.swift -o /tmp/quadra-video-check
/tmp/quadra-video-check

# UI test on an available simulator; use your simulator's id
xcodebuild -project QUADRA.xcodeproj -scheme QUADRA \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -only-testing:QuadraUITests/QuadraUITests/testSampleControlsAndCapture test
```

`Tools/make_project.py` regenerates the checked-in Xcode project with the Python standard library. The Metal source is bundled and compiled once at renderer initialization; material adjustment never recompiles it.

## Current limits

This build uses a fixed 1.2 m scene plane, estimated FOV and a camera-attached glass plane. It does not recover hidden scene content or track real reflection lighting. About 2.46% of the current default test map samples beyond the input image and uses edge clamping. Live camera framing is portrait 3:4; imported photos retain their aspect ratio. Landscape camera UI and calibrated intrinsics are outstanding.

Video records the live camera in the same portrait 3:4 framing. Camera switching and original comparison are disabled during recording; glass controls remain active. Denied microphone access produces a visibly muted recording. Encoding drops frames under backpressure while preserving capture timestamps; 30 fps is a target, not a sustained thermal guarantee. Recordings end when the app backgrounds; arbitrary imported-video processing is not implemented.

The supplied reference led to selecting a rolled tensor-product plate instead of the PRD's initial superellipse lenslet candidate, whose first render looked like inflated glass buttons. These effective height parameters have not been measured from a manufactured glass sample. Multi-distance paired glass captures, PSF/MTF calibration, depth sensing, sustained thermal testing and user visual acceptance remain open.

See `docs/VALIDATION.md` for actual results and `artifacts/` for outputs. A successful build or numerical test alone does **not** pass the visual target.

Sample photo: [Orange Tabby Cat sitting on a couch](https://commons.wikimedia.org/wiki/File:Orange_Tabby_Cat_sitting_on_a_couch.jpg), LauraDelga, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Sample renders are cropped and processed by the app's shader. The user reference is not used as renderer input.
