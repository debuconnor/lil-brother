import 'dart:io';
import 'dart:typed_data';

// Sends a WOL magic packet via UDP broadcast to wake the TV from standby.
Future<void> sendWakeOnLan(String mac) async {
    final parts = mac.split(RegExp(r'[:\-]'));
    if (parts.length != 6) {
        throw ArgumentError('올바르지 않은 MAC 주소 형식: $mac');
    }

    final macBytes = parts.map((s) => int.parse(s, radix: 16)).toList();

    // Magic packet: 6 bytes of 0xFF followed by MAC repeated 16 times (102 bytes total)
    final packet = Uint8List(102);
    for (int i = 0; i < 6; i++) {
        packet[i] = 0xFF;
    }
    for (int rep = 0; rep < 16; rep++) {
        for (int b = 0; b < 6; b++) {
            packet[6 + rep * 6 + b] = macBytes[b];
        }
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.send(packet, InternetAddress('255.255.255.255'), 9);
    await Future.delayed(const Duration(milliseconds: 100));
    socket.close();
}
