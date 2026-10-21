import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/l10n/app_localizations.dart';

/// The words for a failed install.
String musicFailureMessage(AppLocalizations l10n, MusicFailure failure) =>
    switch (failure) {
      MusicFailure.network => l10n.musicFailureNetwork,
      MusicFailure.corrupt => l10n.musicFailureCorrupt,
      MusicFailure.storage => l10n.musicFailureStorage,
    };
