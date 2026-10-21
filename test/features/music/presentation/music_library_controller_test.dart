import 'package:cutter/features/music/domain/music_install_state.dart';
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

  setUp(() => store = FakeStore());

  test('lists the catalog with nothing installed', () async {
    final c = container();
    final state = await c.read(musicLibraryProvider.future);
    expect(state.packs.map((p) => p.id), ['epic', 'calm']);
    expect(state.stateOf('epic'), isA<PackAvailable>());
  });

  test('install moves a pack to installed and clears the work state', () async {
    final c = container();
    await c.read(musicLibraryProvider.future);

    await c.read(musicLibraryProvider.notifier).install(testPack());

    final state = c.read(musicLibraryProvider).requireValue;
    expect(state.stateOf('epic'), isA<PackInstalled>());
    expect(state.installed['epic']!.tracks, hasLength(2));
    expect(state.working, isEmpty);
    expect(state.stateOf('calm'), isA<PackAvailable>());
  });

  test('a failed install is shown on that pack and can be retried', () async {
    final c = container();
    await c.read(musicLibraryProvider.future);
    store.failWith = MusicFailure.network;

    await c.read(musicLibraryProvider.notifier).install(testPack());
    var state = c.read(musicLibraryProvider).requireValue;
    expect(
      (state.stateOf('epic') as PackFailed).failure,
      MusicFailure.network,
    );

    store.failWith = null;
    await c.read(musicLibraryProvider.notifier).install(testPack());
    state = c.read(musicLibraryProvider).requireValue;
    expect(state.stateOf('epic'), isA<PackInstalled>());
  });

  test('remove forgets the pack', () async {
    final c = container();
    await c.read(musicLibraryProvider.future);
    await c.read(musicLibraryProvider.notifier).install(testPack());

    await c.read(musicLibraryProvider.notifier).remove('epic');

    final state = c.read(musicLibraryProvider).requireValue;
    expect(state.stateOf('epic'), isA<PackAvailable>());
    expect(store.packs, isEmpty);
  });

  test('without a catalog the installed packs are still listed', () async {
    await store.install(
      testPack(id: 'old'),
      onProgress: (_) {},
      onUnpacking: () {},
    );
    final c = container(withCatalog: false);

    final state = await c.read(musicLibraryProvider.future);

    expect(state.catalog, isNull);
    expect(state.packs.map((p) => p.id), ['old']);
  });
}
