import Foundation
import CoreLocation
import MapKit
import Compression

typealias Coord = CLLocationCoordinate2D

/// The app's home view: Eastern plus Central Pacific — the Mexican coast west to the
/// dateline, with Hawai'i (21°N 157°W) comfortably inside.
let pacificRegion = MKCoordinateRegion(
    center: Coord(latitude: 18, longitude: -136),
    span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 92))

/// Smallest region containing `coords`, padded a little.
func regionCovering(_ coords: [Coord], padding: Double = 1.45) -> MKCoordinateRegion? {
    guard !coords.isEmpty else { return nil }
    let lats = coords.map(\.latitude)
    var lons = coords.map(\.longitude)
    // ponytail: shift to 0..360 when the set straddles the antimeridian; Central Pacific
    // storms cross 180 and naive min/max would zoom out to the whole planet.
    if let lo = lons.min(), let hi = lons.max(), hi - lo > 180 {
        lons = lons.map { $0 < 0 ? $0 + 360 : $0 }
    }
    guard let minLat = lats.min(), let maxLat = lats.max(),
          let minLon = lons.min(), let maxLon = lons.max() else { return nil }
    var centerLon = (minLon + maxLon) / 2
    if centerLon > 180 { centerLon -= 360 }
    return MKCoordinateRegion(
        center: Coord(latitude: (minLat + maxLat) / 2, longitude: centerLon),
        span: MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * padding, 6), 120),
            longitudeDelta: min(max((maxLon - minLon) * padding, 6), 200)))
}

// MARK: - Minimal GeoJSON
// ponytail: one recursive coordinate type instead of per-geometry structs. Handles
// Point / LineString / Polygon / MultiLineString / MultiPolygon uniformly.

indirect enum GJCoords: Decodable {
    case n(Double)
    case a([GJCoords])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Double.self) { self = .n(v) } else { self = .a(try c.decode([GJCoords].self)) }
    }

    var coord: Coord? {
        guard case .a(let i) = self, i.count >= 2,
              case .n(let lon) = i[0], case .n(let lat) = i[1],
              lat.isFinite, lon.isFinite, abs(lat) <= 90 else { return nil }
        return Coord(latitude: lat, longitude: lon)
    }

    /// Point -> [[p]]; LineString -> [pts]; Polygon/Multi* -> one entry per ring or line.
    var paths: [[Coord]] {
        if let p = coord { return [[p]] }
        guard case .a(let items) = self else { return [] }
        let pts = items.compactMap(\.coord)
        if !pts.isEmpty, pts.count == items.count { return [pts] }
        return items.flatMap(\.paths)
    }
}

enum GJValue: Decodable {
    case s(String), n(Double), b(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Double.self) { self = .n(v) }
        else if let v = try? c.decode(Bool.self) { self = .b(v) }
        else if let v = try? c.decode(String.self) { self = .s(v) }
        else { self = .null }
    }

    var string: String? {
        switch self {
        case .s(let v): return v.isEmpty ? nil : v
        case .n(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
        case .b(let v): return String(v)
        case .null: return nil
        }
    }

    var double: Double? {
        switch self {
        case .n(let v): return v
        case .s(let v): return Double(v)
        default: return nil
        }
    }

    var int: Int? {
        guard let d = double, d.isFinite, abs(d) < 1e15 else { return nil }
        return Int(d)
    }
}

struct GJGeometry: Decodable {
    let type: String?
    let coordinates: GJCoords?
}

struct GJFeature: Decodable {
    let properties: [String: GJValue]?
    let geometry: GJGeometry?

    func str(_ key: String) -> String? { properties?[key]?.string }
    func int(_ key: String) -> Int? { properties?[key]?.int }
    var paths: [[Coord]] { geometry?.coordinates?.paths ?? [] }
    var point: Coord? { paths.first?.first }
}

struct GJCollection: Decodable {
    let features: [GJFeature]?
}

/// Lenient numeric decode — the live NHC feed is not consistent about quoting numbers.
struct LooseInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d.isFinite ? Int(d) : nil }
        else if let s = try? c.decode(String.self) {
            let t = s.trimmingCharacters(in: .whitespaces)
            value = Int(t) ?? Double(t).map { Int($0) }
        } else { value = nil }
    }
}

