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
check(storm(wind: 85).atcfID == "07E", "ATCF id for Tropical Tidbits")
check(storm(wind: 85).headline == "Category 2 Hurricane", "headline")

check(Storm.compass(0) == "N", "compass N")
check(Storm.compass(90) == "E", "compass E")
check(Storm.compass(290) == "WNW", "compass WNW")
check(Storm.compass(359) == "N", "compass wraps at 360")

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
