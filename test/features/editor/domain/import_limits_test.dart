import 'package:cutter/features/editor/domain/import_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<ImportNoticeKind> notices({
    int width = 1920,
    int height = 1080,
    int durationMs = 60000,
    int sizeBytes = 100 * 1024 * 1024,
  }) =>
      noticesFor(
        width: width,
        height: height,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
      );

  test('an ordinary file raises no notice', () {
    expect(notices(), isEmpty);
    // 4K itself is fine.
    expect(notices(width: 3840, height: 2160), isEmpty);
  });

  test('big files are warned about, never refused', () {
    expect(
      notices(width: 7680, height: 4320),
      [ImportNoticeKind.highResolution],
    );
    expect(
      notices(durationMs: warnDurationMs + 1),
      [ImportNoticeKind.longDuration],
    );
    expect(
      notices(sizeBytes: warnSizeBytes + 1),
      [ImportNoticeKind.largeFile],
    );
    expect(
      notices(
        width: 7680,
        height: 4320,
        durationMs: 2 * warnDurationMs,
        sizeBytes: 2 * warnSizeBytes,
      ),
      hasLength(3),
    );
  });
}
