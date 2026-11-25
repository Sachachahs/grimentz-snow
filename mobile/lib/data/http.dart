import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';

class HttpResult {
  final Uint8List bytes;
  final DateTime? lastModified; // instant (UTC)
  final String cookies; // cookies reçus (« nom=valeur; … »)
  HttpResult(this.bytes, this.lastModified, [this.cookies = '']);
}

class FetchException implements Exception {
  final String message;
  FetchException(this.message);
  @override
  String toString() => message;
}

/// Téléchargement simple avec délai maximal et un nouvel essai en cas de coupure.
Future<HttpResult> fetchBytes(String url,
    {Duration timeout = const Duration(seconds: 20),
    int retries = 1,
    String method = 'GET',
    Map<String, String> headers = const {}}) async {
  Object? last;
  for (var attempt = 0; attempt <= retries; attempt++) {
    final client = HttpClient()..connectionTimeout = timeout;
    client.userAgent = kUserAgent;
    try {
      final req = await client.openUrl(method, Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      headers.forEach(req.headers.set);
      if (method != 'GET') req.contentLength = 0;
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw FetchException('Erreur ${resp.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await resp.timeout(timeout * 2).forEach(builder.add);
      DateTime? lm;
      final h = resp.headers.value(HttpHeaders.lastModifiedHeader);
      if (h != null) {
        try {
          lm = HttpDate.parse(h);
        } catch (_) {
          lm = null;
        }
      }
      var cookies = '';
      try {
        cookies = resp.cookies.map((c) => '${c.name}=${c.value}').join('; ');
      } catch (_) {}
      return HttpResult(builder.takeBytes(), lm, cookies);
    } on FetchException catch (e) {
      last = e;
    } on SocketException {
      last = FetchException('Pas de connexion Internet');
    } on TimeoutException {
      last = FetchException('Délai dépassé');
    } on HandshakeException {
      last = FetchException('Connexion sécurisée impossible');
    } catch (e) {
      last = FetchException('Erreur réseau');
    } finally {
      client.close(force: true);
    }
    if (attempt < retries) await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  throw last ?? FetchException('Erreur réseau');
}
