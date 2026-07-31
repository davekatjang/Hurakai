import SwiftUI
import MapKit

// MARK: - Palette (Saffir-Simpson, the colors forecasters expect)

extension Color {
    /// Resolves against the window's effective appearance, so a colour follows the
    /// light/dark toggle without every view having to read the environment.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Palette {
    /// The storm palette is tuned for dark satellite imagery, which is what the map always
    /// draws on — pale yellow Cat 1 on a white sidebar is invisible. This derives a light
    /// counterpart by deepening the same hue, so the two modes stay recognisably the same
    /// colour scheme. Map overlays keep the bright originals; app chrome uses these.
    /// ponytail: one transform beats hand-tuning two dozen colours twice.
    static func onLight(_ base: Color) -> Color {
        let ns = NSColor(base).usingColorSpace(.deviceRGB) ?? .black
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Achromatic (the white official-forecast line) has no hue to deepen — go near-black.
        let light = s < 0.05
            ? Color(hue: Double(h), saturation: 0, brightness: 0.15)
            : Color(hue: Double(h), saturation: min(Double(s) * 1.5, 1), brightness: Double(b) * 0.55)
        return .adaptive(light: light, dark: base)
    }

    static let depression = Color(red: 0.37, green: 0.73, blue: 1.00)
    static let storm      = Color(red: 0.00, green: 0.88, blue: 0.92)
    static let cat1       = Color(red: 1.00, green: 1.00, blue: 0.70)
    static let cat2       = Color(red: 1.00, green: 0.91, blue: 0.46)
    static let cat3       = Color(red: 1.00, green: 0.76, blue: 0.25)
    static let cat4       = Color(red: 1.00, green: 0.56, blue: 0.13)
    static let cat5       = Color(red: 1.00, green: 0.38, blue: 0.38)
    static let postTropical = Color(red: 0.63, green: 0.65, blue: 0.70)

    static func forCategory(_ category: Int) -> Color {
        switch category {
        case 5: return cat5
        case 4: return cat4
        case 3: return cat3
        case 2: return cat2
        case 1: return cat1
        default: return storm
        }
    }

    /// Saffir-Simpson boundaries, for the intensity chart's reference lines.
    static let intensityThresholds: [(kt: Int, label: String, color: Color)] = [
        (34, "TS", storm), (64, "CAT 1", cat1), (83, "CAT 2", cat2),
        (96, "CAT 3", cat3), (113, "CAT 4", cat4), (137, "CAT 5", cat5)
    ]

    static func risk(_ level: String?) -> Color {
        switch level?.lowercased() {
        case "high": return Color(red: 1.0, green: 0.28, blue: 0.28)
        case "medium": return Color(red: 1.0, green: 0.62, blue: 0.13)
        default: return Color(red: 1.0, green: 0.87, blue: 0.30)
        }
    }

    /// Appearance-aware variants, for everything that sits on the app background
    /// rather than on the map.
    static func uiModel(_ tech: String) -> Color { onLight(model(tech)) }
    static func uiRisk(_ level: String?) -> Color { onLight(risk(level)) }

    static let uiIntensityThresholds: [(kt: Int, label: String, color: Color)] =
        intensityThresholds.map { ($0.kt, $0.label, onLight($0.color)) }

    /// Model guidance colors. The named ones match how forecasters expect to see them;
    /// anything else gets a stable hue derived from its technique id.
    static func model(_ tech: String) -> Color {
        switch tech {
        case "OFCL", "OFCI": return .white
        case "GDMN", "GDMI", "GDM2": return Color(red: 0.80, green: 0.42, blue: 1.00)
        case "AVNO", "AVNI": return Color(red: 1.00, green: 0.34, blue: 0.34)
        case "AEMN", "AC00": return Color(red: 1.00, green: 0.62, blue: 0.40)
        case "CMC", "CMCI", "CMC2": return Color(red: 0.38, green: 1.00, blue: 0.52)
        case "UKX", "UKXI", "UKX2": return Color(red: 0.40, green: 0.70, blue: 1.00)
        case "NVGM", "NVGI", "NVG2": return Color(red: 0.62, green: 0.82, blue: 0.92)
        case "HFSA", "HFAI": return Color(red: 1.00, green: 0.86, blue: 0.30)
        case "HFSB", "HFBI": return Color(red: 0.94, green: 0.68, blue: 0.18)
        case "HMON", "HMNI", "HWRF", "HWFI": return Color(red: 0.92, green: 0.50, blue: 0.72)
        case "HCCA", "TVCN", "IVCN", "RVCN": return Color(red: 0.45, green: 1.00, blue: 0.90)
        default:
            let hue = Double(abs(tech.hashValue) % 360) / 360
            return Color(hue: hue, saturation: 0.55, brightness: 0.95)
        }
    }

