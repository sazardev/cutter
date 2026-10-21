// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// The least of the source a crop may keep on each axis.
const minCropKeep = 0.05;

/// The part of the source picture that is kept, as fractions cut from each
/// edge of the source (0 keeps the edge, 0.25 cuts a quarter).
class ClipCrop {
  /// Creates a crop; the defaults keep the whole picture.
  const ClipCrop({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// The centred crop with width over height [aspect] of a [sourceWidth] x
  /// [sourceHeight] picture: the largest such rectangle that fits.
  factory ClipCrop.centred(double aspect, int sourceWidth, int sourceHeight) {
    if (sourceWidth <= 0 || sourceHeight <= 0) return const ClipCrop();
    final source = sourceWidth / sourceHeight;
    if (aspect > source) {
      final keep = source / aspect;
      return ClipCrop(top: (1 - keep) / 2, bottom: (1 - keep) / 2);
    }
    final keep = aspect / source;
    return ClipCrop(left: (1 - keep) / 2, right: (1 - keep) / 2);
  }

  /// Fraction cut from the left edge.
  final double left;

  /// Fraction cut from the top edge.
  final double top;

  /// Fraction cut from the right edge.
  final double right;

  /// Fraction cut from the bottom edge.
  final double bottom;

  /// True when the whole picture is kept.
  bool get isNone => left == 0 && top == 0 && right == 0 && bottom == 0;

  /// The fraction of the source width kept.
  double get keptWidth => 1 - left - right;

  /// The fraction of the source height kept.
  double get keptHeight => 1 - top - bottom;

  /// True when every edge is in 0..1 and enough of the picture remains.
  bool get isValid =>
      [left, top, right, bottom].every((v) => v >= 0 && v < 1) &&
      keptWidth >= minCropKeep &&
      keptHeight >= minCropKeep;

  @override
  bool operator ==(Object other) =>
      other is ClipCrop &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'ClipCrop($left, $top, $right, $bottom)';
}
