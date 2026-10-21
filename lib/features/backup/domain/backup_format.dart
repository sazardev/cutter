import 'dart:convert';

/// First bytes of every backup file.
const String backupMagic = 'CUTTERBK';

/// Version of the backup layout; a reader refuses a newer one.
const int backupFormat = 1;

/// File extension of a backup.
const String backupExtension = 'cutter';

/// Why a backup could not be made or read.
enum BackupFailure {
  /// The file is not a Cutter backup.
  notABackup,

  /// The backup was made by a newer version of Cutter.
  newerVersion,

  /// The file ends before its content does, or its pieces do not add up.
  damaged,

  /// The device has no room to write or unpack the file.
  storageFull,

  /// Any other problem reading or writing a file.
  io,
}

/// A backup could not be made or read.
class BackupException implements Exception {
  /// Creates the error.
  const BackupException(this.failure);

  /// Why it failed.
  final BackupFailure failure;

  @override
  String toString() => 'BackupException(${failure.name})';
}

/// One media file inside a backup: where the project had it, a readable
/// name, and its length in bytes.
class BackupEntry {
  /// Creates an entry.
  const BackupEntry({
    required this.uri,
    required this.name,
    required this.size,
  });

  /// Reads an entry from its JSON form.
  factory BackupEntry.fromJson(Map<String, Object?> json) => BackupEntry(
        uri: json['uri']! as String,
        name: json['name']! as String,
        size: json['size']! as int,
      );

  /// The source URI the project's clips use for this file.
  final String uri;

  /// The file name, kept so the restored copy is recognizable.
  final String name;

  /// The length of the file in bytes.
  final int size;

  /// The JSON form of the entry.
  Map<String, Object?> toJson() => {'uri': uri, 'name': name, 'size': size};
}

/// The table of contents of a backup: the project and the media that follow
/// it, in order.
class BackupManifest {
  /// Creates a manifest.
  const BackupManifest({
    required this.createdAtMs,
    required this.projectJson,
    required this.entries,
    this.format = backupFormat,
  });

  /// Reads a manifest from its encoded form.
  factory BackupManifest.decode(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return BackupManifest(
      format: json['format']! as int,
      createdAtMs: json['createdAtMs']! as int,
      projectJson: json['project']! as String,
      entries: [
        for (final raw in json['media']! as List<dynamic>)
          BackupEntry.fromJson((raw as Map).cast<String, Object?>()),
      ],
    );
  }

  /// The backup layout version.
  final int format;

  /// When the backup was made, in milliseconds since the epoch.
  final int createdAtMs;

  /// The project, as a snapshot.
  final String projectJson;

  /// The media files that follow the manifest, in this order.
  final List<BackupEntry> entries;

  /// The bytes of all the media together.
  int get mediaBytes => entries.fold(0, (sum, entry) => sum + entry.size);

  /// The encoded form of the manifest.
  String encode() => jsonEncode({
        'format': format,
        'createdAtMs': createdAtMs,
        'project': projectJson,
        'media': [for (final entry in entries) entry.toJson()],
      });
}
