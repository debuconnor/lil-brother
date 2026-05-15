import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// Conditional import: wol_service_io.dart on native, wol_service.dart (stub) on web
import 'wol_service.dart' if (dart.library.io) 'wol_service_io.dart';

class SamsungTvClient {
    static const int _apiPort = 8001;
    // base64('lil-brother')
    static const String _remoteName = 'bGlsLWJyb3RoZXI=';
    static const Duration _httpTimeout = Duration(seconds: 3);
    static const Duration _wsTimeout = Duration(seconds: 5);

    final String ip;
    final String mac;

    SamsungTvClient({required this.ip, required this.mac});

    String get _wsUrl => 'ws://$ip:$_apiPort/api/v2/channels/samsung.remote.control';
    String get _restUrl => 'http://$ip:$_apiPort/api/v2';

    /// Returns true if TV is responding to REST ping (powered on).
    /// On web, may return false due to browser CORS restrictions.
    Future<bool> isOn() async {
        try {
            final resp = await http.get(Uri.parse(_restUrl)).timeout(_httpTimeout);
            return resp.statusCode == 200;
        } catch (_) {
            return false;
        }
    }

    /// Sends a WOL magic packet via UDP. Throws [UnsupportedError] on web.
    Future<void> wakeOnLan() => sendWakeOnLan(mac);

    /// Connects via WebSocket and sends a remote control key.
    /// Opens a fresh connection per call to avoid stale connection issues.
    Future<void> sendKey(String keyCode) async {
        final ws = WebSocketChannel.connect(Uri.parse(_wsUrl));
        try {
            await ws.ready.timeout(_wsTimeout);

            // Samsung TV WebSocket authentication handshake
            ws.sink.add(jsonEncode({
                'method': 'ms.channel.connect',
                'params': {'name': _remoteName},
            }));

            // Wait for TV to process the handshake before sending key
            await Future.delayed(const Duration(milliseconds: 350));

            ws.sink.add(jsonEncode({
                'method': 'ms.remote.control',
                'params': {
                    'Cmd': 'Click',
                    'DataOfCmd': keyCode,
                    'Option': 'false',
                    'TypeOfRemote': 'SendRemoteKey',
                },
            }));

            await Future.delayed(const Duration(milliseconds: 200));
        } finally {
            await ws.sink.close();
        }
    }
}
