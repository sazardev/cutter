import 'package:flutter/foundation.dart' show immutable, setEquals;

/// The places a finished video is commonly published to. The share sheet of
/// the system does the sending; these are the shortcuts the user chose to
/// see next to the share button.
enum SharePlatform {
  /// WhatsApp.
  whatsapp,

  /// Instagram.
  instagram,

  /// TikTok.
  tiktok,

  /// YouTube.
  youtube,

  /// Facebook.
  facebook,

  /// Telegram.
  telegram,

  /// X.
  x,

  /// Snapchat.
  snapchat,
}

/// What shows once a video is exported, and what happens on its own.
@immutable
class SharePreferences {
  /// Creates the preferences; by default sharing is offered, the sheet does
  /// not open by itself, and the usual platforms and result actions show.
  const SharePreferences({
    this.showAfterExport = true,
    this.openSheetAutomatically = false,
    this.platforms = defaultPlatforms,
    this.showWatch = true,
    this.showOpenFolder = true,
    this.showCopyPath = true,
  });

  /// The platforms shown until the user changes them.
  static const Set<SharePlatform> defaultPlatforms = {
    SharePlatform.whatsapp,
    SharePlatform.instagram,
    SharePlatform.tiktok,
    SharePlatform.youtube,
    SharePlatform.facebook,
    SharePlatform.telegram,
  };

  /// Whether the share options appear when an export finishes.
  final bool showAfterExport;

  /// Whether the share sheet opens on its own when an export finishes.
  final bool openSheetAutomatically;

  /// The platform shortcuts shown next to the share button.
  final Set<SharePlatform> platforms;

  /// Whether "Watch" shows in the result of an export.
  final bool showWatch;

  /// Whether "Open folder" shows in the result of an export.
  final bool showOpenFolder;

  /// Whether "Copy path" shows in the result of an export.
  final bool showCopyPath;

  /// A copy with the given fields replaced.
  SharePreferences copyWith({
    bool? showAfterExport,
    bool? openSheetAutomatically,
    Set<SharePlatform>? platforms,
    bool? showWatch,
    bool? showOpenFolder,
    bool? showCopyPath,
  }) {
    return SharePreferences(
      showAfterExport: showAfterExport ?? this.showAfterExport,
      openSheetAutomatically:
          openSheetAutomatically ?? this.openSheetAutomatically,
      platforms: platforms ?? this.platforms,
      showWatch: showWatch ?? this.showWatch,
      showOpenFolder: showOpenFolder ?? this.showOpenFolder,
      showCopyPath: showCopyPath ?? this.showCopyPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SharePreferences &&
      other.showAfterExport == showAfterExport &&
      other.openSheetAutomatically == openSheetAutomatically &&
      setEquals(other.platforms, platforms) &&
      other.showWatch == showWatch &&
      other.showOpenFolder == showOpenFolder &&
      other.showCopyPath == showCopyPath;

  @override
  int get hashCode => Object.hash(
        showAfterExport,
        openSheetAutomatically,
        Object.hashAllUnordered(platforms),
        showWatch,
        showOpenFolder,
        showCopyPath,
      );
}
