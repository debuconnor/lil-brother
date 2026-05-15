import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/discovered_tv.dart';

const String _ssdpAddr = '239.255.255.250';
const int _ssdpPort = 1900;
// SSDP M-SEARCH targeting Samsung TV remote control receivers
const String _mSearch = 'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: 3\r\n'
    'ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n'
    '\r\n';

/// Sends SSDP M-SEARCH multicast, waits 3 s for responses, then confirms
/// each responding IP is a Samsung TV via the REST API.
Future<List<DiscoveredTv>> discoverSamsungTvs() async {
    final ips = <String>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;

    try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.send(utf8.encode(_mSearch), InternetAddress(_ssdpAddr), _ssdpPort);

        sub = socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            final dg = socket?.receive();
            if (dg == null) return;
            ips.add(dg.address.address);
        });

        // Collect all SSDP responses within the MX window
        await Future<void>.delayed(const Duration(seconds: 3));
    } catch (_) {
        // Network or socket errors — return empty list
    } finally {
        await sub?.cancel();
        socket?.close();
    }

    if (ips.isEmpty) return const [];

    // Confirm each IP is a Samsung TV and extract details in parallel
    final fetched = await Future.wait(ips.map(fetchTvInfo));
    return fetched.whereType<DiscoveredTv>().toList();
}

/// Fetches TV MAC and model name from a known IP via the Samsung REST API.
Future<DiscoveredTv?> fetchTvInfo(String ip) async {
    try {
        final resp = await http
            .get(Uri.parse('http://$ip:8001/api/v2'))
            .timeout(const Duration(seconds: 3));
        if (resp.statusCode != 200) return null;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final device = data['device'] as Map<String, dynamic>?;
        if (device == null) return null;
        final mac = (device['wifiMac'] as String? ?? '')
            .replaceAll('-', ':')
            .toUpperCase();
        final model = device['modelName'] as String? ?? ip;
        if (mac.isEmpty) return null;
        return DiscoveredTv(ip: ip, mac: mac, name: model, modelName: model);
    } catch (_) {
        return null;
    }
}
