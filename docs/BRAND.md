# BRAND.md: Cutter

## Name
**Cutter**. One word, names the core gesture (cut), reads the same in English and Spanish, and is already the package, binary and window title. The product is an editor only, so the name never promises a feed or a network.

## Positioning
Cutter is the multi-layer video editor that fits in your pocket: stack video, images, music and voice on layers, cut with precision, and keep everything on your device.

- **Tagline (en):** Layer. Cut. Done.
- **Tagline (es):** Capas. Cortes. Listo.
- **One line (en):** Multi-layer video editor for phones and tablets. Works offline.
- **One line (es):** Editor de video por capas para móviles y tablets. Funciona sin conexión.
- **Audience:** creators who record and cut short layered videos on a phone (P1); tablet editors who build longer compositions (P2).
- **Proof points** (each is a SPEC.md requirement, claim nothing else): multi-layer timeline, split / trim / reverse, filters and presets, voice-over, music packs, local-first, no account needed to edit.

## Voice
Direct, calm, short. Verbs first ("Cut with precision"), no hype, no emoji in product copy, no exclamation marks. Say what happens, not how great it is.

## Logo
Three staggered clips on three layers, cut by one diagonal: layers + cut in one shape.

| Asset | File |
| --- | --- |
| Launcher icon (full bleed) | `assets/brand/app_icon.svg` |
| Mark only (transparent) | `assets/brand/logo_mark.svg` |
| Android adaptive foreground | `assets/brand/icon_foreground.svg` |
| Android themed (monochrome) | `assets/brand/icon_monochrome.svg` |
| In-app widget | `lib/app/brand/brand_mark.dart` (`BrandMark`, theme roles) |

- Brand color `#6750A4` (the DESIGN.md seed) behind the mark. Clips use `#FFFFFF`, `#EADDFF`, `#D0BCFF` (`onPrimary`, `primaryContainer`, `inversePrimary`).
- Clear space around the mark: at least the height of one clip bar. Minimum size 24dp.
- Never: recolor the clips outside those roles, rotate the cut, add a shadow or outline, put the mark on a busy photo.
- Regenerate every platform icon and splash asset after editing an SVG: `tool/brand/build_icons.sh` (needs `rsvg-convert`).

Platform outputs: Android legacy + adaptive + themed icons and the splash (`res/mipmap-*`, `values-v31`, `drawable/launch_background.xml`), iOS `AppIcon.appiconset`, Linux `linux/runner/resources/cutter.png` and `cutter.desktop`.

## Store listing (ASO / SEO)
Title and short description carry the highest-weight keywords; do not repeat a keyword across fields.

**Google Play / App Store (en)**
- Title (≤30): `Cutter: Layered Video Editor`
- Short description (≤80): `Layer video, images and music. Cut, trim and mix offline on phone or tablet.`
- Keywords (iOS, ≤100): `video editor,layers,cut,trim,split,timeline,overlay,voice over,music,filters,offline,tablet`
- Full description opening: "Cutter is a multi-layer video editor for phones and tablets. Stack video, images, music and voice-over on separate layers, split and trim on a precise timeline, add filters, and export. Your projects stay on your device."

**Google Play / App Store (es)**
- Título (≤30): `Cutter: Editor de video`
- Descripción corta (≤80): `Edita video por capas con imágenes y música. Corta y mezcla sin conexión.`
- Palabras clave (iOS): `editor de video,capas,cortar,recortar,dividir,línea de tiempo,superponer,voz en off,música,filtros,sin conexión,tablet`

**Linux:** `cutter.desktop` carries `GenericName`, `Comment`, `Categories=AudioVideo;Video;AudioVideoEditing;` and `Keywords` for software centers.

**Screenshot order** (caption on each, one verb): 1 Layers timeline ("Layer"), 2 split at playhead ("Cut"), 3 filters and presets ("Tune"), 4 tablet layout ("Compose"), 5 export ("Share").

## Before launch
- Verify the name is free in the Play Store, App Store and trademark registers of target markets (not checked here).
- Replace the placeholder application ID `com.example.cutter` (Linux) and confirm the Android/iOS bundle IDs.
- Capture the screenshots from a profile build.