// MARK: - Domain

enum Basin: String, CaseIterable {
    case ep = "EP", cp = "CP", al = "AL"

    var label: String {
        switch self {
        case .ep: return "Eastern Pacific"
        case .cp: return "Central Pacific"
        case .al: return "Atlantic"
        }
    }

    /// Tropical Tidbits / ATCF basin suffix.
    var atcfSuffix: String {
        switch self {
        case .ep: return "E"
        case .cp: return "C"
        case .al: return "L"
        }
    }

    var isPacific: Bool { self != .al }

    /// The GIS outlook layers spell the basin out inconsistently and publish no coded
    /// domain, so normalise what we've seen and what NHC's shapefiles use.
    /// ponytail: string match only. An unrecognised value returns nil and — with the
    /// Atlantic toggle off — is dropped rather than shown, so the failure mode is a
    /// missing Pacific area, never an Atlantic one leaking into a Pacific-only app.
    /// If a new spelling ever appears, add it here.
    static func parse(_ raw: String?) -> Basin? {
        guard let raw else { return nil }
        switch raw.uppercased().filter(\.isLetter) {
        case "EP", "E", "EPAC", "EASTPACIFIC", "EASTERNPACIFIC": return .ep
        case "CP", "C", "CPAC", "CENTRALPACIFIC": return .cp
        case "AL", "L", "AT", "ATL", "ATLANTIC": return .al
        default: return nil
        }
    }
}

struct Storm: Identifiable {
    let id: String            // "ep072026"
    let bin: String           // "EP2" — the GIS layer key
    let name: String
    let classification: String   // HU, TS, TD, PTC, STS, STD, LO, DB
    let basin: Basin
    let stormNumber: Int
    let year: Int
    let windKt: Int
    let gustKt: Int?
    let pressureMb: Int?
    let coord: Coord
    let movementDir: Int?
    let movementKt: Int?
    let lastUpdate: Date?
    let advisoryNumber: String?
    let products: [Product]

    struct Product: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { name }
    }

    /// Saffir-Simpson category; 0 means below hurricane force.
    var category: Int {
        guard isHurricaneType else { return 0 }
        switch windKt {
        case 137...: return 5
        case 113...136: return 4
        case 96...112: return 3
        case 83...95: return 2
        case 64...82: return 1
        default: return 0
        }
    }

    var isHurricaneType: Bool { ["HU", "MH", "TY", "STY"].contains(classification) }

    var typeLabel: String {
        switch classification {
        case "HU", "MH": return basin == .al ? "Hurricane" : "Hurricane"
        case "TY": return "Typhoon"
        case "STY": return "Super Typhoon"
        case "TS": return "Tropical Storm"
        case "STS": return "Subtropical Storm"
        case "TD": return "Tropical Depression"
        case "STD": return "Subtropical Depression"
        case "PTC": return "Post-Tropical Cyclone"
        case "PT": return "Post-Tropical Cyclone"
        case "LO": return "Remnant Low"
        case "DB": return "Disturbance"
        default: return classification
        }
    }

    var headline: String {
        category > 0 ? "Category \(category) \(typeLabel)" : typeLabel
    }

    /// NHC publishes sustained winds rounded to the nearest 5 mph.
    var windMph: Int { Int((Double(windKt) * 1.15078 / 5).rounded()) * 5 }

    /// ATCF-style short id used by Tropical Tidbits, e.g. "07E".
    var atcfID: String { String(format: "%02d", stormNumber) + basin.atcfSuffix }

    var movementText: String {
        guard let dir = movementDir, let kt = movementKt else { return "Stationary" }
        return "\(Storm.compass(dir)) (\(dir)°) at \(kt) kt"
    }

    static func compass(_ deg: Int) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((Double(deg).truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return names[(i + 16) % 16]
    }
}

