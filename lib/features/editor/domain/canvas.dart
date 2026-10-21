// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// The frame a project renders to: its size in pixels and frame rate.
class Canvas {
  /// Creates a canvas.
  const Canvas({required this.width, required this.height, this.fps = 30});

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Frames per second.
  final int fps;

  /// Width over height.
  double get aspectRatio => width / height;

  /// The preset with this size, or null for a custom size.
  CanvasPreset? get preset {
    for (final preset in CanvasPreset.values) {
      if (preset.width == width && preset.height == height) return preset;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  Canvas copyWith({int? width, int? height, int? fps}) => Canvas(
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
      );

  @override
  bool operator ==(Object other) =>
      other is Canvas &&
      other.width == width &&
      other.height == height &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(width, height, fps);

  @override
  String toString() => 'Canvas(${width}x$height@$fps)';
}

/// The canvas shapes offered in the editor, at 1080 pixels on the short
/// side.
enum CanvasPreset {
  /// Vertical 9:16: stories, reels, shorts.
  portrait(1080, 1920),

  /// Horizontal 16:9: video platforms, TV.
  landscape(1920, 1080),

  /// Square 1:1: feeds.
  square(1080, 1080),

  /// Tall 4:5: feed posts.
  feed(1080, 1350);

  const CanvasPreset(this.width, this.height);

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// The canvas of this preset at [fps].
  Canvas canvas({int fps = 30}) =>
      Canvas(width: width, height: height, fps: fps);
}

/// The canvas a new project starts with.
const defaultCanvas = Canvas(width: 1080, height: 1920);
