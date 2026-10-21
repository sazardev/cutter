import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:cutter/features/music/presentation/music_providers.dart';

/// A pack of the catalog for tests.
MusicPack testPack({String id = 'epic', int tracks = 2}) => MusicPack(
      id: id,
      names: {'en': 'Epic $id', 'es': 'Épica $id'},
      genre: 'epic',
      source: const MusicSource(name: 'FreePD', license: 'CC0-1.0'),
      url: 'https://example.test/$id.zip',
      bytes: 5000000,
      trackCount: tracks,
    );

/// A catalog that answers with [packs].
class FakeCatalog implements MusicCatalog {
  FakeCatalog(this.packs);

  final List<MusicPack>? packs;

  @override
  Future<List<MusicPack>?> load() async => packs;
}

/// A store in memory; installing succeeds unless `failWith` is set.
class FakeStore implements MusicPackStore {
  final Map<String, InstalledPack> packs = {};
  MusicFailure? failWith;

  @override
  Future<List<InstalledPack>> installed() async => packs.values.toList();

  @override
  Future<InstalledPack> install(
    MusicPack pack, {
    required void Function(double? progress) onProgress,
    required void Function() onUnpacking,
  }) async {
    onProgress(0.5);
    onUnpacking();
    final failure = failWith;
    if (failure != null) throw MusicInstallException(failure);
    return packs[pack.id] = InstalledPack(
      pack: pack,
      directory: '/music/${pack.id}',
      tracks: const [
        MusicTrack(file: 'a.mp3', title: 'Anthem', artist: 'FreePD', bpm: 120),
        MusicTrack(file: 'b.mp3', title: 'Battle'),
      ],
    );
  }

  @override
  Future<void> remove(String id) async => packs.remove(id);
}

/// The backend the tests override the real one with.
MusicBackend fakeBackend(FakeStore store, List<MusicPack>? catalog) =>
    MusicBackend(catalog: FakeCatalog(catalog), store: store);
