import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tv_config.dart';
import '../services/samsung_tv_client.dart';

enum TvStatus { unknown, online, offline }

class TvProvider extends ChangeNotifier {
    static const String _keyIp = 'tv_ip';
    static const String _keyMac = 'tv_mac';
    static const Duration _pollInterval = Duration(seconds: 10);

    TvConfig _config = const TvConfig(ip: '', mac: '');
    TvStatus _status = TvStatus.unknown;
    bool _busy = false;
    bool _initialized = false;
    String? _error;
    Timer? _pollTimer;

    TvConfig get config => _config;
    TvStatus get status => _status;
    bool get busy => _busy;
    bool get initialized => _initialized;
    String? get error => _error;

    SamsungTvClient get _client => SamsungTvClient(ip: _config.ip, mac: _config.mac);

    Future<void> init() async {
        final prefs = await SharedPreferences.getInstance();
        _config = TvConfig(
            ip: prefs.getString(_keyIp) ?? '',
            mac: prefs.getString(_keyMac) ?? '',
        );
        _initialized = true;
        notifyListeners();
        if (_config.isConfigured) {
            await checkStatus();
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
        notifyListeners();
    }

    Future<void> togglePower() async {
        if (!_config.isConfigured || _busy) return;
        _busy = true;
        _error = null;
        notifyListeners();
        try {
            if (_status == TvStatus.online) {
                await _client.sendKey('KEY_POWER');
                // Assume off; next poll will verify
                _status = TvStatus.offline;
            } else {
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
