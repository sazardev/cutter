import 'dart:io';

import 'package:cutter/features/music/data/file_music_pack_store.dart';
import 'package:cutter/features/music/data/http_music_catalog.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const _catalogFromEnvironment = String.fromEnvironment('MUSIC_CATALOG_URL');

/// The catalog the release workflow publishes (`.github/workflows/
/// music-packs.yml`), used unless a build gives another with
/// `--dart-define=MUSIC_CATALOG_URL=...` (see `.env.example`).
const defaultMusicCatalogUrl =
    'https://github.com/sazardev/cutter/releases/download/music-v1/catalog.json';

/// Where the packs are listed.
const musicCatalogUrl = _catalogFromEnvironment == ''
    ? defaultMusicCatalogUrl
    : _catalogFromEnvironment;

/// The catalog and the store of packs, as one unit so the controller reads
/// both from the same folder. Tests override it with fakes.
class MusicBackend {
  /// Creates the backend.
  const MusicBackend({required this.catalog, required this.store});

  /// The packs on offer.
  final MusicCatalog catalog;

  /// The packs on the device.
  final MusicPackStore store;
}

/// The real backend: packs under `<app support>/music`, in the folder phones
/// keep for app data (never cleared by the media scanner).
final musicBackendProvider = FutureProvider<MusicBackend>((ref) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/music');
  return MusicBackend(
    catalog: HttpMusicCatalog(
      url: musicCatalogUrl,
      cache: File('${root.path}/.catalog.json'),
    ),
    store: FileMusicPackStore(root: root),
  );
});
