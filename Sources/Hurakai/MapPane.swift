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

    var configuration: MKMapConfiguration {
        switch self {
        case .hybrid: return MKHybridMapConfiguration(elevationStyle: .flat)
        case .satellite: return MKImageryMapConfiguration(elevationStyle: .flat)
        case .standard: return MKStandardMapConfiguration(elevationStyle: .flat)
        }
    }
}

// MARK: - Map
//
// ponytail: this is an MKMapView, not SwiftUI's Map, for one reason — SwiftUI's Map has
// no tile-overlay API at any deployment target (verified against the SDK), and a
// georeferenced satellite layer has to be tiles. The SwiftUI pin views are reused as-is
// by hosting them inside the annotation views, so nothing is lost by dropping down.

/// Satellite imagery drawn beneath the storm overlays.
private func satelliteOverlay() -> MKTileOverlay {
    let overlay = MKTileOverlay(urlTemplate: Feed.satelliteTileTemplate)
    overlay.canReplaceMapContent = false     // sits on top of the base map, not instead of it
    overlay.minimumZ = 1
    overlay.maximumZ = 7                     // GIBS tops out here; MapKit upsamples past it
    return overlay
}

// Overlay subclasses carry their own styling so the renderer stays a lookup.

private final class StyledPolyline: MKPolyline {
    var color: NSColor = .white
    var width: CGFloat = 2
    var dash: [NSNumber]?
}

private final class StyledPolygon: MKPolygon {
    var stroke: NSColor = .white
    var fill: NSColor = .clear
    var width: CGFloat = 1.2
    var dash: [NSNumber]?
}

/// An annotation whose content is a SwiftUI view. `target` is what clicking it selects;
/// nil means the pin is decorative and shouldn't take clicks at all.
private final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let size: CGSize
    let target: Selection?
    let content: AnyView

    init(coordinate: CLLocationCoordinate2D, size: CGSize, target: Selection?, content: AnyView) {
        self.coordinate = coordinate
        self.size = size
        self.target = target
        self.content = content
    }
}

/// Lets clicks fall through to the MKAnnotationView so MapKit drives selection.
private final class PassthroughHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PinView: MKAnnotationView {
    private var host: PassthroughHost?

    func apply(_ pin: PinAnnotation) {
        if let host {
            host.rootView = pin.content
        } else {
            let new = PassthroughHost(rootView: pin.content)
            new.frame = CGRect(origin: .zero, size: pin.size)
            addSubview(new)
            host = new
        }
        // A fixed, generously sized container keeps the pin's icon centred on the
        // coordinate even though its label overflows below.
        frame = CGRect(origin: .zero, size: pin.size)
        host?.frame = bounds
        centerOffset = .zero
        isEnabled = pin.target != nil
        canShowCallout = false
    }
}

/// Holds the map view so SwiftUI chrome (the reset button) can drive it.
final class MapController: ObservableObject {
    weak var mapView: MKMapView?

    func showWholeBasin() {
        mapView?.setRegion(pacificRegion, animated: true)
    }
}

struct StormMap: View {
    @EnvironmentObject var tracker: Tracker
    @Binding var selection: Selection?
    @Binding var layers: LayerToggles
    @Binding var styleChoice: MapStyleChoice
    @StateObject private var controller = MapController()

    private var selectedStorm: Storm? {
        guard case .storm(let id) = selection else { return nil }
        return tracker.storm(id: id)
    }

    var body: some View {
        MapSurface(selection: $selection, layers: $layers,
                   styleChoice: $styleChoice, controller: controller)
            .overlay(alignment: .bottomLeading) { Legend() }
            .overlay(alignment: .topTrailing) { resetButton }
            .task(id: selectedStorm?.id) {
                if let storm = selectedStorm { await tracker.loadModels(for: storm) }
            }
    }

