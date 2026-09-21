import SwiftUI
import MetalKit
import PhotosUI
import AVKit

struct MetalPreview: UIViewRepresentable {
    let store: PreviewStore
    let aspect: CGFloat
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, aspect: aspect, onError: onError) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer?.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.isOpaque = true
        view.backgroundColor = .black
        view.delegate = context.coordinator
        view.autoResizeDrawable = false
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.aspect = aspect
        guard view.bounds.width > 0 else { return }
        // A 3:4 camera viewport independent of display resolution; capture rerenders
        // the original still instead of enlarging this texture.
        let width = min(1080, max(1, Int(view.bounds.width*view.contentScaleFactor)))
        let size = CGSize(width: width, height: Int(CGFloat(width)/aspect))
        if view.drawableSize != size { view.drawableSize = size }
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let store: PreviewStore
        let renderer: GlassRenderer?
        let onError: (String) -> Void
        var aspect: CGFloat
        private let gate = DispatchSemaphore(value: 1)
        private var reportedError = false
        init(store: PreviewStore, aspect: CGFloat, onError: @escaping (String) -> Void) {
            self.store = store; self.aspect = aspect; self.onError = onError
            do {
                guard let url = Bundle.main.url(forResource: "Quadra", withExtension: "metal") else { throw GlassError.message("렌더러 파일이 없습니다.") }
                renderer = try GlassRenderer(shaderURL: url)
            } catch {
                renderer = nil
                DispatchQueue.main.async { onError(error.localizedDescription) }
            }
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            if view.drawableSize.width < 2 || view.drawableSize.height < 2 {
                let width = min(1080, max(1, Int(view.bounds.width*view.contentScaleFactor)))
                view.drawableSize = CGSize(width: width, height: Int(CGFloat(width)/aspect))
            }
            guard let renderer, let (snapshot,original) = store.pending(), gate.wait(timeout: .now()) == .success else { return }
            guard let drawable = view.currentDrawable, let command = renderer.queue.makeCommandBuffer() else { gate.signal(); return }
            do {
                try renderer.encode(image: snapshot.frame, output: drawable.texture, command: command,
                                    material: snapshot.material, tangentHalfFOV: snapshot.tangentHalfFOV, mode: original ? 1 : 0)
                command.present(drawable)
                let gate = gate, onError = onError
                command.addCompletedHandler { buffer in
                    gate.signal()
                    if let error = buffer.error { DispatchQueue.main.async { onError(error.localizedDescription) } }
                }
                command.commit()
                store.markSubmitted(snapshot)
            } catch {
                gate.signal()
                if !reportedError { reportedError = true; onError(error.localizedDescription) }
            }
        }
    }
}

struct CameraView: View {
    @Bindable var model: CameraModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedControlID = "pitch"
    @State private var showPhoto = false
    @State private var showInfo = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var focusPoint: CGPoint?
    private let accent = Color(red: 0.87, green: 0.95, blue: 0.65)

