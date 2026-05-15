import 'package:flutter/foundation.dart';

import '../models/discovered_tv.dart';
// Conditional import: SSDP (dart:io) on native, HTTP-only stub on web
import '../services/tv_discovery_service.dart'
    if (dart.library.io) '../services/tv_discovery_service_io.dart';

class TvDiscoveryProvider extends ChangeNotifier {
    List<DiscoveredTv> _results = const [];
    bool _scanning = false;
    String? _error;

    List<DiscoveredTv> get results => _results;
    bool get scanning => _scanning;
    String? get error => _error;

    /// Runs SSDP discovery (native only) and confirms each found TV via REST.
    Future<void> scan() async {
        if (_scanning) return;
        _scanning = true;
        _error = null;
        _results = const [];
        notifyListeners();
        try {
            _results = await discoverSamsungTvs();
            if (_results.isEmpty) {
                _error = '주변에서 삼성 TV를 찾지 못했습니다';
            }
        } catch (e) {
            _error = '탐색 오류: $e';
        } finally {
            _scanning = false;
            notifyListeners();
        }
    }

    /// Confirms a TV at [ip] and returns its details. Works on all platforms.
    Future<DiscoveredTv?> fetchFromIp(String ip) async {
        try {
            return await fetchTvInfo(ip);
        } catch (_) {
            return null;
        }
    }
}
