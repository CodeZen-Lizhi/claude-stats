import AppKit
import SpriteKit
import SwiftUI

struct TokenTownView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var town = env.town

        ZStack(alignment: .topLeading) {
            Color.stxBackground.ignoresSafeArea()

            if let map = town.map {
                TokenTownSpriteView(
                    map: map,
                    state: town.state,
                    isPaused: town.isPaused,
                    onSelect: { town.select($0) },
                    onCameraChanged: { town.setCamera($0) }
                )
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    hud(map: map, town: town)
                        .padding(.leading, 22)
                        .padding(.top, 22)
                }
                .overlay(alignment: .trailing) {
                    inspector(map: map, town: town)
                        .frame(width: 286)
                        .padding(.trailing, 18)
                        .padding(.vertical, 22)
                }
                .overlay(alignment: .bottomLeading) {
                    thoughtBubble(town: town)
                        .padding(.leading, 22)
                        .padding(.bottom, 20)
                }
            } else {
                loadingView
            }

            if town.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(Color.stxPanel.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.leading, 22)
                    .padding(.top, 92)
            }
        }
        .sheet(isPresented: $town.shopPresented) {
            shopSheet(town: town)
                .frame(width: 560, height: 520)
        }
        .task {
            await town.loadIfNeeded(from: env.store, provider: env.preferences.selectedProvider)
        }
        .onChange(of: town.period) { _, _ in
            Task { await town.refresh(from: env.store, provider: env.preferences.selectedProvider) }
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            Task { await town.refresh(from: env.store, provider: env.preferences.selectedProvider) }
        }
        .onChange(of: env.preferences.selectedProvider) { _, provider in
            Task { await town.refresh(from: env.store, provider: provider) }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Raising the first streets")
                .font(.sora(13, weight: .semibold))
            Text("Token Town builds only from local usage metadata.")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hud(map: TownMap, town: TownStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Token Town", systemImage: MainPage.town.symbol)
                    .font(.sora(16, weight: .semibold))
                Text(map.weather.displayName)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 8) {
                statPill(title: "Coins", value: town.balanceText, symbol: "circle.hexagongrid")
                statPill(title: "Today", value: "\(TownEconomy.coins(forEffectiveTokens: map.snapshot.todayEffectiveTokens))", symbol: "sun.max")
                statPill(title: "Tokens", value: Format.tokens(map.snapshot.effectiveTokens), symbol: "bolt")
            }

            HStack(spacing: 8) {
                Picker("Period", selection: Binding(
                    get: { town.period },
                    set: { town.period = $0 }
                )) {
                    ForEach(StatsPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 312)

                iconButton("Shop", symbol: "cart") { town.shopPresented = true }
                iconButton(town.isPaused ? "Resume" : "Pause", symbol: town.isPaused ? "play.fill" : "pause.fill") {
                    town.isPaused.toggle()
                }
                iconButton("Zoom out", symbol: "minus.magnifyingglass") {
                    town.setCameraScale(town.state.camera.scale - 0.15)
                }
                iconButton("Zoom in", symbol: "plus.magnifyingglass") {
                    town.setCameraScale(town.state.camera.scale + 0.15)
                }
            }

            if let error = town.lastError {
                Text(error)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxAccent)
            } else if map.snapshot.isEmpty {
                Text("Sleeping town: refresh after sessions appear to light the windows.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private func inspector(map: TownMap, town: TownStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSPECTOR")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Button {
                    town.resetLayout()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .help("Reset placed objects")
            }

            Divider()

            selectedContent(map: map, town: town)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Town")
                    .font(.sora(12, weight: .semibold))
                metricRow("Provider", map.snapshot.provider.shortName)
                metricRow("Sessions", "\(map.snapshot.sessionCount)")
                metricRow("Messages", Format.tokens(map.snapshot.messageCount))
                metricRow("Cache visual", Format.tokens(map.snapshot.cacheReadTokens))
                metricRow("Validation", map.validation.ok ? "Connected" : "Repaired")
                metricRow("Items", "\(town.state.placedItems.count)")
            }

            if !map.secrets.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("Secrets")
                        .font(.sora(12, weight: .semibold))
                    ForEach(map.secrets, id: \.self) { secret in
                        Button {
                            town.discover(secret)
                        } label: {
                            HStack {
                                Image(systemName: town.state.discoveredSecrets.contains(secret) ? "sparkles" : "questionmark.diamond")
                                Text(secret.replacingOccurrences(of: "-", with: " "))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(town.state.discoveredSecrets.contains(secret) ? Color.stxAccent : Color.stxMuted)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .font(.sora(11))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func selectedContent(map: TownMap, town: TownStore) -> some View {
        if let building = town.selectedBuilding {
            VStack(alignment: .leading, spacing: 8) {
                Label(building.kind.displayName, systemImage: "building.2")
                    .font(.sora(13, weight: .semibold))
                if let label = building.sourceLabel {
                    Text(label)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }
                metricRow("District", building.district.displayName)
                metricRow("Weight", Format.tokens(building.tokenWeight))
                metricRow("Door", "\(building.entrance.x), \(building.entrance.y)")
            }
        } else if let item = town.selectedPlacedItem {
            VStack(alignment: .leading, spacing: 8) {
                Label(item.kind.displayName, systemImage: item.kind.systemSymbol)
                    .font(.sora(13, weight: .semibold))
                metricRow("Footprint", "\(item.footprint.size.width)x\(item.footprint.size.height)")
                metricRow("Placed", Format.shortDate(item.purchasedAt))
            }
        } else if case .resident = town.selectedEntity {
            VStack(alignment: .leading, spacing: 8) {
                Label("Town resident", systemImage: "figure.walk")
                    .font(.sora(13, weight: .semibold))
                metricRow("Activity", town.state.residentMemory.lastActivity.displayName)
                Text(town.state.residentMemory.thought)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        } else if case .tile(let point) = town.selectedEntity, map.grid.contains(point) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Tile \(point.x), \(point.y)", systemImage: "square.grid.3x3")
                    .font(.sora(13, weight: .semibold))
                metricRow("Kind", map.grid[point].rawValue)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("No selection", systemImage: "cursorarrow")
                    .font(.sora(13, weight: .semibold))
                Text("Click buildings, residents, items, or tiles in the town.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private func thoughtBubble(town: TownStore) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .foregroundStyle(Color.stxAccent)
            Text(town.state.residentMemory.thought)
                .font(.sora(11))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private func shopSheet(town: TownStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Town Shop")
                    .font(.sora(18, weight: .semibold))
                Spacer()
                Text("\(town.state.balance) coins")
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.stxAccent)
            }

            AppScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(town.shopItems) { item in
                        shopItemCard(item, town: town)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(18)
        .background(Color.stxBackground)
    }

    private func shopItemCard(_ item: TownShopItem, town: TownStore) -> some View {
        Button {
            town.buy(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: item.kind.systemSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.stxAccent)
                        .frame(width: 28, height: 28)
                    Spacer()
                    Text("\(item.cost)")
                        .font(.sora(11, weight: .semibold).monospacedDigit())
                }
                Text(item.kind.displayName)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(item.footprint.widthText) lot · \(item.affordances.map(\.rawValue).joined(separator: ", "))")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(town.state.balance >= item.cost ? Color.stxStroke : Color.stxStroke.opacity(0.45), lineWidth: 1))
            .opacity(town.state.balance >= item.cost ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(town.state.balance < item.cost)
    }

    private func statPill(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.sora(8, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Text(value)
                    .font(.sora(11, weight: .semibold).monospacedDigit())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func iconButton(_ help: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(help)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Color.stxMuted)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.sora(10))
    }
}

private struct TokenTownSpriteView: NSViewRepresentable {
    let map: TownMap
    let state: TownState
    let isPaused: Bool
    let onSelect: (TownEntitySelection?) -> Void
    let onCameraChanged: (TownCameraState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TokenTownMapSKView {
        let view = TokenTownMapSKView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.presentScene(context.coordinator.scene)
        return view
    }

    func updateNSView(_ nsView: TokenTownMapSKView, context: Context) {
        nsView.configure(
            scene: context.coordinator.scene,
            map: map,
            state: state,
            isPaused: isPaused,
            onSelect: onSelect,
            onCameraChanged: onCameraChanged
        )
    }

    @MainActor
    final class Coordinator {
        let scene = TokenTownScene(size: CGSize(width: 760, height: 520))
    }
}

@MainActor
private final class TokenTownMapSKView: SKView {
    private weak var townScene: TokenTownScene?
    private var map: TownMap?
    private var state: TownState?
    private var cameraState = TownCameraState()
    private var onSelect: ((TownEntitySelection?) -> Void)?
    private var onCameraChanged: ((TownCameraState) -> Void)?
    private var lastDragLocation: CGPoint?
    private var dragDistance: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    func configure(
        scene: TokenTownScene,
        map: TownMap,
        state: TownState,
        isPaused: Bool,
        onSelect: @escaping (TownEntitySelection?) -> Void,
        onCameraChanged: @escaping (TownCameraState) -> Void
    ) {
        self.townScene = scene
        self.map = map
        self.state = state
        self.cameraState = normalized(state.camera)
        self.onSelect = onSelect
        self.onCameraChanged = onCameraChanged

        if scene.view !== self {
            presentScene(scene)
        }
        scene.onSelect = onSelect
        scene.pausedAnimation = isPaused
        scene.configure(map: map, state: state, viewportSize: bounds.size)
    }

    override func layout() {
        super.layout()
        guard let scene = townScene, let map, let state else { return }
        cameraState = normalized(cameraState)
        scene.configure(map: map, state: state.withCamera(cameraState), viewportSize: bounds.size)
        onCameraChanged?(cameraState)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = convert(event.locationInWindow, from: nil)
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let previous = lastDragLocation else {
            lastDragLocation = location
            return
        }
        let delta = CGPoint(x: location.x - previous.x, y: location.y - previous.y)
        dragDistance += hypot(delta.x, delta.y)
        lastDragLocation = location
        updateCamera(
            TownCameraMath.panned(
                cameraState,
                deltaViewX: Double(delta.x),
                deltaViewY: Double(delta.y),
                viewport: viewport
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer { lastDragLocation = nil }
        guard dragDistance < 4, let scene = townScene else { return }
        let location = convert(event.locationInWindow, from: nil)
        scene.select(at: scene.convertPoint(fromView: location))
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        zoom(factor: 1 + Double(event.magnification), at: location)
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
        guard delta != 0 else { return }
        zoom(factor: pow(1.0018, Double(delta)), at: location)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func zoom(factor: Double, at viewLocation: CGPoint) {
        guard let scene = townScene else { return }
        let worldLocation = scene.convertPoint(fromView: viewLocation)
        updateCamera(
            TownCameraMath.zoomed(
                cameraState,
                factor: factor,
                anchorX: Double(worldLocation.x),
                anchorY: Double(worldLocation.y),
                viewport: viewport
            )
        )
    }

    private func updateCamera(_ camera: TownCameraState) {
        let normalizedCamera = normalized(camera)
        guard normalizedCamera != cameraState else { return }
        cameraState = normalizedCamera
        townScene?.applyCamera(normalizedCamera)
        onCameraChanged?(normalizedCamera)
    }

    private func normalized(_ camera: TownCameraState) -> TownCameraState {
        TownCameraMath.normalized(camera, viewport: viewport)
    }

    private var viewport: TownCameraViewport {
        let world = townScene?.worldBounds ?? .zero
        return TownCameraViewport(
            viewWidth: Double(max(1, bounds.width)),
            viewHeight: Double(max(1, bounds.height)),
            worldWidth: Double(max(1, world.width)),
            worldHeight: Double(max(1, world.height))
        )
    }
}

private extension TownSize {
    var widthText: String { "\(width)x\(height)" }
}

private extension TownState {
    func withCamera(_ camera: TownCameraState) -> TownState {
        var copy = self
        copy.camera = camera
        return copy
    }
}

#if DEBUG
#Preview("Token Town") {
    let env = AppEnvironment.preview()
    return TokenTownView()
        .environment(env)
        .frame(width: 1040, height: 720)
}
#endif
