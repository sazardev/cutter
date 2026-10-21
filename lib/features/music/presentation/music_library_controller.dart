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
    this.catalogLoading = false,
    this.working = const {},
  });

  /// The packs on offer; null when there is no catalog, online or cached.
  final List<MusicPack>? catalog;

  /// Whether the catalog is still being asked for.
  final bool catalogLoading;

  /// The packs on the device, by id.
  final Map<String, InstalledPack> installed;

  /// Packs being installed, paused, or whose last install failed, by id.
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

  /// Whether a pack is downloading or being unpacked right now.
  bool get busy => working.values.any(
        (s) => s is PackDownloading || s is PackUnpacking,
      );

  /// What the music takes on disk: installed packs and paused downloads.
  int get usedBytes =>
      installed.values.fold(0, (sum, i) => sum + i.sizeBytes) +
      working.values.whereType<PackPaused>().fold(
            0,
            (sum, p) => sum + p.receivedBytes,
          );

  /// This state with the given parts replaced.
  MusicLibraryState copyWith({
    List<MusicPack>? catalog,
    bool? catalogLoading,
    Map<String, InstalledPack>? installed,
    Map<String, PackState>? working,
  }) =>
      MusicLibraryState(
        catalog: catalog ?? this.catalog,
        catalogLoading: catalogLoading ?? this.catalogLoading,
        installed: installed ?? this.installed,
        working: working ?? this.working,
      );
}

/// Loads the catalog and the installed packs, and installs, pauses, resumes,
/// cancels and removes packs. It lives as long as the app, so a download
/// goes on when the screen is left.
class MusicLibraryController extends AsyncNotifier<MusicLibraryState> {
  final Map<String, TransferControl> _controls = {};
  final Map<String, double?> _lastProgress = {};

  /// Completes when the catalog request of the last load or reload is done.
  Future<void> catalogReady = Future.value();

  @override
  Future<MusicLibraryState> build() async {
    final backend = await ref.watch(musicBackendProvider.future);
    final installed = await backend.store.installed();
    final partials = await backend.store.partials();
    catalogReady = _loadCatalog(backend);
    return MusicLibraryState(
      catalog: null,
      catalogLoading: true,
      installed: {for (final i in installed) i.pack.id: i},
      // Downloads cut short in an earlier run show as paused, so they can be
      // resumed or discarded; their pack is known once the catalog arrives.
      working: {
        for (final e in partials.entries)
          if (e.value > 0 && !installed.any((i) => i.pack.id == e.key))
            e.key: PackPaused(null, e.value),
      },
    );
  }

  Future<void> _loadCatalog(MusicBackend backend) async {
    final catalog = await backend.catalog.load();
    final current = state.valueOrNull;
    if (current == null) return;
    final working = {...current.working};
    // Now the sizes are known, say how far each leftover download got.
    for (final e in working.entries.toList()) {
      final paused = e.value;
      if (paused is! PackPaused) continue;
      if (catalog == null) continue;
      final pack = catalog.where((p) => p.id == e.key).firstOrNull;
      if (pack == null) {
        // A partial download of a pack nobody lists any more.
        await backend.store.discardPartial(e.key);
        working.remove(e.key);
      } else if (pack.bytes > 0) {
        working[e.key] = PackPaused(
          paused.receivedBytes / pack.bytes,
          paused.receivedBytes,
        );
      }
    }
    state = AsyncData(
      current.copyWith(
        catalog: catalog,
        catalogLoading: false,
        working: working,
      ),
    );
  }

  /// Asks for the catalog again.
  Future<void> reloadCatalog() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(catalogLoading: true));
    final backend = await ref.read(musicBackendProvider.future);
    catalogReady = _loadCatalog(backend);
    await catalogReady;
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

  /// Downloads and unpacks [pack], going on from what a paused or cut
  /// download left; a second call for a pack already being installed does
  /// nothing.
  Future<void> install(MusicPack pack) async {
    final current = state.valueOrNull;
    if (current == null || _controls.containsKey(pack.id)) return;
    final backend = await ref.read(musicBackendProvider.future);
    final control = _controls[pack.id] = TransferControl();
    _setWorking(pack.id, const PackDownloading(0));
    try {
      final done = await backend.store.install(
        pack,
        onProgress: (p) {
          _lastProgress[pack.id] = p;
          _setWorking(pack.id, PackDownloading(p));
        },
        onUnpacking: () => _setWorking(pack.id, const PackUnpacking()),
        control: control,
      );
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          installed: {...latest.installed, pack.id: done},
          working: {...latest.working}..remove(pack.id),
        ),
      );
    } on MusicTransferStopped catch (e) {
      if (e.paused) {
        final kept = (await backend.store.partials())[pack.id] ?? 0;
        _setWorking(
          pack.id,
          PackPaused(pack.bytes > 0 ? kept / pack.bytes : null, kept),
        );
      } else {
        _setWorking(pack.id, null);
      }
    } on MusicInstallException catch (e) {
      _setWorking(pack.id, PackFailed(e.failure));
    } finally {
      _controls.remove(pack.id);
      _lastProgress.remove(pack.id);
    }
  }

  /// Pauses the download of [id], keeping what was fetched.
  void pause(String id) => _controls[id]?.pause();

  /// Stops the download of [id] and throws away what was fetched; also
  /// discards a paused download.
  Future<void> cancel(String id) async {
    final control = _controls[id];
    if (control != null) {
      control.cancel();
      return;
    }
    final backend = await ref.read(musicBackendProvider.future);
    await backend.store.discardPartial(id);
    _setWorking(id, null);
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

  /// Deletes every installed pack and every paused download.
  Future<void> removeAll() async {
    final current = state.valueOrNull;
    if (current == null) return;
    for (final control in _controls.values) {
      control.cancel();
    }
    final backend = await ref.read(musicBackendProvider.future);
    for (final id in current.installed.keys) {
      await backend.store.remove(id);
    }
    for (final id in current.working.keys) {
      if (!_controls.containsKey(id)) await backend.store.discardPartial(id);
    }
    state = AsyncData(
      current.copyWith(
        installed: const {},
        working: {
          for (final e in current.working.entries)
            if (_controls.containsKey(e.key)) e.key: e.value,
        },
      ),
    );
  }
}

/// The music library's controller.
final musicLibraryProvider =
    AsyncNotifierProvider<MusicLibraryController, MusicLibraryState>(
  MusicLibraryController.new,
);
