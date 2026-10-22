// All fields are final, so the classes are immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// The thinnest and the thickest stroke, as a fraction of the short side of
/// the canvas.
const minStrokeWidth = 0.004;

/// See [minStrokeWidth].
const maxStrokeWidth = 0.08;

/// One line drawn with a finger: a colour, a thickness and the points it
/// went through. Points are fractions of the canvas, 0 to 1 across and
/// down, so a drawing keeps its shape on any canvas size.
class DrawingStroke {
  /// Creates a stroke. [points] holds x and y one after the other.
  const DrawingStroke({
    required this.color,
    required this.width,
    required this.points,
    this.erase = false,
  });

  /// Reads a stroke written by [toJson].
  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
        color: json['color'] as int,
        width: (json['width'] as num).toDouble(),
        erase: json['erase'] as bool? ?? false,
        points: [
          for (final v in json['points'] as List<dynamic>)
            (v as num).toDouble(),
        ],
      );

  /// The colour as `0xAARRGGBB`; unused by an eraser.
  final int color;

  /// Thickness as a fraction of the short side of the canvas.
  final double width;

  /// Whether the stroke rubs out what is under it instead of painting.
  final bool erase;

  /// x0, y0, x1, y1, ... as fractions of the canvas.
  final List<double> points;

  /// The number of points.
  int get length => points.length ~/ 2;

  /// Writes the stroke as JSON.
  Map<String, Object?> toJson() => {
        'color': color,
        'width': width,
        'erase': erase,
        'points': points,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawingStroke &&
          other.color == color &&
          other.width == width &&
          other.erase == erase &&
          _same(other.points, points);

  @override
  int get hashCode => Object.hash(color, width, erase, Object.hashAll(points));
}

/// What was drawn over a clip: strokes in the order they were made.
class ClipDrawing {
  /// Creates a drawing from [strokes].
  const ClipDrawing(this.strokes);

  /// Reads a drawing written by [toJson].
  factory ClipDrawing.fromJson(Map<String, dynamic> json) => ClipDrawing([
        for (final s in json['strokes'] as List<dynamic>)
          DrawingStroke.fromJson(s as Map<String, dynamic>),
      ]);

  /// No strokes.
  static const empty = ClipDrawing([]);

  /// The strokes, first made first.
  final List<DrawingStroke> strokes;

  /// Whether nothing is drawn: no strokes, or only erasers.
  bool get isBlank => strokes.every((s) => s.erase);

  /// This drawing with [stroke] on top.
  ClipDrawing plus(DrawingStroke stroke) => ClipDrawing([...strokes, stroke]);

  /// This drawing without its last stroke.
  ClipDrawing withoutLast() => strokes.isEmpty
      ? this
      : ClipDrawing(strokes.sublist(0, strokes.length - 1));

  /// Writes the drawing as JSON.
  Map<String, Object?> toJson() => {
        'strokes': [for (final s in strokes) s.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipDrawing && _sameStrokes(other.strokes, strokes);

  @override
  int get hashCode => Object.hashAll(strokes);
}

bool _same(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameStrokes(List<DrawingStroke> a, List<DrawingStroke> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
