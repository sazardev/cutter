import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/features/editor/presentation/clip_inspector_sheet.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/filters_sheet.dart';
import 'package:cutter/features/editor/presentation/media_picker_page.dart';
import 'package:cutter/features/editor/presentation/presets_sheet.dart';
import 'package:cutter/features/editor/presentation/record_sheet.dart';
import 'package:cutter/features/editor/presentation/templates_page.dart';
import 'package:cutter/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:cutter/features/editor/presentation/widgets/preview_canvas.dart';
import 'package:cutter/features/editor/presentation/widgets/timeline_view.dart';
import 'package:cutter/features/editor/presentation/widgets/transport_bar.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Width of the side toolbar on medium and larger windows.
const double _sideToolbarWidth = 96;

/// The Editor screen: preview, transport, timeline and toolbar.
class EditorPage extends StatefulWidget {
  /// Creates the editor screen.
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  late final EditorController _controller;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(sampleProject());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (_controller.isPlaying) _controller.tick(delta.inMilliseconds);
  }

  String? _messageFor(AppLocalizations l10n, EditorOutcome outcome) {
    switch (outcome) {
      case EditorOutcome.ok:
        return null;
      case EditorOutcome.noClipSelected:
        return l10n.outcomeNoClipSelected;
      case EditorOutcome.playheadOutsideClip:
        return l10n.outcomePlayheadOutsideClip;
      case EditorOutcome.zeroDuration:
        return l10n.outcomeZeroDuration;
      case EditorOutcome.overlap:
        return l10n.outcomeOverlap;
      case EditorOutcome.wrongLayerKind:
        return l10n.outcomeWrongLayerKind;
      case EditorOutcome.unsupportedMedia:
        return l10n.outcomeUnsupportedMedia;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onOutcome(EditorOutcome outcome) {
    final message = _messageFor(AppLocalizations.of(context), outcome);
    if (message != null) _showMessage(message);
  }

  void _split() {
    final outcome = _controller.split();
    if (outcome == EditorOutcome.ok) {
      _showMessage(AppLocalizations.of(context).outcomeSplitDone);
      return;
    }
    _onOutcome(outcome);
  }

  void _reverse() => _onOutcome(_controller.toggleReverse());

  Future<void> _addMedia() async {
    final asset = await Navigator.of(context).push<SampleAsset>(
      MaterialPageRoute<SampleAsset>(
        builder: (BuildContext context) => const MediaPickerPage(),
      ),
    );
    if (asset == null || !mounted) return;
    _onOutcome(_controller.addClipFromAsset(asset));
  }

  Future<void> _openTemplates() async {
    final project = await Navigator.of(context).push<SampleProject>(
      MaterialPageRoute<SampleProject>(
        builder: (BuildContext context) => const TemplatesPage(),
      ),
    );
    if (project == null || !mounted) return;
    _controller.loadProject(project);
  }

  EditorToolbar _toolbar(WindowClass windowClass) {
    return EditorToolbar(
      controller: _controller,
      windowClass: windowClass,
      onSplit: _split,
      onReverse: _reverse,
      onAddMedia: _addMedia,
      onRecord: () => showRecordSheet(context, _controller),
      onInspector: () => showClipInspector(context, _controller),
      onFilters: () => showFiltersSheet(context, _controller),
      onPresets: () => showPresetsSheet(context, _controller),
      onTemplates: _openTemplates,
    );
  }

  Widget _preview() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PreviewCanvas(
        project: _controller.project,
        playheadMs: _controller.playheadMs,
      ),
    );
  }

  Widget _timeline() {
    return TimelineView(controller: _controller, onOutcome: _onOutcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editorTitle)),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = windowClassOf(constraints.maxWidth);
            final margin = marginFor(windowClass);
            if (windowClass == WindowClass.compact) {
              return _compact(margin, windowClass);
            }
            return _wide(margin, windowClass);
          },
        ),
      ),
    );
  }

  Widget _compact(double margin, WindowClass windowClass) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: margin,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                _preview(),
                const SizedBox(height: AppSpacing.sm),
                TransportBar(controller: _controller),
                const SizedBox(height: AppSpacing.sm),
                _timeline(),
              ],
            ),
          ),
        ),
        _toolbar(windowClass),
      ],
    );
  }

  Widget _wide(double margin, WindowClass windowClass) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: margin,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(child: Center(child: _preview())),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: _sideToolbarWidth,
                  child: _toolbar(windowClass),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          child: TransportBar(controller: _controller),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            AppSpacing.sm,
            margin,
            AppSpacing.lg,
          ),
          child: _timeline(),
        ),
      ],
    );
  }
}
