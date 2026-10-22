import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The colours a text offers for its letters, outline and background. They
/// are content (what ends up in the video), not interface, so they are fixed
/// values and not theme roles.
const _palette = <int>[
  0xFFFFFFFF,
  0xFF000000,
  0xFFFFD60A,
  0xFFFF9F0A,
  0xFFFF453A,
  0xFFFF2D92,
  0xFFBF5AF2,
  0xFF5E5CE6,
  0xFF0A84FF,
  0xFF32D74B,
];

/// Opacity a background colour gets, so the picture still shows through.
const _backgroundAlpha = 0xB3;

/// Longest pause between key strokes that still counts as one burst of
/// typing: the text is saved once it ends.
const _typingPause = Duration(milliseconds: 350);

/// The font families as named in the pubspec, with the name shown for each.
const _fontNames = {
  'sans': 'Sans',
  'serif': 'Serif',
  'mono': 'Mono',
  'anton': 'Anton',
  'bebas': 'Bebas',
  'bangers': 'Bangers',
  'lobster': 'Lobster',
  'pacifico': 'Pacifico',
  'marker': 'Marker',
};

/// Adds a new text at the playhead and returns its id, or null when the
/// edit was rejected. The text is selected, so the text tool edits it.
Future<String?> addTextAtPlayhead(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  unawaited(HapticFeedback.selectionClick());
  final at = ref.read(playbackControllerProvider).positionMs;
  return ref
      .read(editorControllerProvider.notifier)
      .addText(ClipText(content: l10n.textDefaultContent), at);
}

