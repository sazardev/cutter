# 0012. Appearance settings: theme mode, color source, corner style and text size

## Status

Accepted · 2026-10-21

## Context

The user asked for a settings screen on the home page to change the theme (light, dark, system), the color (Material You, a palette or a custom one), the corner style (custom, clean, consistent) and the font size.

## Decision

- `lib/features/settings/` holds the feature: `AppearanceSettings` (plain, immutable, with defaults), the `AppearanceRepository` port, a drift adapter over `SettingsStore`, and the settings page.
- Preferences are one `app_settings` row per field under the `appearance.` prefix. No schema change. Unreadable or out-of-range values fall back to the default.
- `main` reads them before the first frame (`initialAppearanceProvider`), so the app never flashes the default look. `appearanceProvider` repaints at once; sliders call `preview` while dragging and `commit` on release, so one drag is one write.
- `AppTheme.build(brightness, settings:, dynamicScheme:)` builds the theme. `ShapeScale` derives every radius from the medium step (clean 4dp, consistent 12dp, custom 0 to 24dp); buttons are pills only in the consistent style.
- Material You uses `dynamic_color` pinned to `^1.9.0` (2.x depends on `material_ui`, whose `ColorScheme` is not Flutter's). Where the device has no palette, the option is disabled and the preset color is used.
- Text scale (0.8 to 1.4) multiplies the system scale in `MaterialApp.builder`, so both accessibility settings add up.

## Consequences

- The editor screens still use `AppTheme.dark()` (DESIGN.md: the editor is always dark), so they keep the brand color and corners until a follow-up passes the settings to them.
- Added: `dynamic_color`, `SettingsStore.readPrefixed/writeAll`, `lib/features/settings/`, `lib/app/theme/seed_presets.dart`, `settingsTitle` and related ARB keys.
