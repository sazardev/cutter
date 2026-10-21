import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/l10n/app_localizations.dart';

/// The single place that turns an [EditorFailure] into user-facing text.
String failureMessage(AppLocalizations l10n, EditorFailure failure) {
  if (failure is SplitOutsideClip) return l10n.failureSplitOutsideClip;
  if (failure is InvalidTrim) return l10n.failureInvalidTrim;
  if (failure is Overlap) return l10n.failureOverlap;
  if (failure is NotReversible) return l10n.failureNotReversible;
  if (failure is InvalidVolume) return l10n.failureInvalidVolume;
  if (failure is InvalidAdjustment) return l10n.failureInvalidAdjustment;
  if (failure is FilterNotSupported) return l10n.failureFilterNotSupported;
  if (failure is ClipNotFound) return l10n.failureClipNotFound;
  return l10n.failureGeneric;
}
