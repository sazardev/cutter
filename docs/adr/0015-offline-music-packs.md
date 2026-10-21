# 0015: Offline music packs

Date: 2026-10-21. Status: accepted.

## Context

Creators want music for every kind of video without hunting for files. The
product is local-first and has no cloud processing, so the music has to live
on the device and work offline once fetched. Shipping every track in the
installer is not an option (the FreePD originals alone average 5 MB a track).

## Decision

- Music comes as **packs**: one zip per genre, listed in a JSON catalog the
  app reads from `MUSIC_CATALOG_URL`. The catalog is cached on disk, so the
  list shows offline.
- The app downloads a pack with `dart:io` (streamed to disk), unpacks it in an
  isolate with the `archive` package (added with the owner's approval), and
  keeps it under `<app support>/music/<pack id>/`. Nothing is stored in
  drift: the folder is the source of truth (`pack.json` lists the tracks,
  `installed.json` is written last and marks a complete install), so no schema
  change and no outbox entry are involved. Packs are device data, not
  project data, and are never synced.
- A zip is data from the network: the app refuses entries that are not
  sounds or `pack.json`, any path leaving the folder, and a zip whose size
  differs from the catalog's. A failed install leaves no files and keeps an
  older copy.
- A track is placed through the existing import (`importPaths`), so it joins
  the project's media bank like any file and the engine is unchanged.
- `tool/music_packs/build_packs.dart` builds the zips and the catalog from
  `sources.json`: it downloads tracks from sources with an allowed licence,
  re-encodes them to 128 kbps MP3, and writes the zips and `catalog.json` for
  the owner to host. The `Music packs` workflow (manual) runs it on GitHub's
  runners and publishes the result as the `music-v1` release, whose
  `catalog.json` is the app's default catalog URL. The packs are hosted by the project, not fetched from each
  source's site, because the sources publish no zips, some closed (FreePD in
  2025) and some refuse automated access.
- The pack icon comes from the genre (Material icons); source logos are not
  shipped, since they are third-party marks.
- The release manifest gains `INTERNET`; this is the only thing the app
  fetches.

## Consequences

- "Offline" means offline after the first download of a pack.
- Licence checking is the owner's job: `sources.json` records each source's
  licence, the app shows it and any required credit, but only the owner can
  confirm a source's terms. FreePD's CC0 claim rests on its own statement.
- No in-app preview of a track before it is placed; that needs the engine's
  audio playback outside a timeline and is left for later.
- The archive.org download from the FreePD copy was not run from the
  development machine (its firewall cut the audio transfer); the builder was
  exercised against a local server instead.
