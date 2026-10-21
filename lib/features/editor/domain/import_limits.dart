/// Why a picked file could not be imported.
enum ImportIssueKind {
  /// The engine cannot read the file: an unknown format or a damaged file.
  unreadable,

  /// The file is too short to be a clip.
  tooShort,

  /// The device has no room to keep a copy of the file.
  storageFull,

  /// The copy into the app failed for another reason, or the file went
  /// missing while it was being read.
  copyFailed,
}

/// A file that was left out, and why.
class ImportIssue {
  /// Creates an issue for the file at [path].
  const ImportIssue(this.path, this.kind);

  /// The picked file.
  final String path;

  /// Why it was left out.
  final ImportIssueKind kind;
}

/// Something worth knowing about a file that was imported anyway.
enum ImportNoticeKind {
  /// More pixels than 4K: previews and exports may be slow.
  highResolution,

  /// Longer than an hour.
  longDuration,

  /// Bigger than 4 GB.
  largeFile,
}

/// A warning about an imported file.
class ImportNotice {
  /// Creates a notice for the file at [path].
  const ImportNotice(this.path, this.kind);

  /// The imported file.
  final String path;

  /// What to know about it.
  final ImportNoticeKind kind;
}

/// Pixels of a 4K frame (3840 x 2160); more than this is a high resolution.
const int warnPixelCount = 3840 * 2160;

/// Length above which a file is a long one: an hour.
const int warnDurationMs = 60 * 60 * 1000;

/// Size above which a file is a large one: 4 GiB.
const int warnSizeBytes = 4 * 1024 * 1024 * 1024;

/// The notices a file with these properties deserves. Nothing is refused
/// for being big: the user is told and decides.
List<ImportNoticeKind> noticesFor({
  required int width,
  required int height,
  required int durationMs,
  required int sizeBytes,
}) {
  return [
    if (width * height > warnPixelCount) ImportNoticeKind.highResolution,
    if (durationMs > warnDurationMs) ImportNoticeKind.longDuration,
    if (sizeBytes > warnSizeBytes) ImportNoticeKind.largeFile,
  ];
}
