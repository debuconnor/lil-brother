import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Native: bypasses SSL cert validation for WSS so Samsung TVs' self-signed
// certs (port 8002) are accepted without error.
Future<WebSocketChannel> connectWs(Uri uri) async {
    final ws = uri.isScheme('wss')
        ? IOWebSocketChannel.connect(
            uri,
            customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
          )
        : IOWebSocketChannel.connect(uri);
    await ws.ready;
    return ws;
}
