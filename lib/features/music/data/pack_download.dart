import 'dart:async';
import 'dart:io';

import 'package:cutter/features/music/domain/music_ports.dart';

/// Downloads [url] into [target], reporting the bytes received and the total
/// (-1 when the server does not say). When [target] already holds the start
/// of the file, it goes on from there. Stops with [MusicTransferStopped] when
/// [control] asks; throws when the transfer fails.
typedef PackDownloader = Future<void> Function(
  Uri url,
  File target,
  void Function(int received, int total) onProgress,
  TransferControl control,
);

/// How long the server may stay silent before the download is given up.
const _idleTimeout = Duration(seconds: 30);

/// The downloader the app uses: one streamed GET, written straight to disk so
/// a pack of any size never sits in memory, resuming a partial file with a
/// `Range` request when the server supports it.
Future<void> downloadWithHttpClient(
  Uri url,
  File target,
  void Function(int received, int total) onProgress,
  TransferControl control,
) async {
  final client = HttpClient()..connectionTimeout = _idleTimeout;
  try {
    final offset = target.existsSync() ? target.lengthSync() : 0;
    final request = await client.getUrl(url);
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close().timeout(_idleTimeout);
    if (control.stopRequested) {
      await response.drain<void>();
      throw MusicTransferStopped(paused: !control.cancelled);
    }
    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // What is on disk is not a prefix of the file: start over.
      await response.drain<void>();
      await target.delete();
      await downloadWithHttpClient(url, target, onProgress, control);
      return;
    }
    final resumed = response.statusCode == HttpStatus.partialContent;
    if (response.statusCode != HttpStatus.ok && !resumed) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    var received = resumed ? offset : 0;
    final total = response.contentLength < 0
        ? -1
        : response.contentLength + (resumed ? offset : 0);
    final sink = target.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    try {
      final done = Completer<void>();
      final sub = response.timeout(_idleTimeout).listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        },
        onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      unawaited(
        control.whenStopped.then((_) {
          if (done.isCompleted) return;
          unawaited(sub.cancel());
          done.complete();
        }),
      );
      await done.future;
    } finally {
      await sink.close();
    }
    if (control.stopRequested) {
      throw MusicTransferStopped(paused: !control.cancelled);
    }
    if (total >= 0 && received != total) {
      throw HttpException('Truncated: $received of $total bytes', uri: url);
    }
  } finally {
    client.close(force: true);
  }
}