    static func warning(_ kind: String) -> Color {
        switch kind {
        case "HWR": return Color(red: 0.85, green: 0.10, blue: 0.10)
        case "HWA": return Color(red: 1.00, green: 0.45, blue: 0.60)
        case "TWR": return Color(red: 0.10, green: 0.55, blue: 0.20)
        case "TWA": return Color(red: 0.98, green: 0.85, blue: 0.20)
        default: return .white
        }
    }
}

extension Storm {
    var tint: Color {
        if ["PTC", "PT", "LO", "DB"].contains(classification) { return Palette.postTropical }
        if isHurricaneType { return Palette.forCategory(max(category, 1)) }
        if classification.hasPrefix("TD") || classification == "STD" { return Palette.depression }
        return Palette.storm
    }
}

extension Storm {
    /// For sidebar rows, tabs and the inspector — anything on the app background.
    var uiTint: Color { Palette.onLight(tint) }
}

extension ModelTrack {
    var tint: Color { Palette.model(tech) }
    var uiTint: Color { Palette.uiModel(tech) }
}

extension ForecastPoint {
    var uiTint: Color { Palette.onLight(tint) }
}

extension ForecastPoint {
    var tint: Color {
        switch devLabel {
        case "M", "H": return Palette.forCategory(max(category, 1))
        case "S": return Palette.storm
        case "D": return Palette.depression
        default: return Palette.postTropical
        }
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case hybrid = "Hybrid"
    case satellite = "Satellite"
    case standard = "Standard"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .hybrid: return .hybrid(elevation: .flat)
        case .satellite: return .imagery(elevation: .flat)
        case .standard: return .standard(elevation: .flat)
        }
    }
}

// MARK: - Map

private struct MapPath: Identifiable {
    let id: String
    let coords: [Coord]
    let tint: Color
}

private struct ModelEndpoint: Identifiable {
    let tech: String
    let coord: Coord
    let tint: Color
    var id: String { tech }
}

struct StormMap: View {
    @EnvironmentObject var tracker: Tracker
    @Binding var selection: Selection?
    @Binding var layers: LayerToggles
    @Binding var styleChoice: MapStyleChoice

    @State private var camera: MapCameraPosition = .region(pacificRegion)

