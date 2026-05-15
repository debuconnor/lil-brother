import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_tv.dart';
import '../models/tv_config.dart';
import '../providers/tv_discovery_provider.dart';
import '../providers/tv_provider.dart';

class TvScanScreen extends StatefulWidget {
    const TvScanScreen({super.key});

    @override
    State<TvScanScreen> createState() => _TvScanScreenState();
}

class _TvScanScreenState extends State<TvScanScreen> {
    final _ipController = TextEditingController();
    bool _manualLoading = false;

    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<TvDiscoveryProvider>().scan();
        });
    }

    @override
    void dispose() {
        _ipController.dispose();
        super.dispose();
    }

    Future<void> _connectManual(BuildContext context) async {
        final ip = _ipController.text.trim();
        if (ip.isEmpty) return;
        setState(() => _manualLoading = true);
        try {
            final tv = await context.read<TvDiscoveryProvider>().fetchFromIp(ip);
            if (!mounted) return;
            if (tv != null) {
                await context.read<TvProvider>().saveConfig(
                    TvConfig(ip: tv.ip, mac: tv.mac),
                );
                if (mounted) Navigator.pop(context);
            } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('해당 IP에서 삼성 TV를 찾지 못했습니다')),
                );
            }
        } finally {
            if (mounted) setState(() => _manualLoading = false);
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('주변 TV 탐색'),
                backgroundColor: const Color(0xFF16213E),
                actions: [
                    Consumer<TvDiscoveryProvider>(
                        builder: (_, discovery, __) => IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: '다시 탐색',
                            onPressed: discovery.scanning ? null : () => discovery.scan(),
                        ),
                    ),
                ],
            ),
            body: Consumer<TvDiscoveryProvider>(
                builder: (context, discovery, _) {
                    if (discovery.scanning) {
                        return const Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 20),
                                    Text(
                                        '삼성 TV 탐색 중...',
                                        style: TextStyle(color: Colors.white54),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                        'SSDP → 서브넷 스캔 순서로 탐색합니다',
                                        style: TextStyle(color: Colors.white30, fontSize: 12),
                                    ),
                                ],
                            ),
                        );
                    }

                    if (discovery.results.isEmpty) {
                        return SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    const SizedBox(height: 40),
                                    const Icon(Icons.tv_off_rounded, size: 56, color: Colors.white24),
                                    const SizedBox(height: 16),
                                    Text(
                                        discovery.error ?? '탐색 결과 없음',
                                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                                        textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'TV가 같은 와이파이에 연결되어 있는지 확인하세요',
                                        style: TextStyle(color: Colors.white30, fontSize: 12),
                                        textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                        '계속 안 된다면: Settings → lil-brother → Local Network 권한을 확인하세요',
                                        style: TextStyle(color: Colors.white24, fontSize: 11),
                                        textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 28),
                                    OutlinedButton.icon(
                                        icon: const Icon(Icons.wifi_find_rounded),
                                        label: const Text('다시 탐색'),
                                        onPressed: () => discovery.scan(),
                                    ),
                                    const SizedBox(height: 40),
                                    const Divider(color: Colors.white12),
                                    const SizedBox(height: 20),
                                    const Text(
                                        'TV IP 직접 입력',
                                        style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                        controller: _ipController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: const InputDecoration(
                                            hintText: '예: 192.168.1.100',
                                            hintStyle: TextStyle(color: Colors.white24),
                                            enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(color: Colors.white24),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide(color: Colors.greenAccent),
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                            onPressed: _manualLoading ? null : () => _connectManual(context),
                                            child: _manualLoading
                                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                                : const Text('연결'),
                                        ),
                                    ),
                                ],
                            ),
                        );
                    }

                    return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: discovery.results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                            final tv = discovery.results[i];
                            return _TvTile(
                                tv: tv,
                                onTap: () async {
                                    await context.read<TvProvider>().saveConfig(
                                        TvConfig(ip: tv.ip, mac: tv.mac),
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                },
                            );
                        },
                    );
                },
            ),
        );
    }
}

class _TvTile extends StatelessWidget {
    const _TvTile({required this.tv, required this.onTap});

    final DiscoveredTv tv;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context) {
        return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF16213E),
                    border: Border.all(color: Colors.white12),
                ),
                child: Row(
                    children: [
                        const Icon(Icons.tv_rounded, color: Colors.greenAccent, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(
                                        tv.modelName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                        ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        tv.ip,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    Text(
                                        tv.mac,
                                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                                    ),
                                ],
                            ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                    ],
                ),
            ),
        );
    }
}
