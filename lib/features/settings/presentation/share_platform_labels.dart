import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The name of [platform].
String sharePlatformLabel(AppLocalizations l10n, SharePlatform platform) {
  return switch (platform) {
    SharePlatform.whatsapp => l10n.sharePlatformWhatsapp,
    SharePlatform.instagram => l10n.sharePlatformInstagram,
    SharePlatform.tiktok => l10n.sharePlatformTiktok,
    SharePlatform.youtube => l10n.sharePlatformYoutube,
    SharePlatform.facebook => l10n.sharePlatformFacebook,
    SharePlatform.telegram => l10n.sharePlatformTelegram,
    SharePlatform.x => l10n.sharePlatformX,
    SharePlatform.snapchat => l10n.sharePlatformSnapchat,
  };
}

/// A stand-in icon for [platform]: the icon set has no brand logos.
IconData sharePlatformIcon(SharePlatform platform) {
  return switch (platform) {
    SharePlatform.whatsapp => Icons.chat_bubble_outline,
    SharePlatform.instagram => Icons.photo_camera_outlined,
    SharePlatform.tiktok => Icons.music_video_outlined,
    SharePlatform.youtube => Icons.smart_display_outlined,
    SharePlatform.facebook => Icons.groups_outlined,
    SharePlatform.telegram => Icons.send_outlined,
    SharePlatform.x => Icons.tag,
    SharePlatform.snapchat => Icons.camera_alt_outlined,
  };
}
