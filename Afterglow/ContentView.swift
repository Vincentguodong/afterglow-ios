import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraService()
    @State private var picker: PhotosPickerItem?
    @State private var zoom: CGFloat = 1
    @State private var grid = true
    @State private var compare = false
    @State private var selectedPhoto: SavedPhoto?
    @State private var showingInfo = false
    @State private var showingPicker = false
    @State private var didInitialize = false
    @State private var shareItem: ShareItem?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    switch model.tab {
                    case .camera: cameraPage(height: max(210, min(350, geometry.size.height - 480)))
                    case .darkroom: darkroomPage(height: min(380, geometry.size.height * 0.48))
                    case .roll: rollPage
                    }
                }.padding(.top, 10).padding(.bottom, 24)
            }.scrollIndicators(.hidden).disabled(model.busy)
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.cream)
        .safeAreaInset(edge: .bottom, spacing: 0) { navigation }
        .task { await model.initialize(); didInitialize = true; camera.updateRecipe(model.recipe); syncCamera() }
        .onChange(of: model.tab) { _, tab in if tab == .darkroom { compare = false }; syncCamera() }
        .onChange(of: scenePhase) { _, phase in
            syncCamera()
            if phase != .active && didInitialize { Task { await model.flushSettings() } }
        }
        .onChange(of: model.busy) { _, _ in syncCamera() }
        .onChange(of: showingInfo) { _, _ in syncCamera() }
        .onChange(of: showingPicker) { _, _ in syncCamera() }
        .onChange(of: selectedPhoto?.id) { _, _ in syncCamera() }
        .onChange(of: shareItem?.id) { _, _ in syncCamera() }
        .onChange(of: camera.isFrontCamera) { _, _ in zoom = 1 }
        .onChange(of: model.recipe) { _, recipe in camera.updateRecipe(recipe); model.renderPreview() }
        .onChange(of: picker) { _, item in
            guard let item else { return }
            Task { await model.importPhoto(item); picker = nil }
        }
        .onChange(of: camera.error) { _, error in if let error { model.error = error; camera.error = nil } }
        .sheet(item: $selectedPhoto) { photo in PhotoDetail(photo: photo).environmentObject(model) }
        .sheet(isPresented: $showingInfo) { information }
        .sheet(item: $shareItem) { item in PhotoShareSheet(url: item.url) }
        .photosPicker(isPresented: $showingPicker, selection: $picker, matching: .images)
        .onDisappear { camera.stop() }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay {
            if model.busy {
                ProgressView("正在处理照片…")
                    .font(.callout).tint(Palette.cream).padding(22)
                    .background(Palette.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("正在处理照片，请稍候")
            }
        }
        .overlay(alignment: .top) {
            if let message = model.message {
                Text(message).font(.callout).padding(14)
                    .background(Palette.cream, in: Capsule()).foregroundStyle(Palette.background)
                    .padding(.top, 6)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(3))
                        if model.message == message { model.message = nil }
                    }
                    .onTapGesture { model.message = nil }
            }
        }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("余光").font(.system(size: 29, weight: .medium, design: .serif))
                    Circle().fill(Palette.orange).frame(width: 6, height: 6)
                }
                Text("A F T E R G L O W").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(model.tab == .darkroom ? "THE DARKROOM" : model.tab == .roll ? "YOUR CONTACT SHEET" : "A LITTLE LIGHT, KEPT.")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                Button { showingInfo = true } label: { Image(systemName: "info.circle").font(.system(size: 18)).frame(width: 44, height: 36) }
                    .accessibilityLabel("关于余光").disabled(model.busy || camera.capturing || camera.switching)
            }.foregroundStyle(Palette.muted)
        }.padding(.horizontal, 24)
    }
    private func cameraPage(height: CGFloat) -> some View {
        VStack(spacing: 18) {
            FilmFrame(height: height, stock: model.recipe.stock) {
                GeometryReader { viewport in
                    ZStack {
                        if let frame = camera.frame, camera.status == .ready {
                            Image(uiImage: frame).resizable().scaledToFill()
                        } else {
                            Image("Demo").resizable().scaledToFill().overlay(.black.opacity(0.3))
                        }
                        if grid {
                            GeometryReader { proxy in
                                Path { path in
                                    for i in 1...2 {
                                        let x = proxy.size.width * CGFloat(i) / 3
                                        let y = proxy.size.height * CGFloat(i) / 3
                                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                                    }
                                }.stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }.allowsHitTesting(false)
                        }
                        if camera.status != .ready {
                            VStack(spacing: 10) {
                                Text(camera.status == .denied ? "让光进来" : camera.status == .interrupted ? "相机暂时被占用" : "把此刻，留在胶片里")
                                    .font(.system(size: 21, weight: .medium, design: .serif))
                                Button(camera.status == .denied ? "前往设置" : "开启相机") {
                                    if camera.status == .denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                    else { camera.start(requestPermission: true) }
                                }.buttonStyle(.borderedProminent).tint(Palette.cream).foregroundStyle(Palette.background)
                                    .disabled(model.busy || camera.capturing || camera.switching)
                                Text("背景为 AI 示例照片").font(.caption2).foregroundStyle(.white.opacity(0.75))
                            }.padding(20).background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }.overlay(alignment: .top) {
                        HStack {
                            Text(camera.status == .ready ? "● LIVE" : "DEMO").foregroundStyle(camera.status == .ready ? .green : Palette.cream)
                            Spacer()
                            Button { grid.toggle() } label: { Image(systemName: "grid").frame(width: 44, height: 44) }
                                .accessibilityLabel(grid ? "关闭网格" : "显示网格")
                        }.font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.leading, 14).padding(.trailing, 4)
                    }
                    .frame(width: viewport.size.width, height: viewport.size.height).clipped()
                    .onAppear { updateViewfinderSize(viewport.size) }
                    .onChange(of: viewport.size) { _, size in updateViewfinderSize(size) }
                }
            }.padding(.horizontal, 16)
            HStack(spacing: 8) {
                ForEach([CGFloat(1), CGFloat(2)], id: \.self) { value in
                    Button { zoom = value; camera.setZoom(value) } label: {
                        Text(value == 1 ? "1×" : "2×").font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(zoom == value ? Palette.cream : Palette.panel, in: Capsule())
                            .foregroundStyle(zoom == value ? Palette.background : Palette.muted)
                    }.buttonStyle(.plain)
                        .disabled(camera.status != .ready || camera.capturing || camera.switching || model.busy)
                        .accessibilityLabel(value == 1 ? "1 倍取景" : "2 倍数码变焦")
                }
                Spacer(minLength: 0)
                Text(camera.isFrontCamera ? "前置 · 取景裁切" : "后置 · 取景裁切")
                    .font(.system(size: 9, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(Palette.muted)
                Button { camera.switchCamera() } label: {
                    if camera.switching { ProgressView().frame(width: 40, height: 40) }
                    else { Image(systemName: "camera.rotate").frame(width: 40, height: 40) }
                }.accessibilityLabel(camera.isFrontCamera ? "切换到后置相机" : "切换到前置相机")
                    .disabled(camera.status != .ready || camera.capturing || camera.switching || model.busy)
            }.padding(.horizontal, 24)
            FilmRail(selected: $model.recipe.stock).disabled(model.busy || camera.capturing || camera.switching)
            dials
            HStack {
                importControl
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    camera.capture { result in
                        switch result {
                        case .success(let data): Task { do { try await model.accept(data) } catch { model.error = error.localizedDescription } }
                        case .failure(let error): model.error = error.localizedDescription
                        }
                    }
                } label: {
                    ZStack {
                        Circle().stroke(Palette.cream.opacity(0.7), lineWidth: 2).frame(width: 78, height: 78)
                        Circle().fill(Palette.cream).frame(width: 64, height: 64)
                        if camera.capturing { ProgressView().tint(Palette.background) }
                        else { Circle().stroke(Palette.background.opacity(0.15), lineWidth: 1).frame(width: 54, height: 54) }
                    }
                }.disabled(camera.status != .ready || camera.capturing || camera.switching || model.busy).opacity(camera.status == .ready ? 1 : 0.45)
                    .accessibilityLabel("拍摄照片")
                Spacer()
                Button { useSample() } label: {
                    VStack(spacing: 6) { Image(systemName: "sparkles.rectangle.stack").font(.title3); Text("试用示例").font(.system(size: 10)) }.frame(width: 64, height: 60)
                }.foregroundStyle(Palette.muted).disabled(model.busy || camera.capturing || camera.switching)
            }.padding(.horizontal, 34)
        }
    }
    private var dials: some View {
        HStack(spacing: 0) {
            RotaryDial(title: "曝光 EV", value: $model.recipe.exposure, range: -2...2, step: 0.1, display: String(format: "%+.1f", model.recipe.exposure), color: Palette.orange)
            Spacer(minLength: 0)
            RotaryDial(title: "颗粒 GRAIN", value: $model.recipe.grain, range: 0...1, step: 0.02, display: "\(Int(model.recipe.grain * 100))")
            Spacer(minLength: 0)
            RotaryDial(title: "色温 WARMTH", value: $model.recipe.warmth, range: -1...1, step: 0.05, display: String(format: "%+.0f", model.recipe.warmth * 100))
        }.padding(.horizontal, 22).disabled(model.busy || camera.capturing || camera.switching)
    }
    private func darkroomPage(height: CGFloat) -> some View {
        VStack(spacing: 22) {
            HStack {
                Circle().fill(Palette.orange).frame(width: 7, height: 7)
                Text("暗房已亮灯").font(.system(size: 12))
                Spacer()
                Text("慢一点，让颜色显影。").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 24)
            if model.hasDraft {
                FilmFrame(height: height, stock: model.recipe.stock) {
                    ZStack {
                        if let image = compare ? model.originalPreview : (model.developed ?? model.originalPreview) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                        if model.rendering { ProgressView().padding(10).background(.black.opacity(0.5), in: Circle()) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.padding(.horizontal, 16)
                HStack {
                    Text(model.recipe.stock.note).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { compare.toggle() } label: {
                        Label(compare ? "查看冲洗" : "对比原片", systemImage: "circle.lefthalf.filled")
                            .font(.system(size: 12)).frame(minHeight: 44)
                    }.accessibilityValue(compare ? "当前显示原片" : "当前显示冲洗效果")
                }.padding(.horizontal, 24)
                FilmRail(selected: $model.recipe.stock).disabled(model.busy)
                dials
                VStack(spacing: 16) {
                    adjustment("褪色", value: $model.recipe.fade)
                    adjustment("暗角", value: $model.recipe.vignette)
                    adjustment("漏光", value: $model.recipe.lightLeak)
                }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).disabled(model.busy)
                HStack {
                    Button("重置配方") { model.recipe = FilmRecipe(stock: model.recipe.stock); compare = false }.font(.callout)
                    Spacer()
                    importControl
                }.padding(.horizontal, 24).disabled(model.busy)
                ActionButton(title: model.busy ? "正在冲洗…" : "冲洗入卷", icon: "sparkles", busy: model.busy) { Task { await model.develop() } }
                    .padding(.horizontal, 20).disabled(!model.canDevelop).opacity(model.canDevelop || model.busy ? 1 : 0.5)
                Button {
                    Task { if let url = await model.prepareDraftShare() { shareItem = ShareItem(url: url) } }
                } label: {
                    Label("直接导出当前照片", systemImage: "square.and.arrow.up").font(.callout).frame(minHeight: 44)
                }.disabled(model.busy || model.rendering)
                Text(model.draftStatus).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Text("原片独立保留 · 最长边 4096 像素 JPEG").font(.system(size: 10)).foregroundStyle(Palette.muted)
            } else {
                Image("Demo").resizable().scaledToFill().frame(height: height).clipped().cornerRadius(12).padding(.horizontal, 20)
                Text("每一张，都有自己的颜色。") .font(.system(size: 22, design: .serif))
                Button { showingPicker = true } label: { Label("从相册选一张", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(18).background(Palette.cream, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Palette.background) }.padding(.horizontal, 20).disabled(model.busy)
                Button("使用 AI 示例照片") { useSample() }.font(.callout)
            }
        }
    }
    private func adjustment(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 12)).frame(width: 30)
            Slider(value: value, in: 0...1).tint(Palette.cream).accessibilityLabel(label)
            Text("\(Int(value.wrappedValue * 100))").font(.system(size: 11, design: .monospaced)).monospacedDigit().frame(width: 24)
        }
    }
    private var rollPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("留下的光").font(.system(size: 28, weight: .medium, design: .serif))
                Spacer()
                Text(String(format: "%03d FRAMES", model.photos.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            if model.photos.isEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Palette.muted)
                    Text("第一卷，从今天开始。") .font(.system(size: 21, design: .serif))
                    Text("拍摄或导入照片，在暗房冲洗后，\n它们会留在这里。").font(.callout).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
                    Button("去拍一张") { model.tab = .camera }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 70)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        Button { selectedPhoto = photo } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                PhotoThumbnail(photo: photo, repository: model.repository)
                                    .aspectRatio(0.75, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 5))
                                HStack { Text(String(format: "%02d", model.photos.count - index)); Spacer(); Text(photo.recipe.stock.code) }
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(photo.recipe.stock.tint)
                            }.padding(8).background(.black, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("\(photo.recipe.stock.name)，\(photo.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
            Text("保存在 App 本机空间 · 原片与冲洗照片独立保留").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 20)
    }
    private var importControl: some View {
        Button { showingPicker = true } label: {
            VStack(spacing: 6) { Image(systemName: "photo.on.rectangle.angled").font(.title3); Text("导入照片").font(.system(size: 10)) }.frame(width: 64, height: 60)
        }.foregroundStyle(Palette.muted).disabled(model.busy || camera.capturing || camera.switching)
    }
    private var navigation: some View {
        HStack(spacing: 0) {
            ForEach(AppModel.Tab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab == .camera ? "camera" : tab == .darkroom ? "slider.horizontal.3" : "square.stack").font(.system(size: 20, weight: .light))
                        Text(tab.rawValue).font(.system(size: 11))
                    }.frame(maxWidth: .infinity).frame(height: 63)
                        .foregroundStyle(model.tab == tab ? Palette.orange : Palette.muted)
                }.buttonStyle(.plain).accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }.background(Palette.background.opacity(0.97)).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            .disabled(model.busy || camera.capturing || camera.switching)
    }
    private var information: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("余光 / AFTERGLOW").font(.title)
                    Text("把匆忙的日子，拍得慢一点。") .font(.title3)
                    Text("六款原创胶片配方、实体手感转盘，以及属于你的数字暗房。拍摄后进入暗房，冲洗入卷，再保存到系统相册。")
                    Text("隐私\n照片处理在设备本地进行，无账号、无广告、无分析 SDK。导入使用系统照片选择器；只有拍摄和保存相册时才请求对应权限。照片不会由本 App 上传。设备系统备份行为由你的 iOS 设置决定。")
                    Text("版本 1.1.0 · 原生个人测试版\n支持前后摄切换，拍照按当前取景框裁切；2× 为数码变焦。输出为最长边 4096 像素的 sRGB JPEG。当前不包含 RAW、视频、超广角和独立长焦切换。")
                    Text("草稿与胶卷保存在 App 本机空间。系统分享可导出冲洗照片和原片；请将重要照片另存到系统相册或文件。删除 App 会移除其本机数据。")
                    Text("示例照片由 AI 生成，仅用于体验。色彩配方为原创风格，不代表任何商业胶卷品牌。")
                }.padding(24)
            }.background(Palette.background).navigationTitle("关于")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingInfo = false } } }
        }.preferredColorScheme(.dark)
    }
    private func useSample() {
        guard let data = UIImage(named: "Demo")?.jpegData(compressionQuality: 0.95) else { return }
        Task { do { try await model.accept(data) } catch { model.error = error.localizedDescription } }
    }
    private func updateViewfinderSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        camera.setPreviewAspectRatio(size.width / size.height)
    }
    private func syncCamera() {
        if didInitialize && scenePhase == .active && model.tab == .camera && !model.busy && !showingInfo && !showingPicker && selectedPhoto == nil && shareItem == nil {
            camera.start()
        } else { camera.stop() }
    }
}