    var body: some View {
        GeometryReader { geometry in
            // Reserve the controls' own space: the dial never covers the subject.
            let previewWidth = min(geometry.size.width, max(1,(geometry.size.height-352)*model.previewAspect))
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                ZStack(alignment: .bottom) {
                    MetalPreview(store: model.store, aspect: model.previewAspect) { model.errorMessage = $0 }
                        .frame(width: previewWidth, height: previewWidth/model.previewAspect)
                        .accessibilityLabel("유리 카메라 미리보기")
                        .accessibilityIdentifier("camera-preview")
                        .onTapGesture(coordinateSpace: .local) { location in
                            focusPoint = location
                            model.engine.focus(at: CGPoint(x: location.x/previewWidth, y: location.y/(previewWidth/model.previewAspect)))
                            Task { try? await Task.sleep(for: .seconds(1)); focusPoint = nil }
                        }
                    if let focusPoint {
                        Rectangle().stroke(accent,lineWidth: 1).frame(width: 58,height: 58)
                            .position(focusPoint).allowsHitTesting(false)
                    }
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(model.showOriginal ? .white : accent).frame(width: 5,height: 5)
                                Text(model.showOriginal ? "ORIGINAL" : "GLASS").tracking(1.7)
                            }
                            Spacer()
                            if let started=model.recordingStartedAt {
                                TimelineView(.periodic(from: started,by: 1)) { context in
                                    let seconds=max(0,Int(context.date.timeIntervalSince(started)))
                                    HStack(spacing: 5) {
                                        Circle().fill(.red).frame(width: 6,height: 6)
                                        Text(String(format: "%02d:%02d",seconds/60,seconds%60)).monospacedDigit()
                                        if !model.recordingHasAudio { Image(systemName: "mic.slash.fill") }
                                    }
                                }.accessibilityLabel("녹화 중").accessibilityIdentifier("recording-timer")
                            } else if model.isSample { Text("샘플 사진") }
                            else if model.isImported { Text("불러온 사진") }
                            else { Text("LIVE") }
                        }
                        .font(.system(size: 10,weight: .semibold,design: .monospaced))
                        .padding(14).background(.linearGradient(colors: [.black.opacity(0.45),.clear],startPoint: .top,endPoint: .bottom))
                        Spacer()
                        if let message = model.cameraMessage, model.hasFrame {
                            Text(message).font(.caption).padding(12)
                                .background(.black.opacity(0.8),in: RoundedRectangle(cornerRadius: 12)).padding(12)
                        }
                        if let notice = model.notice {
                            Label(notice,systemImage: "checkmark.circle.fill").font(.caption)
                                .padding(10).background(.black.opacity(0.7),in: Capsule()).padding(.bottom,12)
                        }
                    }.allowsHitTesting(false)
                    if !model.hasFrame {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.aperture").font(.system(size: 38,weight: .ultraLight))
                            Text(model.cameraMessage ?? "카메라를 준비하고 있어요").font(.callout).multilineTextAlignment(.center)
                            if model.cameraMessage != nil {
                                Button("설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                Button("카메라 다시 시작") { model.returnToCamera() }
                                Button("샘플로 살펴보기") { model.loadSample() }
                            }
                        }.padding(32).frame(maxWidth: .infinity,maxHeight: .infinity).background(.black.opacity(0.85))
                    }
                }
                .frame(width: previewWidth,height: previewWidth/model.previewAspect)
                .clipped()
                Spacer(minLength: 8)
                footer
            }
            .frame(maxWidth: .infinity,maxHeight: .infinity)
        }
        .background(Color.black).foregroundStyle(.white).tint(accent)
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onChange(of: scenePhase) { _,phase in
            if phase == .active { Task { await model.start() } }
            else if phase == .background { model.stop() }
        }
        .onChange(of: pickerItem) { _,item in
            Task {
                do { if let data = try await item?.loadTransferable(type: Data.self) { model.importImage(data) } }
                catch { model.errorMessage = error.localizedDescription }
                pickerItem = nil
            }
        }
        .alert("확인해 주세요", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인",role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showPhoto) { recentPhoto }
        .sheet(isPresented: $showInfo) { info }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading,spacing: 3) {
                Text("GLASS CAMERA").font(.system(size: 19,weight: .light,design: .rounded)).tracking(4)
                Text("A DIFFERENT WAY TO SEE").font(.system(size: 8,weight: .medium,design: .monospaced)).tracking(1.5).foregroundStyle(.gray)
            }
            Spacer()
            Button { showInfo = true } label: { Image(systemName: "info.circle").frame(width: 44,height: 44) }
                .foregroundStyle(.white.opacity(0.65)).accessibilityLabel("앱 정보와 샘플 출처")
                .disabled(model.isRecording || model.isPreparingRecording)
        }.padding(.horizontal,24).padding(.top,8)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(GlassPattern.allCases) { pattern in
                    Button {
                        model.selectPattern(pattern)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(pattern.name).font(.system(size: 12,weight: .medium))
                            .frame(maxWidth: .infinity,minHeight: 44)
                            .foregroundStyle(model.material.pattern == pattern ? accent : .white.opacity(0.6))
                            .background(model.material.pattern == pattern ? accent.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityIdentifier("pattern-\(pattern.rawValue)")
                        .accessibilityAddTraits(model.material.pattern == pattern ? .isSelected : [])
                }
            }.buttonStyle(.plain).padding(.horizontal,16)
            HStack(spacing: 8) {
                Button { model.showOriginal.toggle() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "square.on.square").font(.system(size: 15))
                        Text(model.showOriginal ? "유리" : "원본").font(.system(size: 10))
                    }.frame(width: 44,height: 44)
                }.foregroundStyle(model.showOriginal ? accent : .white)
                    .accessibilityLabel(model.showOriginal ? "유리 보기" : "원본 비교").accessibilityIdentifier("compare")
                    .disabled(model.isRecording || model.isPreparingRecording)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1,height: 20)
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(displayedControls) { control in
                            Button {
                                selectedControlID = control.id
                                model.showOriginal = false
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(control.name).font(.system(size: 12,weight: .medium))
                                    .padding(.horizontal,10).frame(minHeight: 44)
                                    .foregroundStyle(selectedControlID == control.id ? accent : .white.opacity(0.6))
                                    .overlay(alignment: .bottom) {
                                        if selectedControlID == control.id {
                                            Capsule().fill(accent).frame(height: 2).padding(.horizontal,10)
                                        }
                                    }
                            }.accessibilityIdentifier("control-\(control.id)")
                                .accessibilityAddTraits(selectedControlID == control.id ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
            }.buttonStyle(.plain).padding(.horizontal,12)
            ZStack(alignment: .top) {
                ProtractorDial(control: selectedControl, range: selectedRange,
                               value: Binding(get: { Double(model.material[selectedControlID]) },
                                              set: { model.showOriginal = false; model.set(selectedControlID,value: $0) }),
                               accent: accent)
                    .frame(width: 264,height: 136)
                HStack {
                    HStack(spacing: 8) {
                        Button { model.selectCaptureMode(.photo) } label: { Text("사진").frame(minWidth: 36,minHeight: 44) }
                            .foregroundStyle(model.captureMode == .photo ? accent : .secondary)
                            .accessibilityIdentifier("mode-photo")
                        Button { model.selectCaptureMode(.video) } label: { Text("동영상").frame(minWidth: 44,minHeight: 44) }
                            .foregroundStyle(model.captureMode == .video ? .red : .secondary)
                            .accessibilityIdentifier("mode-video")
                    }.font(.system(size: 11,weight: .medium)).frame(height: 44)
                        .disabled(model.isRecording || model.isPreparingRecording || model.isSaving)
                    Spacer()
                    Button { model.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 14)).frame(width: 44,height: 44)
                    }.accessibilityLabel("전체 초기화").accessibilityIdentifier("reset-controls")
                }.padding(.horizontal,20)
                captureButtons.padding(.top,104)
            }.frame(height: 180)
        }.padding(.bottom,8)
    }

    private var captureButtons: some View {
            HStack {
                Button {
                    showPhoto = true
                } label: {
                    Group {
                        if let thumbnail = model.lastThumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                        else { Image(systemName: "photo").font(.system(size: 22)).frame(maxWidth: .infinity,maxHeight: .infinity).background(.white.opacity(0.08)) }
                    }.frame(width: 48,height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                }.disabled(model.lastPhoto == nil || model.isRecording || model.isPreparingRecording || model.isSaving)
                    .accessibilityLabel("최근 촬영 보기").accessibilityIdentifier("recent-capture")
                Spacer()
                Button { model.pressShutter() } label: {
                    ZStack {
                        Circle().strokeBorder(.white.opacity(0.8),lineWidth: 1.5).frame(width: 76,height: 76)
                        if model.isRecording { RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 28,height: 28) }
                        else { Circle().fill(model.captureMode == .video ? .red : accent).frame(width: 64,height: 64) }
                        if model.isSaving || model.isPreparingRecording { ProgressView().tint(.white) }
                    }
                }.disabled(model.isSaving || model.isPreparingRecording || !model.hasFrame || (model.captureMode == .video && (model.isSample || model.isImported)))
                    .accessibilityLabel(model.isRecording ? "녹화 종료" : model.captureMode == .video ? "녹화 시작" : "유리 사진 촬영")
                    .accessibilityIdentifier("shutter")
                Spacer()
                Button {
                    if model.isSample || model.isImported { model.returnToCamera() } else { model.engine.flip() }
                } label: { Image(systemName: model.isSample || model.isImported ? "camera" : "arrow.triangle.2.circlepath.camera").font(.system(size: 25)).frame(width: 48,height: 54) }
                    .disabled(model.isSaving || model.isRecording || model.isPreparingRecording)
                    .accessibilityLabel(model.isSample || model.isImported ? "카메라로 돌아가기" : "전후면 카메라 전환")
            }.padding(.horizontal,32)
    }

    private var displayedControls: [GlassControl] {
        // Presentation order is independent of the material hash and saved values.
        ["pitch","relief","roundness","thickness","edge","reflection","lightAngle"].compactMap { id in
            model.material.controls.first { $0.id == id }
        }
    }

    private var selectedControl: GlassControl {
        model.material.controls.first { $0.id == selectedControlID } ?? model.material.controls[0]
    }

    private var selectedRange: ClosedRange<Double> {
        let control=selectedControl
        var lower=control.min, upper=control.max
        // The relief must fit inside the plate. Keep the dial in valid bounds
        // so dragging to an endpoint never opens an error over the camera.
        if control.id == "thickness" {
            lower=max(lower,ceil(Double(model.material.relief+model.material.microHeight+0.5001)/control.step)*control.step)
        } else if control.id == "relief" {
            upper=min(upper,floor(Double(model.material.thickness-model.material.microHeight-0.5001)/control.step)*control.step)
        }
        return lower...upper
    }

    private var recentPhoto: some View {
        NavigationStack {
            VStack {
                if let url = model.lastPhoto {
                    if url.pathExtension == "mp4" {
                        RecentVideoPlayer(url: url).id(url)
                    } else if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    HStack(spacing: 24) {
                        ShareLink(item: url) { Label("공유",systemImage: "square.and.arrow.up") }
                        Button("저장 재시도") { model.retrySave() }.disabled(model.isSaving)
                    }.padding()
                }
            }.navigationTitle("최근 촬영").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showPhoto = false } } }
        }.preferredColorScheme(.dark)
    }

    private var info: some View {
        NavigationStack {
            List {
                Section("유리 카메라") {
                    Text("눈앞의 장면을 사각 패턴 유리 너머로 바라보세요. 화면을 누르면 초점을 맞춥니다.")
                    PhotosPicker(selection: $pickerItem,matching: .images) { Label("내 사진으로 보기",systemImage: "photo.on.rectangle") }
                        .onChange(of: pickerItem) { _,value in if value != nil { showInfo = false } }
                    Button("치와와 테스트 사진") { model.loadSample(); showInfo = false }
                    Button("고양이 테스트 사진") { model.loadSample(named: "sample-cat"); showInfo = false }
                }
                Section("현재 버전") {
                    Text("실물 사진의 질감을 목표로 개발 중인 프로토타입입니다. 조명 반사는 가상 실내 조명이며 실물과의 일치는 아직 검증하지 않았습니다.")
                    Text("사진은 기기 안에서 처리합니다.")
                }
                Section("샘플 사진 출처") {
                    Text("치와와 사진은 사용자가 효과 비교를 위해 제공한 이미지입니다.")
                    Text("Orange Tabby Cat sitting on a couch · LauraDelga · CC BY 4.0. 미리보기에서 자르기와 유리 효과 적용.")
                    Link("Wikimedia Commons 원본",destination: URL(string: "https://commons.wikimedia.org/wiki/File:Orange_Tabby_Cat_sitting_on_a_couch.jpg")!)
                    Link("CC BY 4.0",destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
            }.navigationTitle("유리 너머의 시선").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showInfo = false } } }
        }.preferredColorScheme(.dark)
    }
}