struct ForecastPoint: Identifiable {
    let id: Int
    let bin: String
    let coord: Coord
    let tau: Int?              // forecast hour
    let windKt: Int?
    let gustKt: Int?
    let pressureMb: Int?
    let timeLabel: String?     // "11:00 AM Wed"
    let validLabel: String?    // "2026-07-29 8:00 AM Wed HST"
    let devLabel: String?      // H / S / D / M
    let type: String?
    let ssnum: Int?

    var category: Int {
        guard let w = windKt, devLabel == "H" || devLabel == "M" || type == "HU" || type == "MH" else { return 0 }
        switch w {
        case 137...: return 5
        case 113...136: return 4
        case 96...112: return 3
        case 83...95: return 2
        case 64...82: return 1
        default: return 0
        }
    }
}

struct WatchWarning: Identifiable {
    let id: Int
    let bin: String
    let kind: String           // tcww: TWA / TWR / HWA / HWR
    let path: [Coord]

    var label: String {
        switch kind {
        case "TWA": return "Tropical Storm Watch"
        case "TWR": return "Tropical Storm Warning"
        case "HWA": return "Hurricane Watch"
        case "HWR": return "Hurricane Warning"
        default: return kind
        }
    }
}

struct StormGeometry {
    var forecastPoints: [ForecastPoint] = []
    var forecastTrack: [[Coord]] = []
    var cone: [[Coord]] = []
    var pastTrack: [[Coord]] = []
    var warnings: [WatchWarning] = []
}

/// A Tropical Weather Outlook area — the "disturbance" / invest layer.
struct Disturbance: Identifiable {
    let id: Int
    let basin: Basin?
    let coord: Coord
    let prob2Day: Int?
    let prob7Day: Int?
    let risk2Day: String?
    let risk7Day: String?
    var area: [[Coord]] = []
    let isSevenDayOnly: Bool

    var riskLevel: String { (risk7Day ?? risk2Day ?? "Low").capitalized }
    var title: String { "Disturbance \(id)" }
}

// MARK: - Feeds

enum Feed {
    static let currentStorms = URL(string: "https://www.nhc.noaa.gov/CurrentStorms.json")!

    private static let gis =
        "https://mapservices.weather.noaa.gov/tropical/rest/services/tropical/NHC_tropical_weather_summary/MapServer"

    enum Layer: Int {
        case twoDayPoint = 1, sevenDayPoint = 2, developmentRegion = 3
        case forecastPoints = 5, forecastTrack = 6, cone = 7, watchWarning = 8
        case pastTrack = 11
    }

    static func url(_ layer: Layer) -> URL {
        URL(string: "\(gis)/\(layer.rawValue)/query?where=1%3D1&outFields=*&f=geojson&returnGeometry=true")!
    }

    // Text products (HTML pages wrapping a <pre> block).
    static let epacOutlookText = URL(string: "https://www.nhc.noaa.gov/text/MIATWOEP.shtml")!
    static let cpacOutlookText = URL(string: "https://www.nhc.noaa.gov/text/HFOTWOCP.shtml")!

    // Graphics.
    static let outlook2Day = URL(string: "https://www.nhc.noaa.gov/xgtwo/two_pac_2d0.png")!
    static let outlook7Day = URL(string: "https://www.nhc.noaa.gov/xgtwo/two_pac_7d0.png")!
    static let goesWestFullDisk =
        URL(string: "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/FD/GEOCOLOR/1808x1808.jpg")!
    static let goesWestHawaii =
        URL(string: "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/SECTOR/hi/GEOCOLOR/1200x1200.jpg")!
    static let goesWestAirMass =
        URL(string: "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/FD/AirMass/1808x1808.jpg")!

    // Third-party sites. Tropical Tidbits is an outbound link only — its model guidance
    // comes from the a-deck now. Weather Lab needs a Google sign-in, so it stays a web view.
    static let tropicalTidbits = URL(string: "https://www.tropicaltidbits.com/storminfo/")!
    static func tropicalTidbits(storm: Storm) -> URL {
        URL(string: "https://www.tropicaltidbits.com/storminfo/#\(storm.atcfID)") ?? tropicalTidbits
    }
    static let deepMindWeatherLab = URL(string: "https://deepmind.google.com/science/weatherlab")!
    static let cphc = URL(string: "https://www.nhc.noaa.gov/?cpac")!
}