/// Adds texts over the video and styles the selected one: its words, font,
/// size, colour, outline, shadow, background and entrance. Everything shows
/// live in the preview while it is changed; letting go saves it. Dragging,
/// pinching and turning the text in the preview moves it like any picture.
class TextPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const TextPanel({super.key});

  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  String? _clipId;
  ClipText? _draft;
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final id = await addTextAtPlayhead(context, ref);
    if (id == null || !mounted) return;
    // The new text is ready to be typed over.
    _focus.requestFocus();
    _field.selection =
        TextSelection(baseOffset: 0, extentOffset: _field.text.length);
  }

  void _preview(String clipId, ClipText text) {
    setState(() => _draft = text);
    ref.read(playbackControllerProvider.notifier).previewText(clipId, text);
  }

  Future<void> _commit(String clipId, ClipText text) async {
    _typing?.cancel();
    unawaited(HapticFeedback.selectionClick());
    await ref.read(editorControllerProvider.notifier).setText(clipId, text);
    if (mounted) setState(() => _draft = null);
  }

  void _type(String clipId, ClipText current, String words) {
    final text = current.copyWith(content: words);
    _preview(clipId, text);
    _typing?.cancel();
    _typing = Timer(_typingPause, () {
      if (mounted) unawaited(_commit(clipId, text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null || clip.kind != MediaKind.text || clip.text == null) {
      return _AddPrompt(onAdd: _add);
    }
    if (_clipId != clip.id) {
      _clipId = clip.id;
      _draft = null;
      _field.text = clip.text!.content;
    }
    final text = _draft ?? clip.text!;
    final id = clip.id;

    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ClipText Function(double v) apply,
    ) {
      return SliderTile(
        title: label,
        valueLabel: '${(value * 100).round()}%',
        value: value,
        min: min,
        max: max,
        onChanged: (v) => _preview(id, apply(v)),
        onChangeEnd: (v) => _commit(id, apply(v)),
      );
    }

    Widget dot(int color) => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outline),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _field,
          focusNode: _focus,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.layerKindText,
            hintText: l10n.textFieldHint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (words) => _type(id, text, words),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(l10n.textAddAnotherAction),
        ),
        const SizedBox(height: AppSpacing.md),
        ToolSection(
          icon: Icons.text_format,
          title: l10n.textSectionStyle,
          summary: [
            if (text.bold) l10n.textBoldAction,
            if (text.italic) l10n.textItalicAction,
          ].join(' · '),
          initiallyExpanded: true,
          children: [
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              secondary: const Icon(Icons.format_bold),
              title: Text(l10n.textBoldAction),
              value: text.bold,
              onChanged: (v) => _commit(id, text.copyWith(bold: v)),
            ),
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              secondary: const Icon(Icons.format_italic),
              title: Text(l10n.textItalicAction),
              value: text.italic,
              onChanged: (v) => _commit(id, text.copyWith(italic: v)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.textAlignLabel, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ClipTextAlign>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ClipTextAlign.left,
                  icon: const Icon(Icons.format_align_left),
                  tooltip: l10n.textAlignLeftAction,
                ),
                ButtonSegment(
                  value: ClipTextAlign.center,
                  icon: const Icon(Icons.format_align_center),
                  tooltip: l10n.textAlignCenterAction,
                ),
                ButtonSegment(
                  value: ClipTextAlign.right,
                  icon: const Icon(Icons.format_align_right),
                  tooltip: l10n.textAlignRightAction,
                ),
              ],
              selected: {text.align},
              onSelectionChanged: (s) =>
                  _commit(id, text.copyWith(align: s.single)),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.font_download_outlined,
          title: l10n.textSectionFont,
          summary: _fontNames[text.font] ?? text.font,
          children: [
            for (final font in clipTextFonts)
              OptionTile(
                title: _fontNames[font] ?? font,
                titleStyle: TextStyle(
                  fontFamily: font,
                  fontSize: 20,
                  fontWeight: text.bold ? FontWeight.w700 : FontWeight.w400,
                  fontStyle: text.italic ? FontStyle.italic : FontStyle.normal,
                ),
                selected: text.font == font,
                onTap: () => _commit(id, text.copyWith(font: font)),
              ),
          ],
        ),
        ToolSection(
          icon: Icons.format_size,
          title: l10n.textSizeLabel,
          summary: '${(text.size * 100).round()}%',
          children: [
            slider(
              l10n.textSizeLabel,
              text.size,
              minTextSize,
              0.3,
              (v) => text.copyWith(size: v),
            ),
            slider(
              l10n.textSpacingLabel,
              text.letterSpacing,
              -0.05,
              0.3,
              (v) => text.copyWith(letterSpacing: v),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.palette_outlined,
          title: l10n.textSectionColor,
          trailing: dot(text.color),
          children: [
            _Swatches(
              selected: text.color,
              onPick: (c) => _commit(id, text.copyWith(color: c)),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.border_style,
          title: l10n.textSectionOutline,
          summary: text.strokeWidth == 0 ? l10n.textNoneOption : null,
          trailing: text.strokeWidth == 0 ? null : dot(text.strokeColor),
          children: [
            OptionTile(
              title: l10n.textNoneOption,
              selected: text.strokeWidth == 0,
              onTap: () => _commit(id, text.copyWith(strokeWidth: 0)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Swatches(
              selected: text.strokeWidth == 0 ? null : text.strokeColor,
              onPick: (c) => _commit(
                id,
                text.copyWith(
                  strokeColor: c,
                  strokeWidth: text.strokeWidth == 0 ? 0.08 : null,
                ),
              ),
            ),
            slider(
              l10n.textThicknessLabel,
              text.strokeWidth,
              0,
              maxTextStroke,
              (v) => text.copyWith(strokeWidth: v),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.blur_on,
          title: l10n.textSectionShadow,
          summary: text.shadow == 0
              ? l10n.textNoneOption
              : '${(text.shadow * 100).round()}%',
          children: [
            slider(
              l10n.textStrengthLabel,
              text.shadow,
              0,
              1,
              (v) => text.copyWith(shadow: v),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.format_color_fill,
          title: l10n.textSectionBackground,
          summary: text.hasBackground ? null : l10n.textNoneOption,
          trailing: text.hasBackground ? dot(text.background) : null,
          children: [
            OptionTile(
              title: l10n.textNoneOption,
              selected: !text.hasBackground,
              onTap: () => _commit(id, text.copyWith(background: 0)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Swatches(
              selected: text.hasBackground ? text.background : null,
              alpha: _backgroundAlpha,
              onPick: (c) => _commit(id, text.copyWith(background: c)),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.animation,
          title: l10n.textSectionMotion,
          summary: _animationLabel(l10n, text.animation),
          children: [
            for (final animation in ClipTextAnimation.values)
              OptionTile(
                title: _animationLabel(l10n, animation),
                selected: text.animation == animation,
                onTap: () => _commit(id, text.copyWith(animation: animation)),
              ),
          ],
        ),
      ],
    );
  }

  static String _animationLabel(
    AppLocalizations l10n,
    ClipTextAnimation animation,
  ) =>
      switch (animation) {
        ClipTextAnimation.none => l10n.textNoneOption,
        ClipTextAnimation.fade => l10n.textAnimationFade,
        ClipTextAnimation.pop => l10n.textAnimationPop,
        ClipTextAnimation.slideUp => l10n.textAnimationSlide,
      };
}

/// What the panel shows while no text is selected: a button to add one.
class _AddPrompt extends StatelessWidget {
  const _AddPrompt({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.textAddHint,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.text_fields),
          label: Text(l10n.textAddAction),
        ),
      ],
    );
  }
}

/// A grid of colour swatches; the one in use is ringed.
class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.selected,
    required this.onPick,
    this.alpha = 0xFF,
  });

  /// The colour in use (`0xAARRGGBB`), compared by its RGB; null when none.
  final int? selected;

  /// Called with the colour picked, at [alpha].
  final ValueChanged<int> onPick;

  /// Opacity the swatches pick with.
  final int alpha;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final value in _palette)
          Semantics(
            button: true,
            selected: _isSelected(value),
            label: l10n.textColorSemantics(
              '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            ),
            child: InkResponse(
              radius: 28,
              onTap: () => onPick((alpha << 24) | (value & 0xFFFFFF)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isSelected(value)
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: _isSelected(value) ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isSelected(int value) =>
      selected != null && (selected! & 0xFFFFFF) == (value & 0xFFFFFF);
}
