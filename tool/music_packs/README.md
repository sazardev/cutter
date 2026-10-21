# Music packs

The app downloads music as zip packs, one per genre, listed in a catalog.
This folder builds both.

```
dart run tool/music_packs/build_packs.dart --out build/music_packs
dart run tool/music_packs/build_packs.dart --only epic --limit 3   # a quick trial
```

It needs `ffmpeg` and `ffprobe` on the PATH. For each source in
`sources.json` it downloads the tracks, re-encodes them to 128 kbps MP3 (the
FreePD originals average 5 MB each), writes `<pack id>.zip` and
`catalog.json`.

Normally you do not run it: the **Music packs** workflow (Actions tab, Run
workflow) builds every pack on GitHub's runners and publishes the zips and
`catalog.json` as the `music-v1` release. `baseUrl` in `sources.json` and the
app's default catalog URL both point at that release, so the app needs no
setup. To try packs of your own, serve the output folder and set
`MUSIC_CATALOG_URL` in `.env`.

## What a pack is

A zip holding only sounds (`mp3 m4a aac ogg opus wav flac`) and a
`pack.json` with `{"tracks": [{"file", "title", "artist", "durationMs",
"bpm", "mood"}]}`. The app refuses any other entry, any path with `..`, and
any zip whose size differs from the catalog's `bytes`.

## Sources

| Source | Licence | State |
| --- | --- | --- |
| FreePD, through its archive.org copy (`freepd`) | CC0 per FreePD | In `sources.json`. FreePD closed in 2025 and the archive item carries no licence field, so the CC0 claim rests on FreePD's own statement. The item also holds files that are not FreePD tracks (outside the genre folders), which the script skips. |
| Others (Kenney, OpenGameArt, Incompetech, Free Music Archive) | CC0 / CC-BY | Not added: their sites refused automated access when this was written, so their URLs and terms were not verified. Add them under `directTracks` once checked. |

`CC-BY` tracks need a credit: put the text in the source's `attribution`; the
pack screen shows it.

Do not add Pixabay Music or AI-platform exports (Suno, Udio) without reading
their terms on redistributing the files inside an app.