// MARK: - Networking

enum FetchError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let host): return "\(host) returned HTTP \(code)"
        }
    }
}

struct Net {
    static func data(_ url: URL) async throws -> Foundation.Data {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Hurakai/1.0 (macOS; Pacific cyclone tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode, url.host ?? "server")
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try JSONDecoder().decode(type, from: await data(url))
    }

    static func text(_ url: URL) async throws -> String {
        let raw = try await data(url)
        return String(data: raw, encoding: .utf8) ?? String(decoding: raw, as: UTF8.self)
    }
}

// MARK: - NHC CurrentStorms.json

private struct CurrentStormsResponse: Decodable {
    struct Product: Decodable {
        let advNum: String?
        let url: String?
    }

    struct Item: Decodable {
        let id: String
        let binNumber: String?
        let name: String?
        let classification: String?
        let intensity: LooseInt?
        let pressure: LooseInt?
        let latitudeNumeric: Double?
        let longitudeNumeric: Double?
        let movementDir: LooseInt?
        let movementSpeed: LooseInt?
        let lastUpdate: String?
        let publicAdvisory: Product?
        let forecastAdvisory: Product?
        let forecastDiscussion: Product?
        let windSpeedProbabilities: Product?
        let forecastGraphics: Product?
    }

    let activeStorms: [Item]?
}

private let isoParsers: [ISO8601DateFormatter] = {
    let a = ISO8601DateFormatter()
    a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let b = ISO8601DateFormatter()
    b.formatOptions = [.withInternetDateTime]
    return [a, b]
}()

func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    for p in isoParsers { if let d = p.date(from: s) { return d } }
    return nil
}

enum NHC {
    static func activeStorms() async throws -> [Storm] {
        let response = try await Net.decode(CurrentStormsResponse.self, from: Feed.currentStorms)
        return (response.activeStorms ?? []).compactMap { item -> Storm? in
            guard let lat = item.latitudeNumeric, let lon = item.longitudeNumeric,
                  let basin = Basin(rawValue: String(item.id.prefix(2)).uppercased()) else { return nil }

            var products: [Storm.Product] = []
            func add(_ name: String, _ p: CurrentStormsResponse.Product?) {
                if let s = p?.url, let u = URL(string: s) { products.append(.init(name: name, url: u)) }
            }
            add("Public Advisory", item.publicAdvisory)
            add("Forecast Advisory", item.forecastAdvisory)
            add("Forecast Discussion", item.forecastDiscussion)
            add("Wind Speed Probabilities", item.windSpeedProbabilities)
            add("Forecast Graphic", item.forecastGraphics)

            let digits = item.id.dropFirst(2)
            return Storm(
                id: item.id,
                bin: item.binNumber ?? item.id.uppercased(),
                name: item.name ?? "Unnamed",
                classification: (item.classification ?? "DB").uppercased(),
                basin: basin,
                stormNumber: Int(digits.prefix(2)) ?? 0,
                year: Int(digits.dropFirst(2).prefix(4)) ?? Calendar.current.component(.year, from: Date()),
                windKt: item.intensity?.value ?? 0,
                gustKt: nil,
                pressureMb: item.pressure?.value,
                coord: Coord(latitude: lat, longitude: lon),
                movementDir: item.movementDir?.value,
                movementKt: item.movementSpeed?.value,
                lastUpdate: parseISO(item.lastUpdate),
                advisoryNumber: item.publicAdvisory?.advNum ?? item.forecastAdvisory?.advNum,
                products: products
            )
        }
    }

