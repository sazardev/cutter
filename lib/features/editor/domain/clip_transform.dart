// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// How a picture is sized to the canvas before its own scale applies.
enum ClipFit {
  /// The whole picture is visible; bars fill the rest.
  fit,

  /// The picture covers the whole canvas; its edges may be cut.
  fill,
}

/// Smallest scale a picture may have.
const minClipScale = 0.05;

/// Largest scale a picture may have.
const maxClipScale = 10.0;

/// Where and how a picture sits on the canvas. Positions are fractions of
/// the canvas size measured from its centre, so a transform keeps its look
/// when the canvas shape changes.
class ClipTransform {
  /// Creates a transform; the defaults leave the picture fitted and
  /// centred.
  const ClipTransform({
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.flipX = false,
    this.fit = ClipFit.fit,
  });

  /// Horizontal offset of the picture's centre, as a fraction of the canvas
  /// width; positive is right.
  final double x;

  /// Vertical offset of the picture's centre, as a fraction of the canvas
  /// height; positive is down.
  final double y;

  /// Scale on top of [fit]; 1 is the fitted size.
  final double scale;

  /// Clockwise rotation in degrees.
  final double rotation;

  /// Opacity from 0 (invisible) to 1.
  final double opacity;

  /// Whether the picture is mirrored left to right.
  final bool flipX;

  /// How the picture is sized to the canvas.
  final ClipFit fit;

  /// True when the transform changes nothing.
  bool get isIdentity => this == const ClipTransform();

  /// True when every value is in its allowed range.
  bool get isValid =>
      x.isFinite &&
      y.isFinite &&
      rotation.isFinite &&
      scale >= minClipScale &&
      scale <= maxClipScale &&
      opacity >= 0 &&
      opacity <= 1;

  /// Returns a copy with the given fields replaced.
  ClipTransform copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    double? opacity,
    bool? flipX,
    ClipFit? fit,
  }) {
    return ClipTransform(
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      flipX: flipX ?? this.flipX,
      fit: fit ?? this.fit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipTransform &&
      other.x == x &&
      other.y == y &&
      other.scale == scale &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      other.flipX == flipX &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(x, y, scale, rotation, opacity, flipX, fit);

  @override
  String toString() => 'ClipTransform($x, $y, x$scale, $rotation°, '
      'opacity $opacity, flip $flipX, $fit)';
}
