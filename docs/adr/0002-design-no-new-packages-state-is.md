# 0002. Design: No new packages: state is a ChangeNotifier (EditorController) listened to with ListenableBuilder, because AGENTS.md forbids adding a dependency without asking and Riverpod is not declared

## Status

Accepted · 2026-10-21

## Context

Build of Cutter interface (design · from DESIGN.md). Builds the Cutter editor UI as Material 3 Expressive screens on top of the existing Flutter foundation. No domain or engine exists yet, so every screen reads one small sample-data file and a ChangeNotifier EditorController holds only UI state over that sample. The app opens on the Editor: a preview canvas, a transport bar, a layered timeline with a playhead, and a toolbar. The toolbar opens the clip inspector, media picker, record sheet, filters, presets and templates. Colors, type, spacing and shapes come from a theme built once from DESIGN.md tokens. Widgets read only the theme and AppLocalizations; every visible string is an ARB key. The controller is the single seam to swap for the Rust FFI engine later.

## Decision

Architecture: lib/app/theme: tokens (spacing, radii, window classes) and ThemeData builders; widgets read only Theme.of and these constants. lib/features/editor/data: sample models and sample data, a stand-in for the future domain. lib/features/editor/presentation: EditorController (UI state and edit rules over the sample), widgets (preview, timeline, clip tile, transport, toolbar), sheets/pages (inspector, media picker, record, filters, presets, templates), and EditorPage as the screen. lib/app/app.dart composes theme plus EditorPage. Dependencies run one way: app -> editor pages -> widgets -> controller -> sample data, and everything -> theme tokens and l10n. Widgets never import each other's pages; sheets receive the controller and callbacks by constructor.

- No new packages: state is a ChangeNotifier (EditorController) listened to with ListenableBuilder, because AGENTS.md forbids adding a dependency without asking and Riverpod is not declared.
- The project timebase is integer milliseconds, decided for the UI. Minimum clip duration is 100 ms. A split needs the playhead strictly inside the clip. Move onto an occupied range on the same layer is rejected, never resolved. Move across layers is allowed only to a layer of the same kind.
- Edit rules return an EditorOutcome enum (ok, noClipSelected, playheadOutsideClip, zeroDuration, overlap, wrongLayerKind); pages map the outcome to a localized snackbar in one place (EditorPage). Expected failures are values, not exceptions.
- Theme is built from explicit ColorScheme roles using the DESIGN.md light and dark values; component shapes are set once in the theme (cards, filled buttons, sheets, snackbars) and widgets never pass shape or Color(0x...). ThemeMode follows the system.
- Layout uses LayoutBuilder against window classes: compact (<600) is a single column with the toolbar docked at the bottom (thumb zone); medium and up places the preview beside the inspector panel and the timeline below, with 24dp margins instead of 16dp.
- Motion uses implicit animations with a spring-like curve (Curves.easeOutBack for spatial, Curves.easeOut for effects) and returns Duration.zero when MediaQuery.disableAnimationsOf is true. Expressive emphasis (primary-container, large shape) is used only on the play button.
- Every interactive control has a Semantics label from ARB and a 48dp minimum target; clips announce name, layer, start and duration; selection is shown by a border plus a check icon, not by color alone.
- Sample permissions: microphone granted, camera denied, so the Record sheet shows both the working and the denied path.

## Consequences

- Files created: lib/app/theme/app_tokens.dart, lib/app/theme/app_theme.dart, lib/features/editor/data/sample_models.dart, lib/features/editor/data/sample_project.dart, lib/features/editor/presentation/editor_controller.dart, lib/features/editor/presentation/widgets/preview_canvas.dart, lib/features/editor/presentation/widgets/timeline_clip_tile.dart, lib/features/editor/presentation/widgets/timeline_view.dart, lib/features/editor/presentation/widgets/transport_bar.dart, lib/features/editor/presentation/widgets/editor_toolbar.dart, lib/features/editor/presentation/clip_inspector_sheet.dart, lib/features/editor/presentation/media_picker_page.dart, lib/features/editor/presentation/record_sheet.dart, lib/features/editor/presentation/filters_sheet.dart, lib/features/editor/presentation/presets_sheet.dart, lib/features/editor/presentation/templates_page.dart, lib/features/editor/presentation/editor_page.dart, test/features/editor/editor_controller_test.dart, test/features/editor/editor_page_test.dart
- Files changed: lib/l10n/app_en.arb, lib/app/app.dart, test/smoke_test.dart, README.md
- Later changes follow these decisions; one that reverses a decision gets a new ADR that supersedes this one.
