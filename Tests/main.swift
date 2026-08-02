// ponytail: one assert-based binary over the parsing/geometry logic, no test framework.
// Run with ./test.sh — it compiles this against Sources/Hurakai/Data.swift.
import Foundation
import MapKit

func check(_ condition: Bool, _ label: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL: \(label)\n".utf8))
        exit(1)
    }
    print("ok  \(label)")
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    try! JSONDecoder().decode(type, from: Data(json.utf8))
}

// MARK: GeoJSON geometry flattening

let point = decode(GJGeometry.self, #"{"type":"Point","coordinates":[-120.1,19.2]}"#)
check(point.coordinates?.paths.count == 1, "Point -> one path")
check(point.coordinates?.paths.first?.count == 1, "Point -> one coordinate")
check(point.coordinates?.paths.first?.first?.latitude == 19.2, "Point latitude comes from index 1")
check(point.coordinates?.paths.first?.first?.longitude == -120.1, "Point longitude comes from index 0")

let line = decode(GJGeometry.self, #"{"type":"LineString","coordinates":[[-120,19],[-121,20],[-122,21]]}"#)
check(line.coordinates?.paths.count == 1, "LineString -> one path")
check(line.coordinates?.paths.first?.count == 3, "LineString keeps its points together")

let polygon = decode(GJGeometry.self,
    #"{"type":"Polygon","coordinates":[[[-120,19],[-121,20],[-122,21],[-120,19]]]}"#)
check(polygon.coordinates?.paths.count == 1, "Polygon -> one ring")
check(polygon.coordinates?.paths.first?.count == 4, "Polygon ring keeps all vertices")

let multi = decode(GJGeometry.self,
    #"{"type":"MultiPolygon","coordinates":[[[[-1,1],[-2,2],[-3,3],[-1,1]]],[[[10,10],[11,11],[12,12],[10,10]]]]}"#)
check(multi.coordinates?.paths.count == 2, "MultiPolygon -> one path per ring")
check(multi.coordinates?.paths.allSatisfy { $0.count == 4 } == true, "MultiPolygon rings stay intact")

// MARK: Feature property access

let feature = decode(GJFeature.self, #"""
{"type":"Feature",
 "properties":{"binnumber":"EP2","stormname":"Genevieve","maxwind":85,"mslp":970,"tcww":null,"advisnum":"23"},
 "geometry":{"type":"Point","coordinates":[-120.1,19.2]}}
"""#)
check(feature.str("binnumber") == "EP2", "string property")
check(feature.int("maxwind") == 85, "numeric property as Int")
check(feature.str("maxwind") == "85", "numeric property rendered without decimal point")
check(feature.str("advisnum") == "23", "quoted number stays a string")
check(feature.str("tcww") == nil, "null property is nil")
check(feature.str("nope") == nil, "missing property is nil")
check(feature.point?.latitude == 19.2, "feature point")

// MARK: Lenient integers (the live NHC feed quotes numbers inconsistently)

struct Holder: Decodable { let v: LooseInt? }
check(decode(Holder.self, #"{"v":85}"#).v?.value == 85, "LooseInt from number")
check(decode(Holder.self, #"{"v":"85"}"#).v?.value == 85, "LooseInt from quoted number")
check(decode(Holder.self, #"{"v":"85.0"}"#).v?.value == 85, "LooseInt from quoted decimal")
check(decode(Holder.self, #"{"v":null}"#).v?.value == nil, "LooseInt from null")
check(decode(Holder.self, #"{"v":"NNW"}"#).v?.value == nil, "LooseInt from junk is nil, not a crash")
check(decode(Holder.self, "{}").v == nil, "LooseInt absent")

// MARK: Region math

let pacific = regionCovering([Coord(latitude: 10, longitude: -140), Coord(latitude: 20, longitude: -120)])!
check(abs(pacific.center.latitude - 15) < 0.001, "region centers latitude")
check(abs(pacific.center.longitude - (-130)) < 0.001, "region centers longitude")

// A Central Pacific storm straddling the dateline must stay zoomed in, not span the globe.
let dateline = regionCovering([Coord(latitude: 15, longitude: 178), Coord(latitude: 17, longitude: -177)])!
check(dateline.span.longitudeDelta < 30, "antimeridian span stays local (\(dateline.span.longitudeDelta))")
check(dateline.center.longitude > 179 || dateline.center.longitude < -179,
      "antimeridian center sits on the dateline (\(dateline.center.longitude))")
check(regionCovering([]) == nil, "empty coordinate set has no region")

// MARK: Storm derived values

func storm(wind: Int, _ classification: String = "HU") -> Storm {
    Storm(id: "ep072026", bin: "EP2", name: "Genevieve", classification: classification,
          basin: .ep, stormNumber: 7, year: 2026, windKt: wind, gustKt: nil, pressureMb: 970,
          coord: Coord(latitude: 19.2, longitude: -120.1), movementDir: 290, movementKt: 9,
          lastUpdate: nil, advisoryNumber: "23", products: [])
}

check(storm(wind: 63).category == 0, "63 kt is not a hurricane")
check(storm(wind: 64).category == 1, "64 kt is category 1")
check(storm(wind: 82).category == 1, "82 kt is category 1")
check(storm(wind: 83).category == 2, "83 kt is category 2")
check(storm(wind: 96).category == 3, "96 kt is category 3")
check(storm(wind: 113).category == 4, "113 kt is category 4")
check(storm(wind: 137).category == 5, "137 kt is category 5")
check(storm(wind: 120, "TS").category == 0, "a tropical storm never gets a category")
// Against the numbers NHC actually prints in its advisories.
check(storm(wind: 35).windMph == 40, "35 kt is 40 mph")
check(storm(wind: 65).windMph == 75, "65 kt is 75 mph")
check(storm(wind: 85).windMph == 100, "85 kt is 100 mph")
check(storm(wind: 100).windMph == 115, "100 kt is 115 mph")
check(storm(wind: 137).windMph == 160, "137 kt is 160 mph")
check(storm(wind: 85).headline == "Category 2 Hurricane", "headline")

check(Storm.compass(0) == "N", "compass N")
check(Storm.compass(90) == "E", "compass E")
check(Storm.compass(290) == "WNW", "compass WNW")
check(Storm.compass(359) == "N", "compass wraps at 360")

// MARK: ATCF a-deck (model guidance, including Google DeepMind's GDMN)

check(ATCF.degrees("255N", positive: "N") == 25.5, "latitude tenths north")
check(ATCF.degrees("112S", positive: "N") == -11.2, "latitude tenths south")
check(ATCF.degrees("1416W", positive: "E") == -141.6, "longitude tenths west")
check(ATCF.degrees("0653E", positive: "E") == 65.3, "longitude tenths east")
check(ATCF.degrees("", positive: "N") == nil, "empty coordinate field")
check(ATCF.degrees("NNW", positive: "N") == nil, "junk coordinate field")

let deck = """
EP, 07, 2026073012, 03, GDMN,   0, 200N, 1240W,  60, 0990, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073012, 03, GDMN,  12, 210N, 1250W,  55, 0995, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, GDMN,   0, 205N, 1245W,  58, 0992, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, GDMN,  12, 215N, 1256W,  50, 0998, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, GDMN,  12, 215N, 1256W,  50, 0998, XX,  50, NEQ,  20,  10,  10,  10
EP, 07, 2026073018, 03, GDMN,  24, 220N, 1265W,  45, 1000, XX,  34, NEQ,  30,  20,  10,  20
EP, 07, 2026073015, 03, OFCL,   0, 204N, 1244W,  60, 0991, HU,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073015, 03, OFCL,  12, 213N, 1254W,  55, 0995, HU,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, CARQ,   0, 205N, 1245W,  58, 0992, HU,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, AVNO,   0, 206N, 1246W,  57,    0, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, AVNO,  12, 216N, 1257W,  52,    0, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, ONLY,   6, 208N, 1248W,  55, 0993, XX,  34, NEQ,  40,  30,  20,  30
EP, 07, 2026073018, 03, IVCN,  12,   0N,    0W,  50,    0,   ,   0,    ,   0,   0,   0,   0
EP, 07, 2026073018, 03, IVCN,  24,   0N,    0W,  45,    0,   ,   0,    ,   0,   0,   0,   0
EP, 07, 2026073018, 03, IVCN,  36,   0N,    0W,   0,    0,   ,   0,    ,   0,   0,   0,   0
"""
let tracks = ATCF.parse(deck)
let byTech = Dictionary(uniqueKeysWithValues: tracks.map { ($0.tech, $0) })

check(!tracks.contains { $0.tech == "CARQ" }, "analysis rows are not a forecast model")
check(!tracks.contains { $0.tech == "ONLY" }, "a technique with one point is dropped")
check(byTech["GDMN"] != nil, "DeepMind GDMN parsed")
check(byTech["GDMN"]?.isDeepMind == true, "GDMN flagged as DeepMind")
check(byTech["GDMN"]?.name == "Google DeepMind (ensemble mean)", "GDMN named")
check(byTech["GDMN"]?.cycle == "2026073018", "newest run wins")
check(byTech["GDMN"]?.points.count == 3, "superseded run's points are discarded, radii rows deduped")
check(byTech["GDMN"]?.points.map(\.tau) == [0, 12, 24], "points ordered by forecast hour")
check(byTech["GDMN"]?.points[1].coord?.latitude == 21.5, "point latitude from newest run")
check(byTech["GDMN"]?.points[1].coord?.longitude == -125.6, "point longitude from newest run")
check(byTech["GDMN"]?.finalPoint?.windKt == 45, "final intensity")
check(byTech["GDMN"]?.cycleLabel == "30/18Z", "cycle label")
check(byTech["OFCL"]?.cycle == "2026073015", "each technique keeps its own latest cycle")
check(byTech["AVNO"]?.points.first?.pressureMb == nil, "zero pressure means missing, not 0 mb")
check(tracks.first?.tech == "OFCL", "featured models sort first, official first of all")

// Intensity-only aids publish 0N/0W. Taking that literally drew tracks to 0°N 0°E.
check(byTech["IVCN"] != nil, "intensity-only aid is still parsed")
check(byTech["IVCN"]?.points.allSatisfy { $0.coord == nil } == true, "0N/0W means no position")
check(byTech["IVCN"]?.path.isEmpty == true, "intensity-only aid contributes no track path")
check(byTech["IVCN"]?.hasTrack == false, "intensity-only aid is never drawn on the map")
check(byTech["IVCN"]?.lastPositioned == nil, "intensity-only aid has no label anchor")
check(byTech["IVCN"]?.hasIntensity == true, "intensity-only aid does carry intensity")
check(byTech["IVCN"]?.intensityPoints.map(\.tau) == [12, 24], "zero-wind row is not an intensity point")
check(byTech["GDMN"]?.hasTrack == true, "a real model still has a track")
check(byTech["GDMN"]?.path.count == 3, "track path keeps every positioned point")
check(byTech["GDMN"]?.lastPositioned?.tau == 24, "label anchors on the last positioned point")

// gzip: the a-deck is only served gzipped, and Apple's zlib is raw DEFLATE
let gz = Data(base64Encoded:
    "H4sIAGvca2oAA3MN0FEwMNdRMDIwMjMwNzYwtADyjXUU3F18/XQUFAyNgFKGBkCmoZGpQThQxNQUqMDSEkhGRAC5xiY6Cn6ugVwAvWi93kgAAAA=")!
let unzipped = String(decoding: try! gz.gunzipped(), as: UTF8.self)
check(unzipped.contains("GDMN"), "gunzip round-trips an a-deck line")
check(ATCF.parse(unzipped).isEmpty, "a single-point deck yields no track")
var notGzip = false
do { _ = try Data("not gzip at all, definitely not".utf8).gunzipped() } catch { notGzip = true }
check(notGzip, "non-gzip input throws instead of returning garbage")

// MARK: Basin scoping — Eastern and Central Pacific only

check(Basin.parse("EP") == .ep, "EP")
check(Basin.parse("ep") == .ep, "lowercase basin")
check(Basin.parse(" CP ") == .cp, "padded basin")
check(Basin.parse("cpac") == .cp, "CPAC spelling")
check(Basin.parse("Eastern Pacific") == .ep, "spelled-out eastern pacific")
check(Basin.parse("AL") == .al, "Atlantic")
check(Basin.parse("atlantic") == .al, "spelled-out atlantic")
check(Basin.parse(nil) == nil, "missing basin is unknown")
check(Basin.parse("WP") == nil, "west Pacific is not a basin this app covers")
check(Basin.parse("garbage") == nil, "unrecognised basin is unknown, not guessed")

check(Basin.ep.isPacific && Basin.cp.isPacific, "EP and CP are both in scope")
check(!Basin.al.isPacific, "Atlantic is out of scope")
check(Basin.cp.label == "Central Pacific", "CP is the Hawaii domain")

// Hawaii must sit inside the default view.
let honolulu = Coord(latitude: 21.3, longitude: -157.9)
let view = pacificRegion
check(abs(honolulu.latitude - view.center.latitude) < view.span.latitudeDelta / 2,
      "Hawaii is within the default latitude span")
check(abs(honolulu.longitude - view.center.longitude) < view.span.longitudeDelta / 2,
      "Hawaii is within the default longitude span")

// MARK: Product text extraction

let page = """
<html><body><div>nav junk</div>
<pre class="glossaryProduct">
HURRICANE GENEVIEVE DISCUSSION NUMBER 23
Winds are 85 kt &amp; rising &lt;near the center&gt;.
</pre>
<footer>more junk</footer></body></html>
"""
let extracted = page.nhcProductText
check(extracted.hasPrefix("HURRICANE GENEVIEVE"), "pulls the <pre> block")
check(!extracted.contains("nav junk"), "drops surrounding page chrome")
check(extracted.contains("85 kt & rising <near the center>."), "unescapes entities")
check("no pre tags here".nhcProductText == "no pre tags here", "falls back to plain text")

print("\nAll self-checks passed.")
