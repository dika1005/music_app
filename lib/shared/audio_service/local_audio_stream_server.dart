import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight in-app loopback HTTP streaming server.
/// 
/// Bridges YouTube Music dynamic/expiring stream URLs to ExoPlayer/just_audio.
/// Allows all tracks in a queue to have immediate valid HTTP URIs so that:
/// 1. Android Notification & lockscreen show full queue controls (Previous, Play/Pause, Next)
/// 2. Player switches tracks seamlessly without stopping or rebuilding audio pipelines
/// 3. Pre-resolved URLs return instantly with HTTP 302 Found
class LocalAudioStreamServer {
  HttpServer? _server;
  int _port = 0;
  int get port => _port;

  /// External resolver for audio URL if not present in memory cache
  Future<String?> Function(String videoId)? onResolveUrl;

  static const _cacheTtl = Duration(hours: 1);

  /// In-memory cache: videoId -> direct streaming URL with timestamp
  final Map<String, String> _urlCache = {};
  final Map<String, DateTime> _urlCacheTimes = {};

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('LocalAudioStreamServer error: $e');
      });
      debugPrint('LocalAudioStreamServer active on 127.0.0.1:$_port');
    } catch (e) {
      debugPrint('Failed to start LocalAudioStreamServer: $e');
    }
  }

  void cacheUrl(String videoId, String url) {
    if (videoId.isNotEmpty && url.isNotEmpty) {
      _urlCache[videoId] = url;
      _urlCacheTimes[videoId] = DateTime.now();
    }
  }

  void invalidateUrl(String videoId) {
    _urlCache.remove(videoId);
    _urlCacheTimes.remove(videoId);
  }

  void clearCache() {
    _urlCache.clear();
    _urlCacheTimes.clear();
  }

  String? getCachedUrl(String videoId) {
    final cached = _urlCache[videoId];
    final cachedAt = _urlCacheTimes[videoId];
    if (cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    return null;
  }

  bool hasCachedUrl(String videoId) => getCachedUrl(videoId) != null;

  String getStreamUri(String videoId) {
    if (_port == 0 || videoId.isEmpty) return '';
    return 'http://127.0.0.1:$_port/stream/$videoId';
  }

  /// Dipakai AppAudioHandler untuk memastikan server siap sebelum
  /// AudioSource dibuat. Kalau bind awal gagal (port 0), coba sekali lagi
  /// supaya tidak ada AudioSource dengan URI kosong ('') yang dikirim ke
  /// ExoPlayer — itu yang menyebabkan native crash / force close.
  Future<bool> ensureStarted() async {
    if (_server != null && _port != 0) return true;
    await start();
    return _server != null && _port != 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'stream') {
        final videoId = segments[1];
        final cached = _urlCache[videoId];
        final cachedAt = _urlCacheTimes[videoId];
        String? directUrl;
        if (cached != null && cached.isNotEmpty && cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl) {
          directUrl = cached;
        } else {
          _urlCache.remove(videoId);
          _urlCacheTimes.remove(videoId);
          directUrl = await onResolveUrl?.call(videoId);
        }

        if (directUrl != null && directUrl.isNotEmpty) {
          cacheUrl(videoId, directUrl);
          request.response.statusCode = HttpStatus.found; // HTTP 302 Redirect
          request.response.headers.set(HttpHeaders.locationHeader, directUrl);
          request.response.headers.set('Access-Control-Allow-Origin', '*');
          await request.response.close();
          return;
        }
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
