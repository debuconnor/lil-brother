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
    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<TvDiscoveryProvider>().scan();
        });
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
                                        'SSDP로 삼성 TV를 탐색 중...',
                                        style: TextStyle(color: Colors.white54),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                        '최대 3초 소요',
                                        style: TextStyle(color: Colors.white30, fontSize: 12),
                                    ),
                                ],
                            ),
                        );
                    }

                    if (discovery.results.isEmpty) {
                        return Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                    const SizedBox(height: 28),
                                    OutlinedButton.icon(
                                        icon: const Icon(Icons.wifi_find_rounded),
                                        label: const Text('다시 탐색'),
                                        onPressed: () => discovery.scan(),
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