    static func geometry() async throws -> [String: StormGeometry] {
        async let pointsF = Net.decode(GJCollection.self, from: Feed.url(.forecastPoints))
        async let trackF = Net.decode(GJCollection.self, from: Feed.url(.forecastTrack))
        async let coneF = Net.decode(GJCollection.self, from: Feed.url(.cone))
        async let pastF = Net.decode(GJCollection.self, from: Feed.url(.pastTrack))
        async let warnF = Net.decode(GJCollection.self, from: Feed.url(.watchWarning))

        let (points, track, cone, past, warn) = try await (pointsF, trackF, coneF, pastF, warnF)
        var out: [String: StormGeometry] = [:]

        func key(_ f: GJFeature) -> String? {
            f.str("binnumber")?.uppercased() ?? f.str("stormnum").map { "#\($0)" }
        }

        for f in points.features ?? [] {
            guard let bin = key(f), let c = f.point else { continue }
            out[bin, default: .init()].forecastPoints.append(
                ForecastPoint(id: f.int("objectid") ?? Int.random(in: 0..<1_000_000),
                              bin: bin, coord: c,
                              tau: f.int("tau"),
                              windKt: f.int("maxwind"), gustKt: f.int("gust"),
                              pressureMb: f.int("mslp"),
                              timeLabel: f.str("datelbl"), validLabel: f.str("fldatelbl"),
                              devLabel: f.str("dvlbl"), type: f.str("stormtype"),
                              ssnum: f.int("ssnum")))
        }
        for f in track.features ?? [] {
            guard let bin = key(f) else { continue }
            out[bin, default: .init()].forecastTrack.append(contentsOf: f.paths.filter { $0.count > 1 })
        }
        for f in cone.features ?? [] {
            guard let bin = key(f) else { continue }
            out[bin, default: .init()].cone.append(contentsOf: f.paths.filter { $0.count > 2 })
        }
        for f in past.features ?? [] {
            guard let bin = key(f) else { continue }
            out[bin, default: .init()].pastTrack.append(contentsOf: f.paths.filter { $0.count > 1 })
        }
        for f in warn.features ?? [] {
            guard let bin = key(f), let kind = f.str("tcww") else { continue }
            for path in f.paths where path.count > 1 {
                out[bin, default: .init()].warnings.append(
                    WatchWarning(id: f.int("objectid") ?? 0, bin: bin, kind: kind, path: path))
            }
        }

        for bin in out.keys {
            out[bin]?.forecastPoints.sort { ($0.tau ?? 0) < ($1.tau ?? 0) }
        }
        return out
    }

    static func disturbances() async throws -> [Disturbance] {
        async let twoF = Net.decode(GJCollection.self, from: Feed.url(.twoDayPoint))
        async let sevenF = Net.decode(GJCollection.self, from: Feed.url(.sevenDayPoint))
        async let regionF = Net.decode(GJCollection.self, from: Feed.url(.developmentRegion))
        let (two, seven, region) = try await (twoF, sevenF, regionF)

        let regions = (region.features ?? []).compactMap { f -> (String?, [[Coord]])? in
            let rings = f.paths.filter { $0.count > 2 }
            return rings.isEmpty ? nil : (f.str("basin"), rings)
        }

        func build(_ features: [GJFeature], sevenOnly: Bool) -> [Disturbance] {
            features.compactMap { f in
                guard let c = f.point else { return nil }
                let basinCode = f.str("basin")
                var d = Disturbance(
                    id: f.int("objectid") ?? 0,
                    basin: Basin.parse(basinCode),
                    coord: c,
                    prob2Day: f.int("prob2day"),
                    prob7Day: f.int("prob7day"),
                    risk2Day: f.str("risk2day"),
                    risk7Day: f.str("risk7day"),
                    isSevenDayOnly: sevenOnly)
                // ponytail: nearest matching-basin region is good enough; GTWO areas rarely overlap.
                d.area = regions.first(where: { $0.0 == basinCode })?.1 ?? []
                return d
            }
        }

        var all = build(two.features ?? [], sevenOnly: false)
        let existing = Set(all.map(\.id))
        all += build(seven.features ?? [], sevenOnly: true).filter { !existing.contains($0.id) }
        return all
    }
}

// MARK: - ATCF model guidance (a-decks)
//
// This is the same data Tropical Tidbits plots: every model's track and intensity
// forecast for a storm, published openly by NHC. It also carries GDMN — the Google
// DeepMind ensemble mean — so DeepMind guidance arrives here with no API key.

struct ModelPoint: Identifiable {
    let tau: Int               // forecast hour
    /// Intensity-only aids (SHIP, LGEM, DSHP, IVCN) publish 0N/0W — no position at all.
    let coord: Coord?
    let windKt: Int?
    let pressureMb: Int?
    var id: Int { tau }
}

