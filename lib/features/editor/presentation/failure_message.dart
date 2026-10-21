import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/l10n/app_localizations.dart';

/// The single place that turns an [EditorFailure] into user-facing text.
///
/// The switch is exhaustive on purpose: adding a failure to the domain
/// without a message here is a compile error, not a silent generic message.
String failureMessage(AppLocalizations l10n, EditorFailure failure) {
  return switch (failure) {
    PlayheadOutsideClip() => l10n.failureSplitOutsideClip,
    ZeroDuration() || TrimOutOfSource() => l10n.failureInvalidTrim,
    Overlap() => l10n.failureOverlap,
    NotReversible() => l10n.failureNotReversible,
    InvalidVolume() => l10n.failureInvalidVolume,
    UnknownAdjustment() ||
    AdjustmentOutOfRange() =>
      l10n.failureInvalidAdjustment,
    IncompatibleClip() => l10n.failureFilterNotSupported,
    ClipNotFound() => l10n.failureClipNotFound,
    ProjectNotFound() ||
    LayerNotFound() ||
    NegativeStart() ||
    WrongLayerKind() ||
    UnsupportedMedia() ||
    InvalidLayerOrder() ||
    EmptyName() ||
    PresetNotFound() ||
    TemplateNotFound() ||
    MissingTemplateMedia() =>
      l10n.failureGeneric,
  };
}
