import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:cutter/features/music/presentation/music_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the music library shows.
class MusicLibraryState {
  /// Creates the state.
  const MusicLibraryState({
    required this.catalog,
    required this.installed,
    this.working = const {},
  });

  /// The packs on offer; null when there is no catalog, online or cached.
  final List<MusicPack>? catalog;

  /// The packs on the device, by id.
  final Map<String, InstalledPack> installed;

  /// Packs being installed, or whose last install failed, by id.
  final Map<String, PackState> working;

  /// The packs to list: the catalog, then any installed pack it no longer
  /// lists, so what is on the device is always reachable.
  List<MusicPack> get packs {
    final listed = catalog ?? const <MusicPack>[];
    final ids = {for (final p in listed) p.id};
    return [
      ...listed,
      for (final i in installed.values)
        if (!ids.contains(i.pack.id)) i.pack,
    ];
  }

  /// Where [id] stands.
  PackState stateOf(String id) =>
      working[id] ??
      (installed.containsKey(id)
          ? const PackInstalled()
          : const PackAvailable());

  /// This state with [working] replaced.
  MusicLibraryState copyWith({
    Map<String, InstalledPack>? installed,
    Map<String, PackState>? working,
  }) =>
      MusicLibraryState(
        catalog: catalog,
        installed: installed ?? this.installed,
        working: working ?? this.working,
      );
}

/// Loads the catalog and the installed packs, and installs and removes packs.
class MusicLibraryController extends AsyncNotifier<MusicLibraryState> {
  @override
  Future<MusicLibraryState> build() async {
    final backend = await ref.watch(musicBackendProvider.future);
    final installed = await backend.store.installed();
    final catalog = await backend.catalog.load();
    return MusicLibraryState(
      catalog: catalog,
      installed: {for (final i in installed) i.pack.id: i},
    );
  }

  void _setWorking(String id, PackState? value) {
    final current = state.valueOrNull;
    if (current == null) return;
    final working = {...current.working};
    if (value == null) {
      working.remove(id);
    } else {
      working[id] = value;
    }
    state = AsyncData(current.copyWith(working: working));
  }

  /// Downloads and unpacks [pack]; a second call for a pack already being
  /// installed does nothing.
  Future<void> install(MusicPack pack) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final now = current.working[pack.id];
    if (now is PackDownloading || now is PackUnpacking) return;
    final backend = await ref.read(musicBackendProvider.future);
    _setWorking(pack.id, const PackDownloading(0));
    try {
      final done = await backend.store.install(
        pack,
        onProgress: (p) => _setWorking(pack.id, PackDownloading(p)),
        onUnpacking: () => _setWorking(pack.id, const PackUnpacking()),
      );
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          installed: {...latest.installed, pack.id: done},
          working: {...latest.working}..remove(pack.id),
        ),
      );
    } on MusicInstallException catch (e) {
      _setWorking(pack.id, PackFailed(e.failure));
    }
  }

  /// Deletes the installed pack with [id].
  Future<void> remove(String id) async {
    final backend = await ref.read(musicBackendProvider.future);
    await backend.store.remove(id);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(installed: {...current.installed}..remove(id)),
    );
  }
}

/// The music library's controller.
final musicLibraryProvider =
    AsyncNotifierProvider<MusicLibraryController, MusicLibraryState>(
  MusicLibraryController.new,
);