    private var resetButton: some View {
        Button {
            controller.showWholeBasin()
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
}

private struct MapSurface: NSViewRepresentable {
    @EnvironmentObject var tracker: Tracker
    @Binding var selection: Selection?
    @Binding var layers: LayerToggles
    @Binding var styleChoice: MapStyleChoice
    let controller: MapController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.showsZoomControls = true
        map.setRegion(pacificRegion, animated: false)
        controller.mapView = map
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        controller.mapView = map

        if context.coordinator.style != styleChoice {
            context.coordinator.style = styleChoice
            map.preferredConfiguration = styleChoice.configuration
        }

        context.coordinator.syncSatellite(on: map, enabled: layers.satellite)

        let revision = context.coordinator.revision(tracker: tracker, layers: layers,
                                                    selection: selection)
        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            context.coordinator.rebuild(on: map, tracker: tracker,
                                        layers: layers, selection: selection)
        }

        if context.coordinator.lastFocused != selection {
            context.coordinator.lastFocused = selection
            context.coordinator.focus(map: map, on: selection, tracker: tracker)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapSurface
        var style: MapStyleChoice?
        var lastRevision = ""
        var lastFocused: Selection??
        private var satellite: MKTileOverlay?

        init(_ parent: MapSurface) { self.parent = parent }

        // MARK: satellite layer

        func syncSatellite(on map: MKMapView, enabled: Bool) {
            if enabled, satellite == nil {
                let overlay = satelliteOverlay()
                satellite = overlay
                // Below the storm vectors (which go in at .aboveLabels) but above the base map.
                map.addOverlay(overlay, level: .aboveRoads)
            } else if !enabled, let overlay = satellite {
                map.removeOverlay(overlay)
                satellite = nil
            }
        }

        // MARK: change detection

        /// Rebuilding on every SwiftUI update would thrash the map, so overlays are only
        /// rebuilt when something they depend on actually changed.
        func revision(tracker: Tracker, layers: LayerToggles, selection: Selection?) -> String {
            var parts: [String] = []
            for storm in tracker.visibleStorms {
                parts.append("\(storm.id):\(storm.advisoryNumber ?? ""):\(storm.windKt)")
                let geo = tracker.geometry(for: storm)
                parts.append("g\(geo.cone.count),\(geo.forecastTrack.count),"
                             + "\(geo.pastTrack.count),\(geo.forecastPoints.count),\(geo.warnings.count)")
                parts.append("m" + tracker.shownModels(for: storm).map(\.tech).joined(separator: "-"))
            }
            for d in tracker.visibleDisturbances { parts.append("d\(d.id):\(d.prob7Day ?? -1)") }
            parts.append("L\(layers.cone)\(layers.forecastTrack)\(layers.pastTrack)"
                         + "\(layers.forecastPoints)\(layers.warnings)\(layers.disturbances)"
                         + "\(layers.modelTracks)\(layers.labels)")
            switch selection {
            case .storm(let id): parts.append("s\(id)")
            case .disturbance(let id): parts.append("x\(id)")
            case nil: parts.append("none")
            }
            return parts.joined(separator: "|")
        }

        // MARK: building

        func rebuild(on map: MKMapView, tracker: Tracker,
                     layers: LayerToggles, selection: Selection?) {
            map.removeAnnotations(map.annotations)
            for overlay in map.overlays where !(overlay is MKTileOverlay) {
                map.removeOverlay(overlay)
            }

            var overlays: [MKOverlay] = []
            var pins: [PinAnnotation] = []

            let selectedStorm: Storm? = {
                guard case .storm(let id) = selection else { return nil }
                return tracker.storm(id: id)
            }()

            for storm in tracker.visibleStorms {
                let geo = tracker.geometry(for: storm)
                let tint = NSColor(storm.tint)

                if layers.cone {
                    for ring in geo.cone where ring.count > 2 {
                        overlays.append(polygon(ring, stroke: tint.withAlphaComponent(0.75),
                                                fill: tint.withAlphaComponent(0.16), width: 1.2))
                    }
                }
                if layers.modelTracks, selectedStorm?.id == storm.id {
                    for track in tracker.shownModels(for: storm) where track.hasTrack {
                        overlays.append(line(track.path, color: NSColor(track.tint)
                            .withAlphaComponent(0.9), width: 1.6))
                    }
                }
                if layers.pastTrack {
                    for path in geo.pastTrack where path.count > 1 {
                        overlays.append(line(path, color: NSColor.white.withAlphaComponent(0.75),
                                             width: 2, dash: [2, 5]))
                    }
                }
                if layers.forecastTrack {
                    for path in geo.forecastTrack where path.count > 1 {
                        overlays.append(line(path, color: NSColor.black.withAlphaComponent(0.55),
                                             width: 5))
                        overlays.append(line(path, color: tint, width: 2.5))
                    }
                }
                if layers.warnings {
                    for warning in geo.warnings where warning.path.count > 1 {
                        overlays.append(line(warning.path,
                                             color: NSColor(Palette.warning(warning.kind)), width: 5))
                    }
                }

                // Forecast points clutter fast — show them for the selected storm, or for
                // everything when only a couple of systems are up.
                let showPoints = layers.forecastPoints
                    && (selectedStorm?.id == storm.id
                        || (selectedStorm == nil && tracker.visibleStorms.count <= 2))
                if showPoints {
                    for point in geo.forecastPoints where (point.tau ?? 0) > 0 {
                        pins.append(PinAnnotation(
                            coordinate: point.coord, size: CGSize(width: 64, height: 52),
                            target: .storm(storm.id),
                            content: AnyView(ForecastPin(point: point, showLabel: layers.labels))))
                    }
                }
                if layers.modelTracks, layers.labels, selectedStorm?.id == storm.id {
                    for track in tracker.shownModels(for: storm) where track.hasTrack {
                        guard let end = track.lastPositioned?.coord else { continue }
                        pins.append(PinAnnotation(
                            coordinate: end, size: CGSize(width: 96, height: 26), target: nil,
                            content: AnyView(ModelEndpointLabel(tech: track.tech, tint: track.tint))))
                    }
                }

                pins.append(PinAnnotation(
                    coordinate: storm.coord, size: CGSize(width: 190, height: 116),
                    target: .storm(storm.id),
                    content: AnyView(StormPin(storm: storm,
                                              selected: selection == .storm(storm.id),
                                              showLabel: layers.labels))))
            }

            if layers.disturbances {
                for d in tracker.visibleDisturbances {
                    let tint = NSColor(Palette.risk(d.risk7Day ?? d.risk2Day))
                    for ring in d.area where ring.count > 2 {
                        overlays.append(polygon(ring, stroke: tint.withAlphaComponent(0.8),
                                                fill: tint.withAlphaComponent(0.18),
                                                width: 1.5, dash: [7, 4]))
                    }
                    pins.append(PinAnnotation(
                        coordinate: d.coord, size: CGSize(width: 130, height: 74),
                        target: .disturbance(d.id),
                        content: AnyView(DisturbancePin(disturbance: d,
                                                        selected: selection == .disturbance(d.id)))))
                }
            }

            map.addOverlays(overlays, level: .aboveLabels)
            map.addAnnotations(pins)
        }

        private func line(_ coords: [Coord], color: NSColor, width: CGFloat,
                          dash: [NSNumber]? = nil) -> StyledPolyline {
            var points = coords
            let polyline = StyledPolyline(coordinates: &points, count: points.count)
            polyline.color = color
            polyline.width = width
            polyline.dash = dash
            return polyline
        }

        private func polygon(_ coords: [Coord], stroke: NSColor, fill: NSColor,
                             width: CGFloat, dash: [NSNumber]? = nil) -> StyledPolygon {
            var points = coords
            let poly = StyledPolygon(coordinates: &points, count: points.count)
            poly.stroke = stroke
            poly.fill = fill
            poly.width = width
            poly.dash = dash
            return poly
        }

        // MARK: camera

        func focus(map: MKMapView, on selection: Selection?, tracker: Tracker) {
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
            map.setRegion(region, animated: true)
        }

        // MARK: delegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.85
                return renderer
            }
            if let poly = overlay as? StyledPolygon {
                let renderer = MKPolygonRenderer(polygon: poly)
                renderer.strokeColor = poly.stroke
                renderer.fillColor = poly.fill
                renderer.lineWidth = poly.width
                renderer.lineDashPattern = poly.dash
                return renderer
            }
            if let poly = overlay as? StyledPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = poly.color
                renderer.lineWidth = poly.width
                renderer.lineCap = .round
                renderer.lineJoin = .round
                renderer.lineDashPattern = poly.dash
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? PinView
                ?? PinView(annotation: annotation, reuseIdentifier: "pin")
            view.annotation = annotation
            view.apply(pin)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? PinAnnotation, let target = pin.target else { return }
            // Deselect immediately so the same pin can be clicked again later.
            mapView.deselectAnnotation(view.annotation, animated: false)
            if parent.selection != target { parent.selection = target }
        }
    }
}

/// The small technique label at the end of a model track.
private struct ModelEndpointLabel: View {
    let tech: String
    let tint: Color

    var body: some View {
        Text(tech)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .fixedSize()
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(tint)
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
