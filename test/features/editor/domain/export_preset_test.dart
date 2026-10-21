import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/export_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vertical = Canvas(width: 1080, height: 1920);

  test('standard quality of the project canvas is 1080x1920', () {
    final plan = ExportPlan.of(
      vertical,
      ExportPlatform.project,
      ExportQuality.standard,
      30,
    );
    expect((plan.width, plan.height, plan.fps), (1080, 1920, 30));
    expect(plan.reframed, isFalse);
    expect(plan.encoderPreset, 'fast');
  });

  test('YouTube reframes a vertical project to widescreen', () {
    final plan = ExportPlan.of(
      vertical,
      ExportPlatform.widescreen,
      ExportQuality.ultra,
      60,
    );
    expect((plan.width, plan.height, plan.fps), (3840, 2160, 60));
    expect(plan.reframed, isTrue);
  });

  test('messaging caps the size and the frame rate', () {
    final plan = ExportPlan.of(
      vertical,
      ExportPlatform.messaging,
      ExportQuality.high,
      60,
    );
    expect((plan.width, plan.height, plan.fps), (720, 1280, 30));
    final standard = ExportPlan.of(
      vertical,
      ExportPlatform.project,
      ExportQuality.high,
      30,
    );
    expect(plan.videoBitrate, lessThan(standard.videoBitrate));
  });

  test('estimates the file size from the bitrates', () {
    final plan = ExportPlan.of(
      vertical,
      ExportPlatform.project,
      ExportQuality.draft,
      30,
    );
    final bytes = plan.estimatedBytes(10000);
    expect(bytes, ((plan.videoBitrate + plan.audioBitrate) * 10 / 8).round());
  });
}
