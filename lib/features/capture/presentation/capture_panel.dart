import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:cutter/features/capture/presentation/capture_providers.dart';
import 'package:cutter/features/capture/presentation/voice_controller.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/settings/presentation/permission_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the timeline plays while a voice is recorded, so the voice-over
/// can follow the picture. On by default.
final playAlongProvider = StateProvider<bool>((ref) => true);

/// Takes photos, records video with the system camera and records voice,
/// and adds each result to the project as it is made: photos and videos at
/// the end of the picture sequence, voice at the playhead where recording
/// began.
class CapturePanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const CapturePanel({super.key});

  @override
  ConsumerState<CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<CapturePanel>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLost());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A recording cut short by the app leaving the front is kept, never
    // thrown away.
    if (state == AppLifecycleState.paused &&
        ref.read(voiceControllerProvider).phase == VoicePhase.recording) {
      _finishVoice(interrupted: true);
    }
  }

  Future<void> _recoverLost() async {
    final path = await ref.read(cameraCaptureProvider).lostCapture();
    if (path == null || !mounted) return;
    final outcome = await importPaths(context, ref, [path]);
    if (outcome.imported > 0 && mounted) {
      await _tell(AppLocalizations.of(context)!.captureRecovered);
    }
  }

  Future<void> _tell(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.importReportClose),
          ),
        ],
      ),
    );
  }

  Future<void> _useCamera(bool video) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final camera = ref.read(cameraCaptureProvider);
    try {
      final path = await (video ? camera.video() : camera.photo());
      if (path != null && mounted) await importPaths(context, ref, [path]);
    } on CameraDenied {
      if (mounted) {
        await _denied(
          l10n.captureCameraDeniedTitle,
          l10n.captureCameraDeniedBody,
        );
      }
    } on Object {
      if (mounted) await _tell(l10n.captureFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _denied(String title, String body) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(openSystemSettingsProvider)();
            },
            child: Text(l10n.settingsPermissionsOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _startVoice() async {
    if (_busy) return;
    final playback = ref.read(playbackControllerProvider.notifier);
    final playhead = ref.read(playbackControllerProvider).positionMs;
    final started = await ref.read(voiceControllerProvider.notifier).start(
          playhead,
        );
    if (!started) return;
    if (ref.read(playAlongProvider)) playback.play();
  }

  Future<void> _finishVoice({bool interrupted = false}) async {
    ref.read(playbackControllerProvider.notifier).pause();
    final take = await ref
        .read(voiceControllerProvider.notifier)
        .stop(interrupted: interrupted);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (take == null) {
      await _tell(l10n.captureFailed);
      return;
    }
    await importPaths(context, ref, [take.path], atMs: take.atMs);
    if (take.interrupted && mounted) await _tell(l10n.captureInterrupted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final recording = voice.phase == VoicePhase.recording;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busy || recording ? null : () => _useCamera(false),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.capturePhoto),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busy || recording ? null : () => _useCamera(true),
                icon: const Icon(Icons.videocam_outlined),
                label: Text(l10n.captureVideo),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (recording) ...[
          Row(
            children: [
              Icon(Icons.fiber_manual_record, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.captureVoiceRecording(
                      formatTimecode(voice.elapsedMs, tenths: true),
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _finishVoice,
                icon: const Icon(Icons.stop),
                label: Text(l10n.captureVoiceStop),
              ),
            ],
          ),
        ] else ...[
          if (voice.phase == VoicePhase.denied)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.captureMicDeniedTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.captureMicDeniedBody,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => ref.read(openSystemSettingsProvider)(),
                        child: Text(l10n.settingsPermissionsOpenSettings),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _startVoice,
            icon: const Icon(Icons.mic_none),
            label: Text(l10n.captureVoice),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.captureVoiceHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.capturePlayAlong),
            value: ref.watch(playAlongProvider),
            onChanged: (value) =>
                ref.read(playAlongProvider.notifier).state = value,
          ),
        ],
      ],
    );
  }
}
