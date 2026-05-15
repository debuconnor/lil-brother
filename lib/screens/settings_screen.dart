import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tv_config.dart';
import '../providers/tv_discovery_provider.dart';
import '../providers/tv_provider.dart';
import '../services/samsung_tv_client.dart';
import 'tv_scan_screen.dart';

class SettingsScreen extends StatefulWidget {
    const SettingsScreen({super.key});

    @override
    State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
    late final TextEditingController _ipCtrl;
    late final TextEditingController _macCtrl;
    final _formKey = GlobalKey<FormState>();
    bool _fetchingMac = false;

    @override
    void initState() {
        super.initState();
        final config = context.read<TvProvider>().config;
        _ipCtrl = TextEditingController(text: config.ip);
        _macCtrl = TextEditingController(text: config.mac);
    }

    @override
    void dispose() {
        _ipCtrl.dispose();
        _macCtrl.dispose();
        super.dispose();
    }

    void _resetPairing() {
        final ip = _ipCtrl.text.trim();
        if (ip.isNotEmpty) SamsungTvClient.clearToken(ip);
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                title: const Text('페어링 초기화'),
                content: const Text(
                    '앱 연결 기록을 초기화했습니다.\n\n'
                    'TV에서 확인 창이 뜨지 않는다면 삼성 TV에서 직접 삭제하세요:\n\n'
                    '설정 → 일반 → 외부 장치 관리자 → 기기 연결 관리자 → '
                    '기기 목록 → lil-brother 삭제',
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('확인'),
                    ),
                ],
            ),
        );
    }

    /// Opens TV scan screen. TvScanScreen saves config directly on selection;
    /// close settings automatically if a TV was successfully configured.
    Future<void> _openScan() async {
        await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TvScanScreen()),
        );
        if (mounted && context.read<TvProvider>().config.isConfigured) {
            Navigator.pop(context);
        }
    }

    /// Fetches MAC from a TV that is already on and reachable by IP.
    Future<void> _fetchMacFromIp() async {
        final ip = _ipCtrl.text.trim();
        if (ip.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('IP 주소를 먼저 입력하세요')),
            );
            return;
        }
        setState(() => _fetchingMac = true);
        final tv = await context.read<TvDiscoveryProvider>().fetchFromIp(ip);
        if (!mounted) return;
        setState(() => _fetchingMac = false);
        if (tv != null) {
            _macCtrl.text = tv.mac;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('MAC 가져오기 성공: ${tv.mac}')),
            );
        } else {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('TV 응답 없음 — TV가 켜져 있고 IP가 올바른지 확인하세요'),
                ),
            );
        }
    }

    Future<void> _save() async {
        if (!_formKey.currentState!.validate()) return;
        await context.read<TvProvider>().saveConfig(
            TvConfig(ip: _ipCtrl.text.trim(), mac: _macCtrl.text.trim()),
        );
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('저장 완료'),
                    duration: Duration(seconds: 2),
                ),
            );
            Navigator.pop(context);
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('TV 설정'),
                backgroundColor: const Color(0xFF16213E),
            ),
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                    key: _formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            // Native: full SSDP scan button
                            if (!kIsWeb)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: OutlinedButton.icon(
                                            icon: const Icon(Icons.wifi_find_rounded),
                                            label: const Text('주변 TV 자동 탐색'),
                                            onPressed: _openScan,
                                        ),
                                    ),
                                ),
                            if (!kIsWeb)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: OutlinedButton.icon(
                                            icon: const Icon(Icons.link_off_rounded),
                                            label: const Text('페어링 초기화'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.orangeAccent,
                                                side: const BorderSide(color: Colors.orangeAccent),
                                            ),
                                            onPressed: _resetPairing,
                                        ),
                                    ),
                                ),
                            if (kIsWeb)
                                Container(
                                    margin: const EdgeInsets.only(bottom: 20),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        border: Border.all(color: Colors.orangeAccent),
                                        borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                        children: [
                                            Icon(Icons.warning_amber_rounded,
                                                color: Colors.orangeAccent, size: 18),
                                            SizedBox(width: 8),
                                            Expanded(
                                                child: Text(
                                                    '웹에서는 전원 켜기(WOL)가 지원되지 않습니다.\n전원 끄기 및 리모컨 키는 사용 가능합니다.',
                                                    style: TextStyle(
                                                        color: Colors.orangeAccent,
                                                        fontSize: 12,
                                                    ),
                                                ),
                                            ),
                                        ],
                                    ),
                                ),
                            const Text(
                                'TV IP 주소',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                                controller: _ipCtrl,
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                ),
                                decoration: const InputDecoration(
                                    hintText: '예: 192.168.0.100',
                                    filled: true,
                                    fillColor: Color(0xFF16213E),
                                    border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                        return 'IP 주소를 입력하세요';
                                    }
                                    final parts = v.trim().split('.');
                                    if (parts.length != 4) {
                                        return '올바른 IP 형식이 아닙니다 (예: 192.168.0.100)';
                                    }
                                    return null;
                                },
                            ),
                            const SizedBox(height: 24),
                            const Text(
                                'TV MAC 주소',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                                controller: _macCtrl,
                                keyboardType: TextInputType.text,
                                decoration: const InputDecoration(
                                    hintText: '예: AA:BB:CC:DD:EE:FF',
                                    filled: true,
                                    fillColor: Color(0xFF16213E),
                                    border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                    if (v == null || v.trim().isEmpty) return null; // optional
                                    final parts = v.trim().split(RegExp(r'[:\-]'));
                                    if (parts.length != 6) {
                                        return 'AA:BB:CC:DD:EE:FF 형식으로 입력하세요';
                                    }
                                    return null;
                                },
                            ),
                            const SizedBox(height: 8),
                            const Text(
                                'MAC 주소 확인: TV 설정 → 일반 → 네트워크 → 네트워크 상태',
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            // Fetch MAC automatically from TV REST API (works if TV is on)
                            SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: OutlinedButton.icon(
                                    icon: _fetchingMac
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                        : const Icon(Icons.download_rounded, size: 18),
                                    label: const Text('IP로 MAC 자동 가져오기'),
                                    onPressed: _fetchingMac ? null : _fetchMacFromIp,
                                ),
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                    onPressed: _save,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.greenAccent,
                                        foregroundColor: Colors.black,
                                    ),
                                    child: const Text(
                                        '저장',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                        ),
                                    ),
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }
}
