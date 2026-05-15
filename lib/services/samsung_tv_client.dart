import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'wol_service.dart' if (dart.library.io) 'wol_service_io.dart';
import 'ws_connect.dart' if (dart.library.io) 'ws_connect_io.dart';

void _log(String msg) => debugPrint('[TvClient] $msg');

class SamsungTvClient {
    static const int _apiPort = 8001;
    static const int _wsPort = 8001;
    // Samsung 2018+ TVs often block ws:8001 and only accept wss:8002
    static const int _wssPort = 8002;
    // base64('lil-brother')
    static const String _remoteName = 'bGlsLWJyb3RoZXI=';
    static const Duration _httpTimeout = Duration(seconds: 3);
    static const Duration _wsTimeout = Duration(seconds: 5);

    /// Token cache per TV IP — persists for the app session.
    static final Map<String, String> _tokenCache = {};

    /// Protocol cache: true = wss:8002 worked, false = ws:8001 used, null = untested.
    static final Map<String, bool> _wssCache = {};

    /// Evicts the cached pairing token and protocol selection for [ip].
    static void clearToken(String ip) {
        _tokenCache.remove(ip);
        _wssCache.remove(ip);
    }

    final String ip;
    final String mac;

    SamsungTvClient({required this.ip, required this.mac});

    String get _restUrl => 'http://$ip:$_apiPort/api/v2/';

    /// Returns true if TV is responding to REST ping (powered on).
    Future<bool> isOn() async {
        try {
            final resp = await http.get(Uri.parse(_restUrl)).timeout(_httpTimeout);
            return resp.statusCode == 200;
        } catch (_) {
            return false;
        }
    }

    /// Fetches the TV's MAC address from the REST API.
    /// Returns null if the TV is unreachable or the field is absent.
    Future<String?> fetchMac() async {
        try {
            final resp = await http.get(Uri.parse(_restUrl)).timeout(_httpTimeout);
            if (resp.statusCode != 200) return null;
            final body = jsonDecode(resp.body) as Map<String, dynamic>;
            final device = body['device'] as Map<String, dynamic>?;
            final mac = device?['wifiMac'] as String?;
            return (mac != null && mac.isNotEmpty) ? mac : null;
        } catch (_) {
            return null;
        }
    }

    /// Sends a WOL magic packet via UDP. Throws [UnsupportedError] on web.
    Future<void> wakeOnLan() => sendWakeOnLan(mac);

    Uri _buildWsUri(String scheme, int port, String? token) =>
        Uri.parse('$scheme://$ip:$port/api/v2/channels/samsung.remote.control')
            .replace(queryParameters: {
                // Some firmware reads name+token from query params
                'name': _remoteName,
                if (token != null) 'token': token,
            });

    /// Opens a WebSocket to the TV.
    ///
    /// On native: tries wss:8002 first (required by many 2018+ Samsung TVs),
    /// falls back to ws:8001 if the secure port is unavailable.
    /// On web: always uses ws:8001 — the browser blocks self-signed WSS certs.
    /// Caches the working protocol so subsequent calls skip the probe.
    Future<WebSocketChannel> _openWs(String? token) async {
        if (kIsWeb || _wssCache[ip] == false) {
            final uri = _buildWsUri('ws', _wsPort, token);
            _log('WS connecting to $ip:$_wsPort');
            return connectWs(uri).timeout(_wsTimeout);
        }

        if (_wssCache[ip] == true) {
            final uri = _buildWsUri('wss', _wssPort, token);
            _log('WSS connecting to $ip:$_wssPort (cached)');
            return connectWs(uri).timeout(_wsTimeout);
        }

        // First attempt: probe WSS then fall back to WS
        try {
            final uri = _buildWsUri('wss', _wssPort, token);
            _log('WSS connecting to $ip:$_wssPort (probing)');
            final ws = await connectWs(uri).timeout(_wsTimeout);
            _wssCache[ip] = true;
            _log('WSS connected');
            return ws;
        } catch (e) {
            _log('WSS failed ($e), falling back to ws:$_wsPort');
            final uri = _buildWsUri('ws', _wsPort, token);
            final ws = await connectWs(uri).timeout(_wsTimeout);
            _wssCache[ip] = false;
            _log('WS connected');
            return ws;
        }
    }

    /// Connects via WebSocket and sends a remote control key.
    /// Waits for the TV's ms.channel.connect acknowledgment before sending.
    /// Caches the session token so the TV does not show the pairing dialog again.
    Future<void> sendKey(String keyCode) async {
        final token = _tokenCache[ip];
        _log('sendKey $keyCode (token=${token != null ? "cached" : "none"})');

        final ws = await _openWs(token);
        StreamSubscription<dynamic>? sub;
        try {
            // Send connect handshake (body params)
            ws.sink.add(jsonEncode({
                'method': 'ms.channel.connect',
                'params': {
                    'name': _remoteName,
                    if (token != null) 'token': token,
                },
            }));

            // Wait for TV's connect acknowledgment; extract token if present
            final connectDone = Completer<void>();
            sub = ws.stream.listen(
                (raw) {
                    try {
                        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
                        final event = msg['event'] as String?;
                        _log('WS event: $event');
                        if (event == 'ms.channel.connect') {
                            final data = msg['data'] as Map<String, dynamic>?;
                            final newToken = data?['token'] as String?;
                            if (newToken != null && newToken.isNotEmpty) {
                                _log('WS: token received, caching for $ip');
                                _tokenCache[ip] = newToken;
                            }
                            if (!connectDone.isCompleted) connectDone.complete();
                        } else if (event == 'ms.channel.unauthorized') {
                            // Evict stale token so the next attempt sends a clean handshake.
                            _tokenCache.remove(ip);
                            _log('WS: unauthorized — cleared cached token for $ip');
                            if (!connectDone.isCompleted) {
                                connectDone.completeError(
                                    Exception(
                                        'TV가 연결을 거부했습니다.\n'
                                        'TV에서 확인 창이 뜨지 않으면: 설정 → 일반 → 외부 장치 관리자 → '
                                        '기기 연결 관리자 → 기기 목록에서 lil-brother를 삭제 후 다시 시도하세요.',
                                    ),
                                );
                            }
                        }
                    } catch (_) {}
                },
                onError: (e) {
                    if (!connectDone.isCompleted) connectDone.completeError(e);
                    _log('WS stream error: $e');
                },
                cancelOnError: false,
            );

            try {
                await connectDone.future.timeout(const Duration(seconds: 2));
            } on TimeoutException {
                if (token == null) {
                    // No prior token = first-time pairing; TV is showing the approval dialog.
                    // Key sent now would be silently dropped before the user can confirm.
                    throw Exception('TV 화면에서 \'lil-brother\' 연결을 허용한 후 다시 시도하세요.');
                }
                // Known quirk: some firmware versions don't send the ack even when paired.
                _log('WS: no connect ack within 2s (ack-less firmware), sending key anyway');
            }

            _log('WS: sending key $keyCode');
            ws.sink.add(jsonEncode({
                'method': 'ms.remote.control',
                'params': {
                    'Cmd': 'Click',
                    'DataOfCmd': keyCode,
                    'Option': 'false',
                    'TypeOfRemote': 'SendRemoteKey',
                },
            }));

            await Future.delayed(const Duration(milliseconds: 300));
        } finally {
            await sub?.cancel();
            await ws.sink.close();
            _log('WS closed');
        }
    }
}
