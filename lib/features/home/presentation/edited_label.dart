import 'package:cutter/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Edited 5 min ago", "Edited 2 d ago" or the date once it is a week old.
String editedLabel(AppLocalizations l10n, int updatedAtMs, DateTime now) {
  final updated = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final age = now.difference(updated);
  if (age.inMinutes < 1) return l10n.projectEditedJustNow;
  if (age.inHours < 1) return l10n.projectEditedMinutes(age.inMinutes);
  if (age.inDays < 1) return l10n.projectEditedHours(age.inHours);
  if (age.inDays < 7) return l10n.projectEditedDays(age.inDays);
  return l10n.projectEditedOn(
    DateFormat.yMMMd(l10n.localeName).format(updated),
  );
}