private struct RecentVideoPlayer: View {
    @State private var player: AVPlayer

    init(url: URL) {
        // The sheet owns the same nonoptional player that it displays and plays.
        // Parent state set alongside presentation could leave VideoPlayer nil
        // while onAppear played the newly assigned, unattached player.
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity,maxHeight: .infinity)
            .accessibilityIdentifier("recent-video-player")
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct ProtractorDial: View {
    let control: GlassControl
    let range: ClosedRange<Double>
    @Binding var value: Double
    let accent: Color
    @GestureState private var isDragging = false

    private var fraction: Double {
        min(1,max(0,(value-range.lowerBound)/(range.upperBound-range.lowerBound)))
    }

    var body: some View {
        GeometryReader { geometry in
            let center=CGPoint(x: geometry.size.width/2,y: geometry.size.height-18)
            let radius=min(geometry.size.width/2-24,geometry.size.height-42)
            ZStack {
                Canvas { context,size in
                    var arc=Path()
                    arc.addArc(center: center,radius: radius,startAngle: .degrees(180),endAngle: .degrees(0),clockwise: false)
                    context.stroke(arc,with: .color(.white.opacity(0.12)),lineWidth: 1)
                    for index in 0...40 {
                        let progress=Double(index)/40, angle=Double.pi*(1-progress)
                        let length: CGFloat=index%5 == 0 ? 12 : 5
                        func point(_ r: CGFloat) -> CGPoint {
                            CGPoint(x: center.x+cos(angle)*r,y: center.y-sin(angle)*r)
                        }
                        var tick=Path()
                        tick.move(to: point(radius-length)); tick.addLine(to: point(radius))
                        context.stroke(tick,with: .color(progress <= fraction ? accent.opacity(0.85) : .white.opacity(0.27)),lineWidth: index%5 == 0 ? 1.5 : 1)
                    }
                    let angle=Double.pi*(1-fraction)
                    let pointer=CGPoint(x: center.x+cos(angle)*radius,y: center.y-sin(angle)*radius)
                    context.fill(Path(ellipseIn: CGRect(x: pointer.x-4,y: pointer.y-4,width: 8,height: 8)),with: .color(accent))
                }.allowsHitTesting(false)
                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline,spacing: 4) {
                        Text(value,format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 28,weight: .light,design: .monospaced)).monospacedDigit()
                        if !control.unit.isEmpty { Text(control.unit).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }.foregroundStyle(isDragging ? accent : .white)
                    Text(control.name).font(.system(size: 10)).foregroundStyle(.secondary)
                }.position(x: center.x,y: center.y-48).allowsHitTesting(false)
                HStack {
                    Text(range.lowerBound,format: .number.precision(.fractionLength(0...2)))
                    Spacer()
                    Text(range.upperBound,format: .number.precision(.fractionLength(0...2)))
                }.font(.system(size: 9,design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.horizontal,18).frame(maxHeight: .infinity,alignment: .bottom).allowsHitTesting(false)
            }
            .contentShape(DialTrack(center: center,radius: radius))
            .gesture(DragGesture(minimumDistance: 0)
                .updating($isDragging) { _,active,_ in active=true }
                .onChanged { drag in
                    let x=drag.location.x-center.x, y=max(0,center.y-drag.location.y)
                    guard hypot(x,y)>radius*0.3 else { return }
                    let progress=1-atan2(y,x)/Double.pi
                    setValue(range.lowerBound+progress*(range.upperBound-range.lowerBound))
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.name)
        .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(0...2)))) \(control.unit)")
        .accessibilityHint("반원 눈금을 드래그해 조절합니다. 위아래 쓸기로도 조절할 수 있습니다.")
        .accessibilityIdentifier("glass-dial")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value+control.step)
            case .decrement: setValue(value-control.step)
            @unknown default: break
            }
        }
    }

    private func setValue(_ proposed: Double) {
        let next=min(range.upperBound,max(range.lowerBound,(proposed/control.step).rounded()*control.step))
        if abs(next-value)>control.step*0.1 { value=next }
    }
}

private struct DialTrack: Shape {
    let center: CGPoint
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var arc=Path()
        arc.addArc(center: center,radius: radius,startAngle: .degrees(180),endAngle: .degrees(0),clockwise: false)
        return arc.strokedPath(StrokeStyle(lineWidth: 44,lineCap: .round))
    }
}

@main struct QuadraCameraApp: App {
    @State private var model: CameraModel?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { CameraView(model: model) }
                else if let startupError { ContentUnavailableView("카메라를 시작할 수 없어요",systemImage: "camera",description: Text(startupError)) }
                else { ProgressView().task { do { model = try CameraModel() } catch { startupError = error.localizedDescription } } }
            }.preferredColorScheme(.dark)
        }
    }
}
