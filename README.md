# Hurakai

A native macOS app for tracking hurricanes and tropical disturbances in the Pacific.

Live positions, forecast tracks, uncertainty cones, watches and warnings, and Tropical
Weather Outlook disturbance areas on a clickable MapKit chart — plus advisory text,
satellite imagery, and the model-guidance sites forecasters actually use.

Eastern and Central Pacific by default; the Atlantic can be toggled on.

## Screens

- **Map** — every active system on one chart. Click a storm to zoom to its cone and open
  an inspector with current intensity, motion, forecast points, the full public advisory,
  and the forecast discussion. Layers (cone, forecast track, past track, forecast points,
  watches/warnings, disturbance areas, labels) toggle individually. Base map switches
  between hybrid, satellite, and standard.
- **Satellite & Outlook** — NHC/CPHC 2-day and 7-day graphical outlooks, and GOES-West
  GeoColor / Air Mass imagery (full disk and Hawai'i sector).
- **Tropical Tidbits** — model guidance, embedded live and deep-linked to the selected storm.
- **DeepMind Weather Lab** — Google's experimental AI cyclone predictions.
- **Outlook Text** — the Eastern and Central Pacific Tropical Weather Outlook discussions.

Data refreshes on launch, on ⌘R, and every 10 minutes.

## Data sources

| Source | What it provides | How |
| --- | --- | --- |
| NHC `CurrentStorms.json` | Active systems: position, intensity, pressure, motion, advisory links | JSON API |
| NOAA Tropical GIS MapServer | Forecast points, forecast track, uncertainty cone, past track, watches/warnings, TWO disturbance areas | ArcGIS REST → GeoJSON |
| NHC / CPHC text products | Public advisories, forecast discussions, Tropical Weather Outlooks | Product pages, `<pre>` extracted |
| NHC Graphical TWO | 2-day and 7-day outlook graphics | PNG |
| NOAA NESDIS/STAR | GOES-18 (GOES-West) GeoColor and Air Mass imagery | JPEG |
| Tropical Tidbits | Model track and intensity guidance | Embedded web view |
| Google DeepMind Weather Lab | Experimental AI cyclone predictions | Embedded web view |

Both Central Pacific (CPHC) and Eastern Pacific (NHC) systems come through the same feeds —
the GIS service and `CurrentStorms.json` cover the `EP`, `CP`, and `AL` basins.

### Two sources are embedded rather than parsed, on purpose

- **Tropical Tidbits** returns HTTP 403 to direct image requests, including with a browser
  user agent. Scraping it would mean defeating a block its operator put there deliberately,
  so the app embeds the real site instead and deep-links to the selected storm's ATCF id.
- **Google DeepMind Weather Lab** has no public API and requires a Google sign-in. The app
  embeds it so you can sign in yourself; it does not handle credentials.

If you have Google Cloud access, WeatherNext cyclone data is available through BigQuery and
Earth Engine and could be pulled directly — that needs a GCP credential this app doesn't ask for.

## Build

Requires macOS 14+ and Command Line Tools (full Xcode not needed).

```bash
./build.sh && open build/Hurakai.app
```

Self-checks over the parsing and geometry logic:

```bash
./test.sh
```

There is no `Package.swift`: `build.sh` calls `swiftc` directly and assembles the bundle.
MapKit and WebKit need a real `.app` (bundle id + `Info.plist`) either way, so a SwiftPM
manifest bought nothing — and the `PackageDescription` library shipped with Command Line
Tools fails to link at any tools-version.

The bundle is ad-hoc signed. Gatekeeper will ask on first launch since it isn't notarized.

## Layout

```
Sources/Hurakai/Data.swift     models, GeoJSON decoding, feeds, networking
Sources/Hurakai/App.swift      app entry, refresh loop, shell and layer menu
Sources/Hurakai/MapPane.swift  map, overlays, pins, Saffir-Simpson palette
Sources/Hurakai/Panels.swift   sidebar, inspector, imagery, web and text panes
Tests/main.swift               assert-based self-checks
```

## Not a forecast product

Hurakai displays official NHC/CPHC data but is not itself an official source. For warnings
and protective decisions, use [hurricanes.gov](https://www.nhc.noaa.gov) and your local
NWS office.