struct ModelTrack: Identifiable {
    let tech: String           // ATCF technique id, e.g. "GDMN"
    let cycle: String          // initialisation cycle, YYYYMMDDHH
    let points: [ModelPoint]

    var id: String { tech }
    var name: String { ATCF.names[tech] ?? tech }
    var isDeepMind: Bool { tech.hasPrefix("GDM") }

    /// Positions only. Intensity-only aids contribute nothing here.
    var path: [Coord] { points.compactMap(\.coord) }
    var hasTrack: Bool { path.count > 1 }

    var intensityPoints: [ModelPoint] { points.filter { $0.windKt != nil } }
    var hasIntensity: Bool { intensityPoints.count > 1 }

    /// Last point that actually has a position — where the track label goes.
    var lastPositioned: ModelPoint? { points.last { $0.coord != nil } }

    var cycleLabel: String {
        guard cycle.count == 10 else { return cycle }
        let day = cycle.dropFirst(6).prefix(2)
        let hour = cycle.suffix(2)
        return "\(day)/\(hour)Z"
    }

    var finalPoint: ModelPoint? { points.last }
}

enum ATCFError: LocalizedError {
    case notGzip, truncated
    var errorDescription: String? {
        switch self {
        case .notGzip: return "Model guidance file was not gzip data"
        case .truncated: return "Model guidance file was truncated"
        }
    }
}

