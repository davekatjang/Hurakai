import SwiftUI
import WebKit

// MARK: - Sidebar

struct SystemList: View {
    @EnvironmentObject var tracker: Tracker
    @Binding var selection: Selection?

    var body: some View {
        List(selection: $selection) {
            Section("Active Systems") {
                if tracker.visibleStorms.isEmpty {
                    Text(tracker.loading ? "Loading…" : "No active cyclones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(tracker.visibleStorms) { storm in
                    StormRow(storm: storm).tag(Selection.storm(storm.id))
                }
            }

            Section("Tropical Weather Outlook") {
                if tracker.visibleDisturbances.isEmpty {
                    Text(tracker.loading ? "Loading…" : "No areas of interest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(tracker.visibleDisturbances) { d in
                    DisturbanceRow(disturbance: d).tag(Selection.disturbance(d.id))
                }
            }

            if !tracker.problems.isEmpty {
                Section("Feed Problems") {
                    ForEach(tracker.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()
            Text("NHC · CPHC · NOAA GIS · NESDIS")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(tracker.updated.map { "Last poll \($0.formatted(date: .omitted, time: .standard))" }
                 ?? "Never polled")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("Auto-refresh every 10 min")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StormRow: View {
    let storm: Storm

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(storm.tint).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(storm.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(storm.basin.rawValue)
                        .font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                Text(storm.headline)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(storm.windKt) kt / \(storm.windMph) mph" +
                     (storm.pressureMb.map { " · \($0) mb" } ?? ""))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(storm.tint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct DisturbanceRow: View {
    let disturbance: Disturbance

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.risk(disturbance.risk7Day ?? disturbance.risk2Day))
                .frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(disturbance.basin.map { "\($0.rawValue) disturbance" } ?? "Disturbance")
                    .font(.system(size: 12, weight: .medium))
                Text("2-day \(disturbance.prob2Day.map { "\($0)%" } ?? "—") · " +
                     "7-day \(disturbance.prob7Day.map { "\($0)%" } ?? "—")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Inspector

private enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case forecast = "Forecast"
    case models = "Models"
    case advisory = "Advisory"
    case discussion = "Discussion"
    var id: String { rawValue }
}

struct Inspector: View {
    @EnvironmentObject var tracker: Tracker
    @Binding var selection: Selection?
    @State private var tab: InspectorTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch selection {
            case .storm(let id):
                if let storm = tracker.storm(id: id) {
                    Picker("", selection: $tab) {
                        ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)
                    Divider()
                    stormBody(storm)
                } else {
                    placeholder("Storm no longer in the feed.")
                }
            case .disturbance(let id):
                if let d = tracker.disturbance(id: id) {
                    disturbanceBody(d)
                } else {
                    placeholder("Disturbance no longer in the outlook.")
                }
            case .none:
                placeholder("Select a system.")
            }
        }
    }

    private var header: some View {
        HStack {
            if case .storm(let id) = selection, let storm = tracker.storm(id: id) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(storm.name.uppercased())
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    Text(storm.headline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(storm.tint)
                    Text("\(storm.basin.label) · \(storm.id.uppercased())" +
                         (storm.advisoryNumber.map { " · Adv \($0)" } ?? ""))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Details").font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button {
                selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stormBody(_ storm: Storm) -> some View {
        switch tab {
        case .overview: StormOverview(storm: storm)
        case .forecast: ForecastList(storm: storm)
        case .models: ModelGuidance(storm: storm)
        case .advisory:
            ProductText(url: storm.products.first { $0.name == "Public Advisory" }?.url,
                        missing: "No public advisory for this system.")
        case .discussion:
            ProductText(url: storm.products.first { $0.name == "Forecast Discussion" }?.url,
                        missing: "No forecast discussion for this system.")
        }
    }

    @ViewBuilder
    private func disturbanceBody(_ d: Disturbance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Area of Interest")
                    .font(.system(size: 15, weight: .bold))
                StatGrid(rows: [
                    ("Basin", d.basin?.label ?? "Unknown"),
                    ("48-hour chance", d.prob2Day.map { "\($0)%" } ?? "—"),
                    ("7-day chance", d.prob7Day.map { "\($0)%" } ?? "—"),
                    ("48-hour risk", d.risk2Day?.capitalized ?? "—"),
                    ("7-day risk", d.risk7Day?.capitalized ?? "—"),
                    ("Position", format(d.coord))
                ])
                Text("Formation chances come from the NHC/CPHC Graphical Tropical Weather Outlook. "
                     + "Read the full discussion in the Outlook Text pane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }
}

private func format(_ c: Coord) -> String {
    let ns = c.latitude >= 0 ? "N" : "S"
    let ew = c.longitude >= 0 ? "E" : "W"
    return String(format: "%.1f°%@ %.1f°%@", abs(c.latitude), ns, abs(c.longitude), ew)
}

struct StatGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    Text(row.1)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct StormOverview: View {
    @EnvironmentObject var tracker: Tracker
    let storm: Storm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatGrid(rows: [
                    ("Max sustained", "\(storm.windKt) kt · \(storm.windMph) mph"),
                    ("Min pressure", storm.pressureMb.map { "\($0) mb" } ?? "—"),
                    ("Movement", storm.movementText),
                    ("Position", format(storm.coord)),
                    ("Classification", storm.typeLabel),
                    ("Advisory", storm.advisoryNumber ?? "—"),
                    ("Last update", storm.lastUpdate.map {
                        $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                ])

                let warnings = tracker.geometry(for: storm).warnings
                if !warnings.isEmpty {
                    section("Watches & Warnings") {
                        ForEach(Array(Set(warnings.map(\.kind))).sorted(), id: \.self) { kind in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Palette.warning(kind))
                                    .frame(width: 14, height: 8)
                                Text(WatchWarning(id: 0, bin: "", kind: kind, path: []).label)
                                    .font(.system(size: 11))
                            }
                        }
                    }
                }

                if !storm.products.isEmpty {
                    section("NHC Products") {
                        ForEach(storm.products) { product in
                            Link(destination: product.url) {
                                Label(product.name, systemImage: "arrow.up.forward.square")
                                    .font(.system(size: 11))
                            }
                        }
                    }
                }

                section("External") {
                    Link(destination: Feed.tropicalTidbits(storm: storm)) {
                        Label("Tropical Tidbits — \(storm.atcfID) model guidance",
                              systemImage: "chart.xyaxis.line")
                            .font(.system(size: 11))
                    }
                    Link(destination: Feed.deepMindWeatherLab) {
                        Label("DeepMind Weather Lab", systemImage: "sparkles")
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct ForecastList: View {
    @EnvironmentObject var tracker: Tracker
    let storm: Storm

    var body: some View {
        let points = tracker.geometry(for: storm).forecastPoints
        if points.isEmpty {
            VStack {
                Spacer()
                Text("No forecast points published yet.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(points) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Text(point.tau.map { "\($0)h" } ?? "—")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(point.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(point.validLabel ?? point.timeLabel ?? "—")
                                    .font(.system(size: 11, weight: .medium))
                                Text([point.windKt.map { "\($0) kt" },
                                      point.gustKt.map { "gusts \($0) kt" },
                                      point.pressureMb.map { "\($0) mb" },
                                      point.type].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(format(point.coord))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        Divider()
                    }
                }
            }
        }
    }
}

/// ATCF model guidance — the same a-deck Tropical Tidbits plots, including Google
/// DeepMind's GDMN ensemble mean.
struct ModelGuidance: View {
    @EnvironmentObject var tracker: Tracker
    let storm: Storm

    var body: some View {
        let models = tracker.availableModels(for: storm)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Toggle("Every technique", isOn: $tracker.showAllModels)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                Spacer()
                Button("All") {
                    tracker.enabledModels.formUnion(models.map(\.tech))
                }
                .font(.system(size: 10))
                Button("None") {
                    tracker.enabledModels.subtract(models.map(\.tech))
                }
                .font(.system(size: 10))
                Button {
                    Task { await tracker.loadModels(for: storm, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-download the a-deck")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider()

            if tracker.loadingModels && models.isEmpty {
                spacerText("Downloading model guidance…")
            } else if models.isEmpty {
                spacerText("No model guidance published for this system yet.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(models) { track in
                            row(track)
                            Divider()
                        }
                        Text("Source: NHC ATCF a-deck (`\(deckName)`). GDMN is the Google "
                             + "DeepMind ensemble mean, contributed to NHC's guidance suite.")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    }
                }
            }
        }
    }

    private var deckName: String {
        ATCF.url(for: storm)?.lastPathComponent ?? "a-deck"
    }

    private func spacerText(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ track: ModelTrack) -> some View {
        let on = tracker.enabledModels.contains(track.tech)
        return Button {
            if on { tracker.enabledModels.remove(track.tech) }
            else { tracker.enabledModels.insert(track.tech) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? track.tint : .secondary)
                    .font(.system(size: 12))
                RoundedRectangle(cornerRadius: 1)
                    .fill(track.tint)
                    .frame(width: 12, height: 3)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(track.tech)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        if track.isDeepMind {
                            Text("DeepMind")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(track.tint.opacity(0.25), in: Capsule())
                        }
                    }
                    Text(track.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(detail(track))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ track: ModelTrack) -> String {
        var parts = ["run \(track.cycleLabel)"]
        if let last = track.finalPoint {
            parts.append("to \(last.tau)h")
            if let w = last.windKt { parts.append("\(w) kt") }
        }
        return parts.joined(separator: " · ")
    }
}

struct ProductText: View {
    @EnvironmentObject var tracker: Tracker
    let url: URL?
    let missing: String

    var body: some View {
        Group {
            if let url {
                ScrollView {
                    Text(tracker.productText[url] ?? "Loading \(url.lastPathComponent)…")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .task(id: url) {
                    if tracker.productText[url] == nil { await tracker.loadProduct(url) }
                }
            } else {
                VStack {
                    Spacer()
                    Text(missing).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Imagery

private struct ImageSource: Identifiable, Hashable {
    let name: String
    let url: URL
    let credit: String
    var id: String { name }
}

struct ImageryPane: View {
    private static let sources = [
        ImageSource(name: "2-Day Outlook", url: Feed.outlook2Day, credit: "NHC/CPHC Graphical Tropical Weather Outlook"),
        ImageSource(name: "7-Day Outlook", url: Feed.outlook7Day, credit: "NHC/CPHC Graphical Tropical Weather Outlook"),
        ImageSource(name: "GOES-West GeoColor", url: Feed.goesWestFullDisk, credit: "NOAA NESDIS/STAR — GOES-18 full disk"),
        ImageSource(name: "GOES-West Hawai‘i", url: Feed.goesWestHawaii, credit: "NOAA NESDIS/STAR — GOES-18 Hawaii sector"),
        ImageSource(name: "GOES-West Air Mass", url: Feed.goesWestAirMass, credit: "NOAA NESDIS/STAR — GOES-18 air mass RGB")
    ]

    @State private var source = ImageryPane.sources[0]
    @State private var nonce = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $source) {
                    ForEach(ImageryPane.sources) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .frame(width: 240)
                Button {
                    nonce = Date()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text(source.credit).font(.caption2).foregroundStyle(.secondary)
                Link(destination: source.url) {
                    Image(systemName: "arrow.up.forward.square")
                }
            }
            .padding(8)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: bustedURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 400, height: 300)
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure(let error):
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.icloud").font(.largeTitle)
                            Text(error.localizedDescription).font(.caption)
                        }
                        .frame(width: 400, height: 300)
                        .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.opacity(0.85))
        }
    }

    /// ponytail: cache-bust with a query param instead of managing a URLCache.
    private var bustedURL: URL {
        URL(string: source.url.absoluteString + "?t=\(Int(nonce.timeIntervalSince1970))") ?? source.url
    }
}

// MARK: - Web panes

struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded: URL?
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        context.coordinator.loaded = url
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }
}

struct SourceBanner: View {
    let text: String
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(text).font(.caption)
            Spacer()
            Link("Open in browser", destination: url).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
    }
}

struct ModelsPane: View {
    @EnvironmentObject var tracker: Tracker
    let selection: Selection?

    var body: some View {
        VStack(spacing: 0) {
            SourceBanner(
                text: "Tropical Tidbits blocks direct image requests, so it is embedded live. "
                    + (selectedStorm.map { "Showing \($0.atcfID)." } ?? "Showing all active systems."),
                url: url)
            Divider()
            WebView(url: url)
        }
    }

    private var selectedStorm: Storm? {
        if case .storm(let id) = selection { return tracker.storm(id: id) }
        return nil
    }

    private var url: URL {
        selectedStorm.map { Feed.tropicalTidbits(storm: $0) } ?? Feed.tropicalTidbits
    }
}

struct WeatherLabPane: View {
    var body: some View {
        VStack(spacing: 0) {
            SourceBanner(
                text: "Google DeepMind Weather Lab has no public API and requires a Google sign-in. "
                    + "Sign in here yourself to see its experimental cyclone tracks.",
                url: Feed.deepMindWeatherLab)
            Divider()
            WebView(url: Feed.deepMindWeatherLab)
        }
    }
}

struct OutlookTextPane: View {
    @EnvironmentObject var tracker: Tracker
    @State private var basin: Basin = .ep

    private var url: URL { basin == .cp ? Feed.cpacOutlookText : Feed.epacOutlookText }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $basin) {
                    Text("Eastern Pacific").tag(Basin.ep)
                    Text("Central Pacific").tag(Basin.cp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Button {
                    Task { await tracker.loadProduct(url) }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Spacer()
                Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
            }
            .padding(8)
            Divider()
            ScrollView {
                Text(tracker.productText[url] ?? "Loading Tropical Weather Outlook…")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .task(id: url) {
                if tracker.productText[url] == nil { await tracker.loadProduct(url) }
            }
        }
    }
}