struct PhotoThumbnail: View {
    let photo: SavedPhoto
    let repository: PhotoRepository
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.panel
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Palette.muted) }
                else { ProgressView() }
            }
        }.task(id: photo.id) {
            do { image = try await repository.thumbnail(for: photo) } catch { failed = true }
        }
    }
}

struct PhotoDetail: View {
    let photo: SavedPhoto
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false
    @State private var shareItem: ShareItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)) }
                    else { ProgressView().frame(height: 300) }
                    Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.muted)
                    ActionButton(title: "保存到系统相册", icon: "square.and.arrow.down", busy: model.busy) { Task { await model.export(photo) } }.disabled(model.busy || image == nil)
                    HStack(spacing: 20) {
                        Button {
                            Task { if let url = await model.prepareShare(photo) { shareItem = ShareItem(url: url) } }
                        } label: { Label("分享成片", systemImage: "square.and.arrow.up") }
                        Button {
                            Task { if let url = await model.prepareShare(photo, original: true) { shareItem = ShareItem(url: url) } }
                        } label: { Label("导出原片", systemImage: "doc") }
                    }.font(.callout).disabled(model.busy || image == nil)
                    Text("导出原片会保留原始文件，可能包含拍摄位置等元数据。")
                        .font(.footnote).foregroundStyle(Palette.muted)
                    Button("使用原片重新冲洗") { Task { if await model.edit(photo) { dismiss() } } }.disabled(model.busy)
                    Button("从胶卷中删除", role: .destructive) { confirmDelete = true }.disabled(model.busy)
                    if let message = model.message { Text(message).font(.callout).foregroundStyle(Palette.cream) }
                    if let error = model.error { Text(error).font(.callout).foregroundStyle(Palette.orange) }
                }.padding(20)
            }.background(Palette.background).navigationTitle(photo.recipe.stock.name)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("删除此胶卷版本及其原片？暗房草稿、分享副本和系统相册中的照片不受影响。", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { Task { if await model.remove(photo) { dismiss() } } }
                }
                .task {
                    do { let data = try await model.repository.data(for: photo); image = try FilmRenderer.decode(data, maxEdge: 1800) }
                    catch { model.error = error.localizedDescription }
                }
        }.preferredColorScheme(.dark).tint(Palette.orange)
            .sheet(item: $shareItem) { item in PhotoShareSheet(url: item.url) }
            .interactiveDismissDisabled(model.busy)
    }
}