extension Data {
    /// RFC 1952 gzip. Apple's `.zlib` algorithm is raw DEFLATE (RFC 1951), so the gzip
    /// wrapper has to come off first — header, optional fields, and the 8-byte trailer.
    func gunzipped() throws -> Data {
        let bytes = [UInt8](self)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b else { throw ATCFError.notGzip }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 {                                  // FEXTRA
            guard i + 1 < bytes.count else { throw ATCFError.truncated }
            i += 2 + (Int(bytes[i]) | Int(bytes[i + 1]) << 8)
        }
        if flags & 0x08 != 0 {                                  // FNAME
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x10 != 0 {                                  // FCOMMENT
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x02 != 0 { i += 2 }                         // FHCRC
        guard i < bytes.count - 8 else { throw ATCFError.truncated }
        let deflated = Data(bytes[i..<(bytes.count - 8)])
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }
}

enum ATCF {
    /// Shown by default. Everything else (GEFS/ECMWF ensemble members, interpolated
    /// variants) is spaghetti you opt into.
    static let featured = ["OFCL", "GDMN", "AVNO", "HFSA", "HFSB", "HMON",
                           "CMC", "UKX", "NVGM", "AEMN", "HCCA", "TVCN", "IVCN",
                           "DSHP", "LGEM", "SHIP"]

    static let names: [String: String] = [
        "OFCL": "NHC Official Forecast",
        "OFCI": "NHC Official (interpolated)",
        "GDMN": "Google DeepMind (ensemble mean)",
        "GDMI": "Google DeepMind (interpolated)",
        "GDM2": "Google DeepMind (variant)",
        "AVNO": "GFS",
        "AVNI": "GFS (interpolated)",
        "AEMN": "GEFS ensemble mean",
        "AC00": "GEFS control",
        "CMC": "Canadian GEM",
        "CMCI": "Canadian GEM (interpolated)",
        "UKX": "UK Met Office",
        "UKXI": "UK Met Office (interpolated)",
        "NVGM": "Navy NAVGEM",
        "HWRF": "HWRF",
        "HMON": "HMON",
        "HFSA": "HAFS-A",
        "HFSB": "HAFS-B",
        "HCCA": "HFIP corrected consensus",
        "TVCN": "Track variable consensus",
        "IVCN": "Intensity variable consensus",
        "DSHP": "SHIPS with decay",
        "LGEM": "LGEM intensity",
        "SHIP": "SHIPS intensity",
        "CLP5": "CLIPER5 climatology",
        "TCLP": "Climatology and persistence",
        "XTRP": "Extrapolation",
        "CARQ": "Analysis"
    ]

    /// Techniques that are bookkeeping rather than forecasts.
    private static let skipped: Set<String> = ["CARQ", "WRNG"]

    static func url(for storm: Storm) -> URL? {
        let basin = storm.basin.rawValue.lowercased()
        let file = String(format: "a%@%02d%d.dat.gz", basin, storm.stormNumber, storm.year)
        return URL(string: "https://ftp.nhc.noaa.gov/atcf/aid_public/\(file)")
    }

    static func modelTracks(for storm: Storm) async throws -> [ModelTrack] {
        guard let url = url(for: storm) else { return [] }
        let text = String(decoding: try await Net.data(url).gunzipped(), as: UTF8.self)
        return parse(text)
    }

    /// One a-deck line per technique, tau and wind-radius threshold. We keep each
    /// technique's own most recent cycle — models and the official forecast run on
    /// different clocks, so a single global "latest cycle" would silently drop OFCL.
    static func parse(_ text: String) -> [ModelTrack] {
        var latestCycle: [String: String] = [:]
        var points: [String: [Int: ModelPoint]] = [:]

        for line in text.split(separator: "\n") {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count > 9 else { continue }

            let cycle = f[2], tech = f[4]
            guard !tech.isEmpty, !skipped.contains(tech), cycle.count == 10 else { continue }
            guard let tau = Int(f[5]), tau >= 0 else { continue }

            if let known = latestCycle[tech] {
                if cycle < known { continue }
                if cycle > known { points[tech] = [:] }          // newer run supersedes
            }
            latestCycle[tech] = cycle

            // Rows repeat per wind-radius threshold; the first one carries the position.
            if points[tech]?[tau] != nil { continue }

            // 0N/0W is ATCF for "no position" — SHIP, LGEM, DSHP and IVCN forecast
            // intensity only. Taking it literally would draw tracks to the Gulf of Guinea.
            let lat = degrees(f[6], positive: "N")
            let lon = degrees(f[7], positive: "E")
            var coord: Coord?
            if let lat, let lon, !(lat == 0 && lon == 0) {
                coord = Coord(latitude: lat, longitude: lon)
            }
            let wind = Int(f[8]).flatMap { $0 > 0 ? $0 : nil }
            let pressure = Int(f[9]).flatMap { $0 > 0 ? $0 : nil }
            guard coord != nil || wind != nil else { continue }

            points[tech, default: [:]][tau] = ModelPoint(
                tau: tau, coord: coord, windKt: wind, pressureMb: pressure)
        }

        return points.compactMap { tech, byTau -> ModelTrack? in
            let ordered = byTau.values.sorted { $0.tau < $1.tau }
            guard ordered.count >= 2, let cycle = latestCycle[tech] else { return nil }
            return ModelTrack(tech: tech, cycle: cycle, points: ordered)
        }
        .sorted {
            // Featured models first, in listed order, then everything else alphabetically.
            let a = featured.firstIndex(of: $0.tech) ?? Int.max
            let b = featured.firstIndex(of: $1.tech) ?? Int.max
            return a == b ? $0.tech < $1.tech : a < b
        }
    }

    /// ATCF stores coordinates in tenths of a degree with a hemisphere suffix: "255N", "1416W".
    static func degrees(_ field: String, positive: Character) -> Double? {
        guard let hemisphere = field.last, hemisphere.isLetter,
              let tenths = Int(field.dropLast()) else { return nil }
        let value = Double(tenths) / 10
        return hemisphere == positive ? value : -value
    }
}

// MARK: - Text products

extension String {
    /// Pulls the <pre> block out of an NHC product page and unescapes it.
    var nhcProductText: String {
        var body = self
        if let open = range(of: "<pre", options: .caseInsensitive),
           let gt = range(of: ">", range: open.upperBound..<endIndex),
           let close = range(of: "</pre", options: .caseInsensitive, range: gt.upperBound..<endIndex) {
            body = String(self[gt.upperBound..<close.lowerBound])
        }
        return body.strippingHTMLTags.unescapingHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingHTMLTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    var unescapingHTMLEntities: String {
        var s = self
        for (k, v) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                       ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }
}
