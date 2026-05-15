import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tv_config.dart';
import '../services/samsung_tv_client.dart';

enum TvStatus { unknown, online, offline }

class TvProvider extends ChangeNotifier {
    static const String _keyIp = 'tv_ip';
    static const String _keyMac = 'tv_mac';
    static const Duration _pollInterval = Duration(seconds: 6);

    // Initialized synchronously from pre-loaded SharedPreferences in main().
    TvConfig _config;
    TvStatus _status = TvStatus.unknown;
    bool _busy = false;
    String? _error;
    Timer? _pollTimer;

    TvProvider(SharedPreferences prefs)
        : _config = TvConfig(
            ip: prefs.getString(_keyIp) ?? '',
            mac: prefs.getString(_keyMac) ?? '',
          );

    TvConfig get config => _config;
    TvStatus get status => _status;
    bool get busy => _busy;
    // Always true — config loaded synchronously before runApp
    bool get initialized => true;
    String? get error => _error;

    SamsungTvClient get _client => SamsungTvClient(ip: _config.ip, mac: _config.mac);

    Future<void> init() async {
        if (_config.isConfigured) {
            try {
                await checkStatus();
            } catch (e) {
                debugPrint('TvProvider.init: checkStatus failed: $e');
            }
            _startPolling();
        }
    }

    Future<void> saveConfig(TvConfig config) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyIp, config.ip);
        await prefs.setString(_keyMac, config.mac);
        _config = config;
        _status = TvStatus.unknown;
        _error = null;
        _stopPolling();
        notifyListeners();
        if (_config.isConfigured) {
            await checkStatus();
            _startPolling();
        }
    }

    Future<void> checkStatus() async {
        if (!_config.isConfigured) return;
        final on = await _client.isOn();
        _status = on ? TvStatus.online : TvStatus.offline;
        // Auto-fetch and save MAC when TV is online and MAC is not yet stored
        if (on && !_config.hasMac) {
            final mac = await _client.fetchMac();
            if (mac != null) await _saveMac(mac);
        }
        notifyListeners();
    }

    Future<void> _saveMac(String mac) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyMac, mac);
        _config = _config.copyWith(mac: mac);
        debugPrint('TvProvider: MAC auto-saved: $mac');
    }

    Future<void> togglePower() async {
        if (!_config.isConfigured || _busy) return;
        _busy = true;
        _error = null;
        notifyListeners();
        try {
            if (_status == TvStatus.online) {
                await _client.sendKey('KEY_POWER');
                _status = TvStatus.offline;
                // Re-check after the TV has had time to enter standby
                Future.delayed(const Duration(seconds: 4), checkStatus);
            } else {
                if (!_config.hasMac) {
                    throw Exception('TV를 켜려면 MAC 주소가 필요합니다. 설정(⚙)에서 MAC을 입력하거나 TV가 켜진 상태에서 다시 시도하세요.');
                }
                await _client.wakeOnLan();
                // TV takes a few seconds to boot
                _status = TvStatus.unknown;
            }
        } on UnsupportedError catch (e) {
            _error = e.message ?? '이 플랫폼에서는 지원하지 않는 기능입니다';
        } catch (e) {
            _error = e.toString();
        } finally {
            _busy = false;
            notifyListeners();
        }
    }

    Future<void> sendKey(String key) async {
        if (!_config.isConfigured || _busy) return;
        _busy = true;
        _error = null;
        notifyListeners();
        try {
            await _client.sendKey(key);
        } catch (e) {
            _error = e.toString();
        } finally {
            _busy = false;
            notifyListeners();
        }
    }

    void _startPolling() {
        _pollTimer = Timer.periodic(_pollInterval, (_) => checkStatus());
    }

    void _stopPolling() {
        _pollTimer?.cancel();
        _pollTimer = null;
    }

    @override
    void dispose() {
        _stopPolling();
        super.dispose();
    }
}
