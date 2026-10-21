// All fields are final, so the classes are immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Where a pack's music comes from and under which terms it may be used.
class MusicSource {
  /// Creates the source.
  const MusicSource({
    required this.name,
    required this.license,
    this.url,
    this.licenseUrl,
    this.attribution,
  });

  /// Reads a source from the catalog's JSON.
  factory MusicSource.fromJson(Map<String, Object?> json) => MusicSource(
        name: json['name']! as String,
        license: json['license']! as String,
        url: json['url'] as String?,
        licenseUrl: json['licenseUrl'] as String?,
        attribution: json['attribution'] as String?,
      );

  /// Display name of the source.
  final String name;

  /// The licence as an SPDX id (`CC0-1.0`, `CC-BY-4.0`).
  final String license;

  /// Home page of the source.
  final String? url;

  /// The licence text.
  final String? licenseUrl;

  /// The credit the licence asks for; null when it asks for none.
  final String? attribution;

  /// Whether the licence asks the app to credit the author.
  bool get needsCredit => license.startsWith('CC-BY');

  /// The JSON form, as stored in a pack's `pack.json`.
  Map<String, Object?> toJson() => {
        'name': name,
        'license': license,
        'url': url,
        'licenseUrl': licenseUrl,
        'attribution': attribution,
      };
}

/// One sound file of a pack, relative to the pack's folder.
class MusicTrack {
  /// Creates the track.
  const MusicTrack({
    required this.file,
    required this.title,
    this.artist,
    this.durationMs = 0,
    this.bpm,
    this.mood,
  });

  /// Reads a track from a pack's JSON.
  factory MusicTrack.fromJson(Map<String, Object?> json) => MusicTrack(
        file: json['file']! as String,
        title: json['title']! as String,
        artist: json['artist'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        bpm: (json['bpm'] as num?)?.toInt(),
        mood: json['mood'] as String?,
      );

  /// Path of the file inside the pack's folder.
  final String file;

  /// Title shown in the list.
  final String title;

  /// Author, when known.
  final String? artist;

  /// Length, 0 when unknown.
  final int durationMs;

  /// Tempo, when known.
  final int? bpm;

  /// What the track feels like (`epic`, `calm`), when known.
  final String? mood;

  /// The JSON form.
  Map<String, Object?> toJson() => {
        'file': file,
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
        'bpm': bpm,
        'mood': mood,
      };
}

/// A downloadable group of tracks of one genre, as the catalog lists it.
class MusicPack {
  /// Creates the pack.
  const MusicPack({
    required this.id,
    required this.names,
    required this.genre,
    required this.source,
    required this.url,
    required this.bytes,
    required this.trackCount,
  });

  /// Reads a pack from the catalog's JSON.
  factory MusicPack.fromJson(Map<String, Object?> json) => MusicPack(
        id: json['id']! as String,
        names: (json['names']! as Map<String, Object?>).cast<String, String>(),
        genre: json['genre']! as String,
        source: MusicSource.fromJson(
          (json['source']! as Map).cast<String, Object?>(),
        ),
        url: json['url']! as String,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      );

  /// Stable id, also the name of the folder the pack installs into.
  final String id;

  /// The pack's name by language code; `en` is always present.
  final Map<String, String> names;

  /// The genre, which picks the pack's icon.
  final String genre;

  /// Where the music comes from.
  final MusicSource source;

  /// Where the zip is.
  final String url;

  /// Size of the zip, 0 when unknown.
  final int bytes;

  /// How many tracks the zip holds.
  final int trackCount;

  /// The name in [languageCode], or in English.
  String nameIn(String languageCode) => names[languageCode] ?? names['en']!;

  /// The JSON form.
  Map<String, Object?> toJson() => {
        'id': id,
        'names': names,
        'genre': genre,
        'source': source.toJson(),
        'url': url,
        'bytes': bytes,
        'trackCount': trackCount,
      };
}

/// A pack that is on the device, with the folder its files are in.
class InstalledPack {
  /// Creates the installed pack.
  const InstalledPack({
    required this.pack,
    required this.directory,
    required this.tracks,
    this.sizeBytes = 0,
  });

  /// What the catalog said about it when it was installed.
  final MusicPack pack;

  /// The folder holding the tracks.
  final String directory;

  /// The tracks, in the order of the pack.
  final List<MusicTrack> tracks;

  /// What the pack takes on disk.
  final int sizeBytes;

  /// Absolute path of [track].
  String pathOf(MusicTrack track) => '$directory/${track.file}';
}
