import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Sends the video at a path to the system share sheet, with a title.
/// Tests replace it.
typedef VideoSharer = Future<void> Function(String path, String title);

/// The system share sheet.
final videoSharerProvider = Provider<VideoSharer>(
  (ref) => (path, title) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        title: title,
        subject: title,
      ),
    );
  },
);

/// Whether the platform can share a file: phones and the Windows and macOS
/// desktops can; on Linux the plugin only shares text, so the share options
/// are left out there. Tests replace it.
final shareSupportedProvider = Provider<bool>(
  (ref) => !Platform.isLinux,
);

/// Shows a folder in the file manager of the desktop; tests replace it.
typedef FolderOpener = Future<void> Function(String directory);

/// Opens folders with the desktop's file manager, or does nothing on phones.
final folderOpenerProvider = Provider<FolderOpener>(
  (ref) => (directory) async {
    final command = switch (Platform.operatingSystem) {
      'linux' => 'xdg-open',
      'macos' => 'open',
      'windows' => 'explorer',
      _ => null,
    };
    if (command == null) return;
    await Process.start(command, [directory], mode: ProcessStartMode.detached);
  },
);

/// Whether the app can show a folder in a file manager: desktops only.
final folderOpeningSupportedProvider = Provider<bool>(
  (ref) => Platform.isLinux || Platform.isMacOS || Platform.isWindows,
);
