import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Download state exposed to the UI.
enum DownloadStatus { idle, downloading, paused, done, error }

/// Resumable HTTP file downloader.
///
/// Strategy:
///   1. Downloads to a `.part` temp file alongside the final destination.
///   2. On each (re)start it sends a `Range: bytes=<already_received>-`
///      header so the server resumes from where it left off (HTTP 206).
///   3. When the download finishes the temp file is atomically renamed to
///      the final destination path.
///   4. If the server does not support range requests (returns 200 instead
///      of 206) the temp file is truncated and the download restarts.
///
/// Usage:
///   final dl = ModelDownloadService(
///     url: 'https://…/model.gguf',
///     destPath: '/data/.../models/model.gguf',
///     expectedBytes: 3_460_000_000,
///   );
///   dl.addListener(() { /* update UI from dl.status / dl.progress */ });
///   await dl.start();   // also resumes a paused download
///   dl.pause();
class ModelDownloadService extends ChangeNotifier {
  final String url;
  final String destPath;
  final int expectedBytes;

  DownloadStatus _status = DownloadStatus.idle;
  int _received = 0;
  int _total = 0;
  String? _errorMessage;

  // Active download bookkeeping — null when idle/paused.
  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  IOSink? _sink;

  ModelDownloadService({
    required this.url,
    required this.destPath,
    required this.expectedBytes,
  }) : _total = expectedBytes;

  // ── Public state ────────────────────────────────────────────────────────────

  DownloadStatus get status => _status;

  /// 0.0 – 1.0 progress, or null when total is unknown.
  double? get progress => _total > 0 ? _received / _total : null;

  int get receivedBytes => _received;
  int get totalBytes => _total;

  String? get errorMessage => _errorMessage;

  bool get isDone => _status == DownloadStatus.done;
  bool get isActive => _status == DownloadStatus.downloading;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Start or resume the download.
  ///
  /// Safe to call multiple times; ignored if already downloading or done.
  Future<void> start() async {
    if (_status == DownloadStatus.downloading || _status == DownloadStatus.done) {
      return;
    }

    // Check if final file already exists (e.g. app restarted after completion).
    if (await File(destPath).exists()) {
      _status = DownloadStatus.done;
      _received = _total;
      notifyListeners();
      return;
    }

    _status = DownloadStatus.downloading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _doDownload();
    } catch (e) {
      if (_status != DownloadStatus.paused) {
        _status = DownloadStatus.error;
        _errorMessage = e.toString();
        debugPrint('[ModelDownloadService] Error: $e');
        notifyListeners();
      }
    }
  }

  /// Pause the active download. The `.part` file is kept on disk so
  /// [start] can resume from the current byte offset.
  void pause() {
    if (_status != DownloadStatus.downloading) return;
    _status = DownloadStatus.paused;
    _subscription?.cancel();
    _subscription = null;
    _sink?.flush();
    _sink?.close();
    _sink = null;
    _client?.close();
    _client = null;
    notifyListeners();
  }

  @override
  void dispose() {
    pause(); // clean up active resources
    super.dispose();
  }

  // ── Core download logic ─────────────────────────────────────────────────────

  String get _partPath => '$destPath.part';

  Future<void> _doDownload() async {
    final modelsDir = Directory(File(destPath).parent.path);
    await modelsDir.create(recursive: true);

    final partFile = File(_partPath);
    int alreadyHave = 0;

    if (await partFile.exists()) {
      alreadyHave = await partFile.length();
      _received = alreadyHave;
      notifyListeners();
    }

    final uri = Uri.parse(url);
    _client = http.Client();

    final request = http.Request('GET', uri);
    if (alreadyHave > 0) {
      request.headers['Range'] = 'bytes=$alreadyHave-';
      debugPrint('[ModelDownloadService] Resuming from byte $alreadyHave');
    }

    final response = await _client!.send(request);

    // 416 = Range Not Satisfiable → file already fully downloaded on server
    if (response.statusCode == 416) {
      await _finalize(partFile);
      return;
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }

    // If server returned 200 instead of 206 it doesn't support range requests.
    // Truncate and restart from zero.
    if (response.statusCode == 200 && alreadyHave > 0) {
      debugPrint('[ModelDownloadService] Server does not support Range — restarting');
      await partFile.writeAsBytes([], mode: FileMode.write);
      alreadyHave = 0;
      _received = 0;
    }

    // Update total from Content-Length (or Content-Range).
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > 0) {
      _total = alreadyHave + contentLength;
    }
    notifyListeners();

    final sink = partFile.openWrite(mode: FileMode.append);
    _sink = sink;

    final completer = Completer<void>();

    _subscription = response.stream.listen(
      (chunk) {
        sink.add(chunk);
        _received += chunk.length;
        notifyListeners();
      },
      onDone: () => completer.complete(),
      onError: (Object e) => completer.completeError(e),
      cancelOnError: true,
    );

    await completer.future;

    await sink.flush();
    await sink.close();
    _sink = null;
    _subscription = null;
    _client?.close();
    _client = null;

    await _finalize(partFile);
  }

  Future<void> _finalize(File partFile) async {
    // Atomic rename: part file → final destination.
    await partFile.rename(destPath);
    _status = DownloadStatus.done;
    _received = _total > 0 ? _total : _received;
    debugPrint('[ModelDownloadService] Download complete: $destPath');
    notifyListeners();
  }
}
