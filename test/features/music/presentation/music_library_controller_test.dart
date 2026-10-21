import 'dart:async';

import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:cutter/features/music/presentation/music_library_controller.dart';
import 'package:cutter/features/music/presentation/music_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_music_backend.dart';

void main() {
  late FakeStore store;

  ProviderContainer container({bool withCatalog = true}) {
    final c = ProviderContainer(
      overrides: [
        musicBackendProvider.overrideWith(
          (ref) async => fakeBackend(
            store,
            withCatalog ? [testPack(), testPack(id: 'calm')] : null,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<MusicLibraryController> ready(ProviderContainer c) async {
    await c.read(musicLibraryProvider.future);
    final controller = c.read(musicLibraryProvider.notifier);
    await controller.catalogReady;
    return controller;
  }

  MusicLibraryState stateOf(ProviderContainer c) =>
      c.read(musicLibraryProvider).requireValue;

  setUp(() => store = FakeStore());

  test('shows the installed packs at once and the catalog when it comes',
      () async {
    final c = container();
    final first = await c.read(musicLibraryProvider.future);
    expect(first.catalogLoading, isTrue);

    await c.read(musicLibraryProvider.notifier).catalogReady;
    final state = stateOf(c);
    expect(state.catalogLoading, isFalse);
    expect(state.packs.map((p) => p.id), ['epic', 'calm']);
    expect(state.stateOf('epic'), isA<PackAvailable>());
  });

  test('install moves a pack to installed and clears the work state', () async {
    final c = container();
    final controller = await ready(c);

    await controller.install(testPack());

    final state = stateOf(c);
    expect(state.stateOf('epic'), isA<PackInstalled>());
    expect(state.installed['epic']!.tracks, hasLength(2));
    expect(state.working, isEmpty);
    expect(state.usedBytes, 4000000);
  });

  test('a failed install is shown on that pack and can be retried', () async {
    final c = container();
    final controller = await ready(c);
    store.failWith = MusicFailure.network;

    await controller.install(testPack());
    expect(
      (stateOf(c).stateOf('epic') as PackFailed).failure,
      MusicFailure.network,
    );

    store.failWith = null;
    await controller.install(testPack());
    expect(stateOf(c).stateOf('epic'), isA<PackInstalled>());
  });

  test('pause keeps the download and resume finishes it', () async {
    final c = container();
    final controller = await ready(c);
    store.gate = Completer<void>();

    final running = controller.install(testPack());
    await Future<void>.delayed(Duration.zero);
    expect(stateOf(c).stateOf('epic'), isA<PackDownloading>());
    expect(stateOf(c).busy, isTrue);

    controller.pause('epic');
    await running;
    final paused = stateOf(c).stateOf('epic') as PackPaused;
    expect(paused.receivedBytes, 1000);
    expect(paused.progress, closeTo(1000 / 5000000, 1e-9));
    expect(stateOf(c).busy, isFalse);
    expect(stateOf(c).usedBytes, 1000);

    store.gate = null;
    await controller.install(testPack());
    expect(stateOf(c).stateOf('epic'), isA<PackInstalled>());
  });

  test('cancel while downloading leaves nothing', () async {
    final c = container();
    final controller = await ready(c);
    store.gate = Completer<void>();

    final running = controller.install(testPack());
    await Future<void>.delayed(Duration.zero);
    await controller.cancel('epic');
    await running;

    expect(stateOf(c).stateOf('epic'), isA<PackAvailable>());
    expect(store.partialBytes, isEmpty);
  });

  test('cancel on a paused download discards what was kept', () async {
    final c = container();
    final controller = await ready(c);
    store.gate = Completer<void>();
    final running = controller.install(testPack());
    await Future<void>.delayed(Duration.zero);
    controller.pause('epic');
    await running;

    await controller.cancel('epic');

    expect(stateOf(c).stateOf('epic'), isA<PackAvailable>());
    expect(store.discarded, ['epic']);
  });

  test('a second install of a pack already downloading is ignored', () async {
    final c = container();
    final controller = await ready(c);
    store.gate = Completer<void>();

    final first = controller.install(testPack());
    await Future<void>.delayed(Duration.zero);
    await controller.install(testPack());
    store.gate!.complete();
    await first;

    expect(stateOf(c).stateOf('epic'), isA<PackInstalled>());
  });

  test('a download cut in an earlier run shows as paused', () async {
    store.partialBytes['epic'] = 2500000;
    final c = container();
    await ready(c);

    final paused = stateOf(c).stateOf('epic') as PackPaused;
    expect(paused.progress, closeTo(0.5, 1e-9));
  });

  test('a leftover download of a pack nobody lists is discarded', () async {
    store.partialBytes['gone'] = 100;
    final c = container();
    await ready(c);

    expect(stateOf(c).working, isEmpty);
    expect(store.discarded, ['gone']);
  });

  test('without a catalog nothing kept is thrown away', () async {
    store.partialBytes['epic'] = 100;
    final c = container(withCatalog: false);
    await ready(c);

    expect(stateOf(c).stateOf('epic'), isA<PackPaused>());
    expect(store.discarded, isEmpty);
  });

  test('remove forgets the pack', () async {
    final c = container();
    final controller = await ready(c);
    await controller.install(testPack());

    await controller.remove('epic');

    expect(stateOf(c).stateOf('epic'), isA<PackAvailable>());
    expect(store.packs, isEmpty);
  });

  test('removeAll deletes installed packs and kept downloads', () async {
    final c = container();
    final controller = await ready(c);
    await controller.install(testPack());
    store.gate = Completer<void>();
    final running = controller.install(testPack(id: 'calm'));
    await Future<void>.delayed(Duration.zero);
    controller.pause('calm');
    await running;

    await controller.removeAll();

    final state = stateOf(c);
    expect(state.installed, isEmpty);
    expect(state.working, isEmpty);
    expect(state.usedBytes, 0);
    expect(store.packs, isEmpty);
    expect(store.discarded, ['calm']);
  });

  test('without a catalog the installed packs are still listed', () async {
    await store.install(
      testPack(id: 'old'),
      onProgress: (_) {},
      onUnpacking: () {},
      control: TransferControl(),
    );
    final c = container(withCatalog: false);
    await ready(c);

    final state = stateOf(c);
    expect(state.catalog, isNull);
    expect(state.packs.map((p) => p.id), ['old']);
  });
}
