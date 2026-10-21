import 'package:flutter/material.dart';

// The mark is drawn in the 512 unit space of assets/brand/logo_mark.svg:
// three staggered clips on three layers, cut by one diagonal.
const Rect _markBounds = Rect.fromLTWH(112, 144, 288, 224);
const double _barHeight = 56;
const double _cutWidth = 30;
const List<Rect> _bars = [
  Rect.fromLTWH(112, 144, 208, _barHeight),
  Rect.fromLTWH(176, 228, 224, _barHeight),
  Rect.fromLTWH(128, 312, 192, _barHeight),
];

/// The Cutter logo mark, painted with colour roles so it follows the theme.
///
/// It is meant to sit on a `primary` surface: the clips use `onPrimary`,
/// `primaryContainer` and `inversePrimary`, the same tones as the launcher
/// icon.
class BrandMark extends StatelessWidget {
  /// Creates the mark at [size] logical pixels wide.
  const BrandMark({this.size = 56, super.key});

  /// Width of the mark; its height keeps the 9:7 ratio of the artwork.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size * _markBounds.height / _markBounds.width),
        painter: _BrandMarkPainter([
          scheme.onPrimary,
          scheme.primaryContainer,
          scheme.inversePrimary,
        ]),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.colors);

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / _markBounds.width)
      ..translate(-_markBounds.left, -_markBounds.top)
      ..saveLayer(_markBounds.inflate(_cutWidth), Paint());
    for (var i = 0; i < _bars.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _bars[i],
          const Radius.circular(_barHeight / 2),
        ),
        Paint()..color = colors[i],
      );
    }
    canvas
      ..drawLine(
        const Offset(318, 112),
        const Offset(194, 400),
        Paint()
          ..blendMode = BlendMode.clear
          ..strokeWidth = _cutWidth,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
