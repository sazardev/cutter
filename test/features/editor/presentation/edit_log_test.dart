import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/presentation/edit_log.dart';
import 'package:flutter_test/flutter_test.dart';

class _Breadcrumbs extends NoopTelemetry {
  _Breadcrumbs();

  final lines = <String>[];

  @override
  void log(String message) => lines.add(message);
}

void main() {
  test('every edit is left as a breadcrumb with its outcome', () {
    final telemetry = _Breadcrumbs();
    EditLog(telemetry: telemetry)
      ..record('split', 4, const Ok<Object?>(1))
      ..record('trim', 2, const Err<Object?>(ClipNotFound('c1')));

    expect(telemetry.lines, hasLength(2));
    expect(
      telemetry.lines[0],
      matches(r'^edit \d\d:\d\d:\d\d\.\d{3} split 4ms ok$'),
    );
    expect(telemetry.lines[1], contains('trim 2ms rejected'));
  });
}
