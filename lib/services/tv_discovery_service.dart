import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/discovered_tv.dart';

// Web stub — SSDP requires dart:io (UDP sockets unavailable on web).
Future<List<DiscoveredTv>> discoverSamsungTvs() async => const [];

/// Fetches TV MAC and model name from a known IP via the Samsung REST API.
/// May fail on web due to browser CORS restrictions.
Future<DiscoveredTv?> fetchTvInfo(String ip,
    {Duration timeout = const Duration(seconds: 3)}) async {
    try {
        final resp = await http
            .get(Uri.parse('http://$ip:8001/api/v2'))
            .timeout(timeout);
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