    var body: some View {
        Map(position: $camera) {
            overlays
            stormPins
            disturbancePins
        }
        .mapStyle(styleChoice.style)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapZoomStepper()
        }
        .overlay(alignment: .bottomLeading) { Legend() }
        .overlay(alignment: .topTrailing) { resetButton }
        .onChange(of: selection) { _, new in focus(on: new) }
        .task(id: selectedStorm?.id) {
            if let storm = selectedStorm { await tracker.loadModels(for: storm) }
        }
    }

    // MARK: overlays

    @MapContentBuilder
    private var overlays: some MapContent {
        if layers.cone {
            ForEach(cones) { ring in
                MapPolygon(coordinates: ring.coords)
                    .foregroundStyle(ring.tint.opacity(0.16))
                    .stroke(ring.tint.opacity(0.75), lineWidth: 1.2)
            }
        }
        ForEach(modelPaths) { path in
            MapPolyline(coordinates: path.coords)
                .stroke(path.tint.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        if layers.labels {
            ForEach(modelEndpoints) { endpoint in
                Annotation("", coordinate: endpoint.coord, anchor: .center) {
                    Text(endpoint.tech)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .fixedSize()
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(endpoint.tint)
                }
            }
            .annotationTitles(.hidden)
        }
        if layers.pastTrack {
            ForEach(pastTracks) { path in
                MapPolyline(coordinates: path.coords)
                    .stroke(path.tint.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
            }
        }
        if layers.forecastTrack {
            ForEach(forecastTracks) { path in
                MapPolyline(coordinates: path.coords)
                    .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                MapPolyline(coordinates: path.coords)
                    .stroke(path.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        if layers.warnings {
            ForEach(warnings) { path in
                MapPolyline(coordinates: path.coords)
                    .stroke(path.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        if layers.disturbances {
            ForEach(disturbanceAreas) { ring in
                MapPolygon(coordinates: ring.coords)
                    .foregroundStyle(ring.tint.opacity(0.18))
                    .stroke(ring.tint.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 4]))
            }
        }
        if layers.forecastPoints {
            ForEach(forecastPoints) { point in
                Annotation("", coordinate: point.coord, anchor: .center) {
                    ForecastPin(point: point, showLabel: layers.labels)
                        .onTapGesture {
                            if let id = tracker.stormID(forBin: point.bin) { selection = .storm(id) }
                        }
                }
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private var stormPins: some MapContent {
        ForEach(tracker.visibleStorms) { storm in
            Annotation(storm.name, coordinate: storm.coord, anchor: .center) {
                StormPin(storm: storm,
                         selected: selection == .storm(storm.id),
                         showLabel: layers.labels)
                    .onTapGesture { selection = .storm(storm.id) }
            }
        }
        .annotationTitles(.hidden)
    }

    @MapContentBuilder
    private var disturbancePins: some MapContent {
        if layers.disturbances {
            ForEach(tracker.visibleDisturbances) { disturbance in
                Annotation("", coordinate: disturbance.coord, anchor: .center) {
                    DisturbancePin(disturbance: disturbance,
                                   selected: selection == .disturbance(disturbance.id))
                        .onTapGesture { selection = .disturbance(disturbance.id) }
                }
            }
            .annotationTitles(.hidden)
        }
    }

    // MARK: derived geometry

    private var activeStorms: [Storm] { tracker.visibleStorms }

    private var cones: [MapPath] {
        activeStorms.flatMap { storm in
            tracker.geometry(for: storm).cone.enumerated().map {
                MapPath(id: "\(storm.id)-cone-\($0.offset)", coords: $0.element, tint: storm.tint)
            }
        }
    }

    private var forecastTracks: [MapPath] {
        activeStorms.flatMap { storm in
            tracker.geometry(for: storm).forecastTrack.enumerated().map {
                MapPath(id: "\(storm.id)-fcst-\($0.offset)", coords: $0.element, tint: storm.tint)
            }
        }
    }

    private var pastTracks: [MapPath] {
        activeStorms.flatMap { storm in
            tracker.geometry(for: storm).pastTrack.enumerated().map {
                MapPath(id: "\(storm.id)-past-\($0.offset)", coords: $0.element, tint: .white)
            }
        }
    }

    private var warnings: [MapPath] {
        activeStorms.flatMap { storm in
            tracker.geometry(for: storm).warnings.enumerated().map {
                MapPath(id: "\(storm.id)-ww-\($0.offset)",
                        coords: $0.element.path,
                        tint: Palette.warning($0.element.kind))
            }
        }
    }

    /// Forecast points are noise for every storm at once — show them for the selected storm,
    /// or for all storms when nothing is selected and there are only a couple of systems.
    private var forecastPoints: [ForecastPoint] {
        let show: [Storm]
        if case .storm(let id) = selection, let s = tracker.storm(id: id) {
            show = [s]
        } else {
            show = activeStorms.count <= 2 ? activeStorms : []
        }
        return show.flatMap { tracker.geometry(for: $0).forecastPoints.filter { ($0.tau ?? 0) > 0 } }
    }

    /// Spaghetti is only legible one storm at a time, so model guidance follows the selection.
    private var selectedStorm: Storm? {
        guard case .storm(let id) = selection else { return nil }
        return tracker.storm(id: id)
    }

    private var shownModels: [ModelTrack] {
        guard layers.modelTracks, let storm = selectedStorm else { return [] }
        return tracker.shownModels(for: storm)
    }

    private var modelPaths: [MapPath] {
        shownModels.compactMap { track in
            guard track.hasTrack else { return nil }
            return MapPath(id: "model-\(track.tech)", coords: track.path, tint: track.tint)
        }
    }

    private var modelEndpoints: [ModelEndpoint] {
        shownModels.compactMap { track in
            guard track.hasTrack, let last = track.lastPositioned?.coord else { return nil }
            return ModelEndpoint(tech: track.tech, coord: last, tint: track.tint)
        }
    }

    private var disturbanceAreas: [MapPath] {
        tracker.visibleDisturbances.flatMap { d in
            d.area.enumerated().map {
                MapPath(id: "\(d.id)-area-\($0.offset)",
                        coords: $0.element,
                        tint: Palette.risk(d.risk7Day ?? d.risk2Day))
            }
        }
    }

    // MARK: camera

    private var resetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) { camera = .region(pacificRegion) }
        } label: {
            Label("Whole Basin", systemImage: "arrow.down.left.and.arrow.up.right")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .foregroundStyle(.white)
        .padding(10)
    }

    private func focus(on selection: Selection?) {
        guard let selection else { return }
        var coords: [Coord] = []
        switch selection {
        case .storm(let id):
            guard let storm = tracker.storm(id: id) else { return }
            let geo = tracker.geometry(for: storm)
            coords = [storm.coord] + geo.cone.flatMap { $0 } + geo.forecastTrack.flatMap { $0 }
        case .disturbance(let id):
            guard let d = tracker.disturbance(id: id) else { return }
            coords = [d.coord] + d.area.flatMap { $0 }
        }
        guard let region = regionCovering(coords) else { return }
        withAnimation(.easeInOut(duration: 0.7)) { camera = .region(region) }
    }
}

extension Tracker {
    /// Maps a GIS bin number (e.g. "EP2") back to the storm id it belongs to.
    func stormID(forBin bin: String) -> String? {
        storms.first { $0.bin.uppercased() == bin.uppercased() }?.id
    }
}

// MARK: - Pins

struct StormPin: View {
    let storm: Storm
    let selected: Bool
    let showLabel: Bool
    @State private var spin = false

    private var size: CGFloat { selected ? 46 : 34 }

    var body: some View {
        ZStack {
            Circle().fill(storm.tint.opacity(0.25))
            Circle().strokeBorder(storm.tint, lineWidth: selected ? 2.5 : 1.5)
            Image(systemName: storm.isHurricaneType ? "hurricane" : "tropicalstorm")
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(storm.tint)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .animation(.linear(duration: storm.isHurricaneType ? 7 : 14)
                    .repeatForever(autoreverses: false), value: spin)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.7), radius: 3)
        // ponytail: the label hangs off an overlay, not a VStack sibling. An annotation is
        // centered on its own frame, so a stacked label would shove the icon off the
        // storm's real position — which is exactly where the track line starts.
        .overlay(alignment: .top) {
            if showLabel { label.fixedSize().offset(y: size + 3) }
        }
        .onAppear { spin = true }
    }

    private var label: some View {
        VStack(spacing: 0) {
            Text(storm.name.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
            Text("\(storm.windKt) kt" + (storm.category > 0 ? " · C\(storm.category)" : ""))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(storm.tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(.white)
    }
}

struct ForecastPin: View {
    let point: ForecastPoint
    let showLabel: Bool

    var body: some View {
        ZStack {
            Circle().fill(point.tint)
            Circle().strokeBorder(.black.opacity(0.65), lineWidth: 1)
            Text(point.devLabel ?? "")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.black.opacity(0.8))
        }
        .frame(width: 16, height: 16)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .overlay(alignment: .top) {
            if showLabel, let tau = point.tau {
                Text("\(tau)h")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .offset(y: 18)
            }
        }
        .help(pointHelp)
    }

    private var pointHelp: String {
        var parts: [String] = []
        if let t = point.validLabel ?? point.timeLabel { parts.append(t) }
        if let w = point.windKt { parts.append("\(w) kt") }
        if let g = point.gustKt { parts.append("gusts \(g) kt") }
        if let p = point.pressureMb { parts.append("\(p) mb") }
        return parts.joined(separator: " · ")
    }
}

struct DisturbancePin: View {
    let disturbance: Disturbance
    let selected: Bool

    private var tint: Color { Palette.risk(disturbance.risk7Day ?? disturbance.risk2Day) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.9))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? .white : .black.opacity(0.6), lineWidth: selected ? 2 : 1)
            Text("X")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.black.opacity(0.85))
        }
        .frame(width: 22, height: 22)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .overlay(alignment: .top) {
            Text(probabilityLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .offset(y: 25)
        }
    }

    private var probabilityLabel: String {
        let two = disturbance.prob2Day.map { "\($0)%" } ?? "—"
        let seven = disturbance.prob7Day.map { "\($0)%" } ?? "—"
        return "2d \(two) · 7d \(seven)"
    }
}

// MARK: - Legend

struct Legend: View {
    private let rows: [(String, Color)] = [
        ("Cat 5", Palette.cat5), ("Cat 4", Palette.cat4), ("Cat 3", Palette.cat3),
        ("Cat 2", Palette.cat2), ("Cat 1", Palette.cat1),
        ("Trop. Storm", Palette.storm), ("Depression", Palette.depression),
        ("Post-Tropical", Palette.postTropical)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SAFFIR-SIMPSON")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(row.1).frame(width: 16, height: 8)
                    Text(row.0)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            Divider().overlay(.white.opacity(0.3))
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.risk("high")).frame(width: 16, height: 8)
                Text("Disturbance area")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }
}
