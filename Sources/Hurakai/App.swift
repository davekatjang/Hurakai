import SwiftUI

// MARK: - State

enum Selection: Hashable {
    case storm(String)
    case disturbance(Int)
}

struct LayerToggles {
    var cone = true
    var forecastTrack = true
    var pastTrack = true
    var forecastPoints = true
    var warnings = true
    var disturbances = true
    var labels = true
}

enum Pane: String, CaseIterable, Identifiable {
    case map = "Map"
    case imagery = "Satellite & Outlook"
    case models = "Tropical Tidbits"
    case weatherLab = "DeepMind Weather Lab"
    case text = "Outlook Text"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .imagery: return "globe.americas"
        case .models: return "chart.xyaxis.line"
        case .weatherLab: return "sparkles"
        case .text: return "doc.plaintext"
        }
    }
}

@MainActor
final class Tracker: ObservableObject {
    @Published var storms: [Storm] = []
    @Published var geometry: [String: StormGeometry] = [:]
    @Published var disturbances: [Disturbance] = []
    @Published var productText: [URL: String] = [:]
    @Published var updated: Date?
    @Published var loading = false
    @Published var problems: [String] = []
    @Published var includeAtlantic = false

    var visibleStorms: [Storm] {
        storms
            .filter { includeAtlantic || $0.basin.isPacific }
            .sorted { ($0.windKt, $0.name) > ($1.windKt, $1.name) }
    }

    var visibleDisturbances: [Disturbance] {
        disturbances
            .filter { includeAtlantic || ($0.basin?.isPacific ?? true) }
            .sorted { ($0.prob7Day ?? 0) > ($1.prob7Day ?? 0) }
    }

    func storm(id: String) -> Storm? { storms.first { $0.id == id } }
    func disturbance(id: Int) -> Disturbance? { disturbances.first { $0.id == id } }
    func geometry(for storm: Storm) -> StormGeometry {
        geometry[storm.bin.uppercased()] ?? geometry["#\(storm.stormNumber)"] ?? .init()
    }

    func refresh() async {
        loading = true
        var issues: [String] = []

        do { storms = try await NHC.activeStorms() }
        catch { issues.append("NHC active storms — \(error.localizedDescription)") }

        do { geometry = try await NHC.geometry() }
        catch { issues.append("NHC forecast GIS — \(error.localizedDescription)") }

        do { disturbances = try await NHC.disturbances() }
        catch { issues.append("Tropical Weather Outlook — \(error.localizedDescription)") }

        problems = issues
        updated = Date()
        loading = false
    }

    func loadProduct(_ url: URL) async {
        do {
            let text = try await Net.text(url).nhcProductText
            productText[url] = text.isEmpty ? "No text in this product." : text
        } catch {
            productText[url] = "Could not load \(url.absoluteString)\n\n\(error.localizedDescription)"
        }
    }
}

// MARK: - App

@main
struct HurakaiApp: App {
    @StateObject private var tracker = Tracker()

    var body: some Scene {
        WindowGroup("Hurakai — Pacific Cyclone Tracker") {
            ContentView()
                .environmentObject(tracker)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1500, height: 940)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Data") { Task { await tracker.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Toggle("Include Atlantic Basin", isOn: Binding(
                    get: { tracker.includeAtlantic },
                    set: { tracker.includeAtlantic = $0 }))
            }
            CommandMenu("Sources") {
                Link("National Hurricane Center", destination: URL(string: "https://www.nhc.noaa.gov")!)
                Link("Central Pacific Hurricane Center", destination: Feed.cphc)
                Link("Tropical Tidbits", destination: Feed.tropicalTidbits)
                Link("Google DeepMind Weather Lab", destination: Feed.deepMindWeatherLab)
                Divider()
                Link("GOES-West Imagery (NESDIS)", destination: Feed.goesWestFullDisk)
            }
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var selection: Selection?
    @State private var pane: Pane = .map
    @State private var layers = LayerToggles()
    @State private var mapStyleChoice = MapStyleChoice.hybrid

    var body: some View {
        NavigationSplitView {
            SystemList(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            VStack(spacing: 0) {
                PaneBar(pane: $pane)
                Divider()
                content
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup {
                if tracker.loading { ProgressView().controlSize(.small) }
                Text(updatedLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    Task { await tracker.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload every source (⌘R)")

                LayerMenu(layers: $layers, style: $mapStyleChoice)
            }
        }
        .task {
            await tracker.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                if Task.isCancelled { break }
                await tracker.refresh()
            }
        }
        .onChange(of: selection) { _, new in
            if new != nil, pane != .map, pane != .models { pane = .map }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .map:
            HStack(spacing: 0) {
                StormMap(selection: $selection, layers: $layers, styleChoice: $mapStyleChoice)
                if selection != nil {
                    Divider()
                    Inspector(selection: $selection)
                        .frame(width: 400)
                }
            }
        case .imagery:
            ImageryPane()
        case .models:
            ModelsPane(selection: selection)
        case .weatherLab:
            WeatherLabPane()
        case .text:
            OutlookTextPane()
        }
    }

    private var updatedLabel: String {
        guard let updated = tracker.updated else { return "loading…" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "updated \(f.string(from: updated))"
    }
}

struct PaneBar: View {
    @Binding var pane: Pane

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Pane.allCases) { p in
                Button {
                    pane = p
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: p.symbol)
                        Text(p.rawValue)
                    }
                    .font(.system(size: 12, weight: pane == p ? .semibold : .regular))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(pane == p ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(pane == p ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct LayerMenu: View {
    @Binding var layers: LayerToggles
    @Binding var style: MapStyleChoice
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        Menu {
            Picker("Base Map", selection: $style) {
                ForEach(MapStyleChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Forecast Cone", isOn: $layers.cone)
            Toggle("Forecast Track", isOn: $layers.forecastTrack)
            Toggle("Forecast Points", isOn: $layers.forecastPoints)
            Toggle("Past Track", isOn: $layers.pastTrack)
            Toggle("Watches & Warnings", isOn: $layers.warnings)
            Toggle("Disturbance Areas", isOn: $layers.disturbances)
            Toggle("Labels", isOn: $layers.labels)
            Divider()
            Toggle("Include Atlantic Basin", isOn: $tracker.includeAtlantic)
        } label: {
            Label("Layers", systemImage: "square.3.layers.3d")
        }
    }
}
