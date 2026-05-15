import 'package:web_socket_channel/web_socket_channel.dart';

// Web stub — browser enforces SSL; can't bypass self-signed certs.
// Only plain ws:// is usable on web.
Future<WebSocketChannel> connectWs(Uri uri) async {
    final ws = WebSocketChannel.connect(uri);
    await ws.ready;
    return ws;
}
