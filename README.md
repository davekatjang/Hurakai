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
- **Models** (inspector tab) — full ATCF model guidance for the selected storm, drawn as a
  spaghetti plot with labelled endpoints. Each technique can be toggled individually;
  featured models are on by default and "Every technique" reveals the ensemble members.
  Includes **GDMN, the Google DeepMind ensemble mean**.
- **Intensity Models** — the intensity counterpart to the track spaghetti: every technique's
  wind forecast against forecast hour, with Saffir-Simpson thresholds marked and the official
  forecast drawn heavier. Shares the same model toggles as the map, so turning a technique off
  in one place turns it off in both. Includes the intensity-only aids (SHIP, LGEM, DSHP, IVCN)
  that have no track to plot.
- **Tropical Tidbits** — the site itself, embedded live and deep-linked to the selected storm.
- **DeepMind Weather Lab** — Google's experimental AI cyclone predictions.
- **Outlook Text** — the Eastern and Central Pacific Tropical Weather Outlook discussions.

Data refreshes on launch, on ⌘R, and every 10 minutes.

## Data sources

| Source | What it provides | How |
| --- | --- | --- |
| NHC `CurrentStorms.json` | Active systems: position, intensity, pressure, motion, advisory links | JSON API |
| NOAA Tropical GIS MapServer | Forecast points, forecast track, uncertainty cone, past track, watches/warnings, TWO disturbance areas | ArcGIS REST → GeoJSON |
| NHC ATCF a-decks | Every model's track and intensity guidance, incl. Google DeepMind (`GDMN`) | Gzipped flat file |
| NHC / CPHC text products | Public advisories, forecast discussions, Tropical Weather Outlooks | Product pages, `<pre>` extracted |
| NHC Graphical TWO | 2-day and 7-day outlook graphics | PNG |
| NOAA NESDIS/STAR | GOES-18 (GOES-West) GeoColor and Air Mass imagery | JPEG |
| Tropical Tidbits | Model track and intensity guidance | Embedded web view |
| Google DeepMind Weather Lab | Experimental AI cyclone predictions | Embedded web view |

Both Central Pacific (CPHC) and Eastern Pacific (NHC) systems come through the same feeds —
the GIS service and `CurrentStorms.json` cover the `EP`, `CP`, and `AL` basins.

### Model guidance comes from the a-deck, not from scraping

Tropical Tidbits plots the NHC **ATCF a-deck** — `aid_public/a{basin}{nn}{year}.dat.gz` — which
NHC publishes openly. Hurakai reads the same file, so the model numbers behind those plots are
available natively: every technique's latest run, its track, and its intensity forecast.

Each technique keeps its own most recent initialisation cycle rather than a single global
"latest" one, because models run at 00/06/12/18Z while the official forecast runs at
03/09/15/21Z — a global cutoff would silently drop `OFCL`.

Two conventions in that file are easy to get wrong. Rows repeat per wind-radius threshold
(34/50/64 kt), so positions have to be de-duplicated by forecast hour. And intensity-only
aids — `SHIP`, `LGEM`, `DSHP`, `IVCN` — publish `0N`/`0W` rather than omitting the position,
so taking it literally draws a track from the storm to 0°N 0°E. Those points carry intensity
but no position, and the app treats them that way: absent from the map, present in the
intensity chart.

**This is also where Google DeepMind's guidance lives.** `GDMN` is the DeepMind ensemble mean,
contributed to NHC's guidance suite, and it arrives with no API key, no GCP project, and no
sign-in. `GDMI` (interpolated) and `GDM2` appear alongside it.

### Two sources are embedded rather than parsed, on purpose

- **Tropical Tidbits** returns HTTP 403 to direct image requests, including with a browser
  user agent. Scraping it would mean defeating a block its operator put there deliberately,
  so the app embeds the real site instead and deep-links to the selected storm's ATCF id.
  The underlying model data is read from the a-deck, as above.
- **Google DeepMind Weather Lab** has no public API and requires a Google sign-in. The app
  embeds it so you can sign in yourself; it does not handle credentials.

### WeatherNext via BigQuery / Earth Engine — not wired, and probably not needed

Google's WeatherNext datasets are reachable through BigQuery and Earth Engine, but for
*cyclone track and intensity guidance* they are the long way round to `GDMN`, which this app
already reads for free. BigQuery would add value only if you want the **gridded** fields —
global forecast grids of wind, pressure, temperature and precipitation, or per-member
ensemble output — rather than cyclone tracks.

That path is deliberately not implemented, because it cannot be built or tested without
your own credentials. It needs a GCP project with billing, the WeatherNext datasets
subscribed through Analytics Hub, and `gcloud`/`bq` installed (neither is on this machine).
If you want the gridded fields, set up the project and say so — the natural shape is a
small helper that queries BigQuery with your existing `gcloud` credentials and hands the
app JSON, keeping OAuth out of the app entirely.

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
