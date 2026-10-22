// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// How the lines of a text sit against each other.
enum ClipTextAlign {
  /// Lines start at the same left edge.
  left,

  /// Lines are centred on each other.
  center,

  /// Lines end at the same right edge.
  right,
}

/// How a text comes in and goes out, over the first and last moments of its
/// clip.
enum ClipTextAnimation {
  /// It appears and disappears at once.
  none,

  /// It fades in and out.
  fade,

  /// It grows in with a little overshoot.
  pop,

  /// It rises into place while fading in.
  slideUp,
}

/// The ids of the fonts the engine draws, in the order the editor lists
/// them. The first is the default.
const clipTextFonts = [
  'sans',
  'serif',
  'mono',
  'anton',
  'bebas',
  'bangers',
  'lobster',
  'pacifico',
  'marker',
];

/// Smallest font size, as a fraction of the canvas height.
const minTextSize = 0.02;

/// Largest font size, as a fraction of the canvas height.
const maxTextSize = 0.5;

/// Longest outline, as a fraction of the font size.
const maxTextStroke = 0.25;

/// The canvas height, in pixels, a text is measured at: the width and height
/// stored with a text clip are in this reference space.
const textReferenceHeight = 1000;

/// How long a text clip lasts when it is first placed.
const defaultTextDurationMs = 3000;

/// The room a text clip's trim handles have in each direction. A text has no
/// source file, so its clip sits in the middle of a long imaginary one and
/// can be stretched as far as a still image.
const textSourceSpanMs = 20 * 60 * 1000;

/// The words of a text clip and how they look. Colours are `0xAARRGGBB`.
class ClipText {
  /// Creates a text; the defaults are white words with a soft shadow, which
  /// read on any picture.
  const ClipText({
    this.content = '',
    this.font = 'sans',
    this.size = 0.08,
    this.color = 0xFFFFFFFF,
    this.bold = true,
    this.italic = false,
    this.align = ClipTextAlign.center,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 0,
    this.shadow = 0.5,
    this.background = 0x00000000,
    this.letterSpacing = 0,
    this.animation = ClipTextAnimation.none,
  });

  /// The text stored by [toJson]; a missing field keeps its default, so a
  /// later version can add looks without breaking stored projects.
  factory ClipText.fromJson(Map<String, dynamic> json) {
    const defaults = ClipText();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return ClipText(
      content: json['content'] as String? ?? defaults.content,
      font: json['font'] as String? ?? defaults.font,
      size: (json['size'] as num?)?.toDouble() ?? defaults.size,
      color: json['color'] as int? ?? defaults.color,
      bold: json['bold'] as bool? ?? defaults.bold,
      italic: json['italic'] as bool? ?? defaults.italic,
      align: pick(ClipTextAlign.values, json['align'], defaults.align),
      strokeColor: json['strokeColor'] as int? ?? defaults.strokeColor,
      strokeWidth:
          (json['strokeWidth'] as num?)?.toDouble() ?? defaults.strokeWidth,
      shadow: (json['shadow'] as num?)?.toDouble() ?? defaults.shadow,
      background: json['background'] as int? ?? defaults.background,
      letterSpacing:
          (json['letterSpacing'] as num?)?.toDouble() ?? defaults.letterSpacing,
      animation: pick(
        ClipTextAnimation.values,
        json['animation'],
        defaults.animation,
      ),
    );
  }

  /// The words; a line break starts a new line.
  final String content;

  /// One of [clipTextFonts].
  final String font;

  /// Font size as a fraction of the canvas height.
  final double size;

  /// Colour of the letters.
  final int color;

  /// Whether the letters are heavy.
  final bool bold;

  /// Whether the letters lean.
  final bool italic;

  /// How the lines sit against each other.
  final ClipTextAlign align;

  /// Colour of the outline.
  final int strokeColor;

  /// Thickness of the outline as a fraction of the font size; 0 is none.
  final double strokeWidth;

  /// Strength of the shadow, 0 (none) to 1.
  final double shadow;

  /// Fill behind the words; an alpha of 0 is none.
  final int background;

  /// Extra space between letters, as a fraction of the font size.
  final double letterSpacing;

  /// How the text comes in and goes out.
  final ClipTextAnimation animation;

  /// True when there is something to draw.
  bool get hasWords => content.trim().isNotEmpty;

  /// True when a fill is drawn behind the words.
  bool get hasBackground => (background >> 24) & 0xFF != 0;

  /// True when every value is in its allowed range.
  bool get isValid =>
      clipTextFonts.contains(font) &&
      size >= minTextSize &&
      size <= maxTextSize &&
      strokeWidth >= 0 &&
      strokeWidth <= maxTextStroke &&
      shadow >= 0 &&
      shadow <= 1 &&
      letterSpacing.isFinite;

  /// Returns a copy with the given fields replaced.
  ClipText copyWith({
    String? content,
    String? font,
    double? size,
    int? color,
    bool? bold,
    bool? italic,
    ClipTextAlign? align,
    int? strokeColor,
    double? strokeWidth,
    double? shadow,
    int? background,
    double? letterSpacing,
    ClipTextAnimation? animation,
  }) {
    return ClipText(
      content: content ?? this.content,
      font: font ?? this.font,
      size: size ?? this.size,
      color: color ?? this.color,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      align: align ?? this.align,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadow: shadow ?? this.shadow,
      background: background ?? this.background,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      animation: animation ?? this.animation,
    );
  }

  /// The text as a JSON-ready map, for storage.
  Map<String, Object?> toJson() => {
        'content': content,
        'font': font,
        'size': size,
        'color': color,
        'bold': bold,
        'italic': italic,
        'align': align.name,
        'strokeColor': strokeColor,
        'strokeWidth': strokeWidth,
        'shadow': shadow,
        'background': background,
        'letterSpacing': letterSpacing,
        'animation': animation.name,
      };

  @override
  bool operator ==(Object other) =>
      other is ClipText &&
      other.content == content &&
      other.font == font &&
      other.size == size &&
      other.color == color &&
      other.bold == bold &&
      other.italic == italic &&
      other.align == align &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth &&
      other.shadow == shadow &&
      other.background == background &&
      other.letterSpacing == letterSpacing &&
      other.animation == animation;

  @override
  int get hashCode => Object.hash(
        content,
        font,
        size,
        color,
        bold,
        italic,
        align,
        strokeColor,
        strokeWidth,
        shadow,
        background,
        letterSpacing,
        animation,
      );

  @override
  String toString() => 'ClipText("$content", $font, size $size)';
}
