import 'dart:async';

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

/// A store in memory; installing succeeds unless `failWith` is set, and
/// waits while `gate` is open so a test can pause or cancel it.
class FakeStore implements MusicPackStore {
  final Map<String, InstalledPack> packs = {};
  final Map<String, int> partialBytes = {};
  final List<String> discarded = [];
  MusicFailure? failWith;
  Completer<void>? gate;

  @override
  Future<List<InstalledPack>> installed() async => packs.values.toList();

  @override
  Future<Map<String, int>> partials() async => {...partialBytes};

  @override
  Future<void> discardPartial(String id) async {
    partialBytes.remove(id);
    discarded.add(id);
  }

  @override
  Future<InstalledPack> install(
    MusicPack pack, {
    required void Function(double? progress) onProgress,
    required void Function() onUnpacking,
    required TransferControl control,
  }) async {
    onProgress(partialBytes.containsKey(pack.id) ? 0.5 : 0.1);
    final open = gate;
    if (open != null) {
      await Future.any([open.future, control.whenStopped]);
      if (control.stopRequested) {
        if (control.cancelled) {
          partialBytes.remove(pack.id);
        } else {
          partialBytes[pack.id] = 1000;
        }
        throw MusicTransferStopped(paused: !control.cancelled);
      }
    }
    onUnpacking();
    final failure = failWith;
    if (failure != null) throw MusicInstallException(failure);
    partialBytes.remove(pack.id);
    return packs[pack.id] = InstalledPack(
      pack: pack,
      directory: '/music/${pack.id}',
      sizeBytes: 4000000,
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
