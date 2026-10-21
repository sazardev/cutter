import 'dart:async';
import 'dart:io';

/// Downloads [url] into [target], reporting the bytes received and the total
/// (-1 when the server does not say). Throws when the transfer fails.
typedef PackDownloader = Future<void> Function(
  Uri url,
  File target,
  void Function(int received, int total) onProgress,
);

/// How long the server may stay silent before the download is given up.
const _idleTimeout = Duration(seconds: 30);

/// The downloader the app uses: one streamed GET, written straight to disk so
/// a pack of any size never sits in memory.
Future<void> downloadWithHttpClient(
  Uri url,
  File target,
  void Function(int received, int total) onProgress,
) async {
  final client = HttpClient()..connectionTimeout = _idleTimeout;
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(_idleTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final total = response.contentLength;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(_idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    } finally {
      await sink.close();
    }
    if (total >= 0 && received != total) {
      throw HttpException('Truncated: $received of $total bytes', uri: url);
    }
  } finally {
    client.close(force: true);
  }
}
