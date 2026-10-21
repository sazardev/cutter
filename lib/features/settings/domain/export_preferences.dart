import 'package:flutter/foundation.dart' show immutable;

/// Where and how finished videos are saved.
@immutable
class ExportPreferences {
  /// Creates the preferences; the defaults save to the default folder and,
  /// on phones, to the gallery.
  const ExportPreferences({this.directory, this.saveToGallery = true});

  /// A folder the user picked, or null for the default one.
  final String? directory;

  /// Whether finished videos are also copied to the device gallery.
  final bool saveToGallery;

  /// A copy with the given fields replaced; [clearDirectory] goes back to the
  /// default folder.
  ExportPreferences copyWith({
    String? directory,
    bool clearDirectory = false,
    bool? saveToGallery,
  }) {
    return ExportPreferences(
      directory: clearDirectory ? null : directory ?? this.directory,
      saveToGallery: saveToGallery ?? this.saveToGallery,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExportPreferences &&
      other.directory == directory &&
      other.saveToGallery == saveToGallery;

  @override
  int get hashCode => Object.hash(directory, saveToGallery);
}
