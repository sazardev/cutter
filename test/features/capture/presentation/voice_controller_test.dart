import 'dart:io';

import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:cutter/features/capture/presentation/capture_providers.dart';
import 'package:cutter/features/capture/presentation/voice_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRecorder implements VoiceRecorder {
  FakeRecorder({
    this.allowed = true,
    this.writes = 'audio',
    this.failStop = false,
  });

  final bool allowed;
  final String writes;
  final bool failStop;
  String? path;
  bool disposed = false;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> start(String path) async {
    this.path = path;
    File(path).writeAsStringSync(writes);
  }

  @override
  Future<String?> stop() async {
    if (failStop) throw StateError('stop failed');
    return path;
  }

  @override
  Future<bool> get isRecording async => path != null;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync('cutter_voice'));
  tearDown(() => sandbox.deleteSync(recursive: true));

  ProviderContainer containerWith(FakeRecorder recorder) {
    final container = ProviderContainer(
      overrides: [
        voiceRecorderFactoryProvider.overrideWithValue(() => recorder),
        voiceFilePathProvider
            .overrideWithValue(() async => '${sandbox.path}/voice.m4a'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('records and returns a take placed where the playhead was', () async {
    final recorder = FakeRecorder();
    final container = containerWith(recorder);
    final voice = container.read(voiceControllerProvider.notifier);

    expect(await voice.start(2500), isTrue);
    expect(container.read(voiceControllerProvider).phase, VoicePhase.recording);
    expect(container.read(voiceControllerProvider).startedAtMs, 2500);

    final take = await voice.stop();

    expect(take!.path, '${sandbox.path}/voice.m4a');
    expect(take.atMs, 2500);
    expect(take.interrupted, isFalse);
    expect(container.read(voiceControllerProvider).phase, VoicePhase.idle);
    expect(recorder.disposed, isTrue);
  });

  test('a denied microphone records nothing and says so', () async {
    final recorder = FakeRecorder(allowed: false);
    final container = containerWith(recorder);
    final voice = container.read(voiceControllerProvider.notifier);

    expect(await voice.start(0), isFalse);
    expect(container.read(voiceControllerProvider).phase, VoicePhase.denied);
    expect(recorder.path, isNull);

    voice.clearDenied();
    expect(container.read(voiceControllerProvider).phase, VoicePhase.idle);
  });

  test('an interrupted recording is kept and marked', () async {
    final container = containerWith(FakeRecorder());
    final voice = container.read(voiceControllerProvider.notifier);
    await voice.start(0);

    final take = await voice.stop(interrupted: true);

    expect(take!.interrupted, isTrue);
    expect(File(take.path).existsSync(), isTrue);
  });

  test('a recorder that fails to stop still gives back what it wrote',
      () async {
    final container = containerWith(FakeRecorder(failStop: true));
    final voice = container.read(voiceControllerProvider.notifier);
    await voice.start(0);

    final take = await voice.stop(interrupted: true);

    expect(take, isNotNull);
  });

  test('an empty file is not a take', () async {
    final container = containerWith(FakeRecorder(writes: ''));
    final voice = container.read(voiceControllerProvider.notifier);
    await voice.start(0);

    expect(await voice.stop(), isNull);
  });

  test('stopping without recording does nothing', () async {
    final container = containerWith(FakeRecorder());

    expect(
      await container.read(voiceControllerProvider.notifier).stop(),
      isNull,
    );
  });
}
