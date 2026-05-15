import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tv_provider.dart';
import 'settings_screen.dart';
import 'tv_scan_screen.dart';

class HomeScreen extends StatefulWidget {
    const HomeScreen({super.key});

    @override
    State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
    bool _scanLaunched = false;

    @override
    Widget build(BuildContext context) {
        return Consumer<TvProvider>(
            builder: (context, tv, _) {
                // Auto-launch scan on first load when no TV is configured (native only)
                if (tv.initialized && !tv.config.isConfigured && !_scanLaunched && !kIsWeb) {
                    _scanLaunched = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const TvScanScreen()),
                            );
                        }
                    });
                }

                return Scaffold(
                    appBar: AppBar(
                        title: const Text(
                            'lil-brother',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: const Color(0xFF16213E),
                        actions: [
                            if (kIsWeb)
                                const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Center(
                                        child: Text(
                                            'WEB',
                                            style: TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                            ),
                                        ),
                                    ),
                                ),
                            IconButton(
                                icon: const Icon(Icons.settings_outlined),
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                                ),
                            ),
                        ],
                    ),
                    body: _buildBody(context, tv),
                );
            },
        );
    }

    Widget _buildBody(BuildContext context, TvProvider tv) {
        if (!tv.initialized) {
            return const Center(child: CircularProgressIndicator());
        }

        if (!tv.config.isConfigured) {
            return _NoTvView(
                onScan: kIsWeb
                    ? null
                    : () {
                        setState(() => _scanLaunched = false);
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TvScanScreen()),
                        ).then((_) => setState(() => _scanLaunched = true));
                    },
            );
        }

        return Column(
            children: [
                _StatusBanner(tv: tv),
                const Spacer(),
                _PowerButton(tv: tv),
                const SizedBox(height: 36),
                _DPadSection(tv: tv),
                const SizedBox(height: 24),
                _ControlRow(tv: tv),
                const SizedBox(height: 40),
            ],
        );
    }
}

class _NoTvView extends StatelessWidget {
    const _NoTvView({required this.onScan});

    final VoidCallback? onScan;

    @override
    Widget build(BuildContext context) {
        return Center(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    const Icon(Icons.tv_off_rounded, size: 72, color: Colors.white12),
                    const SizedBox(height: 20),
                    const Text(
                        '연결된 TV가 없습니다',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    if (onScan != null)
                        FilledButton.icon(
                            icon: const Icon(Icons.wifi_find_rounded),
                            label: const Text('주변 TV 탐색'),
                            onPressed: onScan,
                        )
                    else
                        const Text(
                            '설정(⚙)에서 IP와 MAC을 입력하세요',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                ],
            ),
        );
    }
}

class _StatusBanner extends StatelessWidget {
    const _StatusBanner({required this.tv});

    final TvProvider tv;

    @override
    Widget build(BuildContext context) {
        final (label, color) = switch (tv.status) {
            TvStatus.online => ('● ONLINE', Colors.greenAccent),
            TvStatus.offline => ('● OFFLINE', Colors.redAccent),
            TvStatus.unknown => ('● 확인 중...', Colors.grey),
        };

        return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
                children: [
                    Text(
                        tv.config.ip,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        label,
                        style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                        ),
                    ),
                    if (tv.error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
                            child: Text(
                                tv.error!.replaceFirst('Exception: ', ''),
                                style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                            ),
                        ),
                ],
            ),
        );
    }
}

class _PowerButton extends StatelessWidget {
    const _PowerButton({required this.tv});

    final TvProvider tv;

    Color get _glowColor => switch (tv.status) {
        TvStatus.online => Colors.greenAccent,
        TvStatus.offline => const Color(0xFF3A3A5C),
        TvStatus.unknown => Colors.grey,
    };

    @override
    Widget build(BuildContext context) {
        return GestureDetector(
            onTap: tv.busy ? null : () => context.read<TvProvider>().togglePower(),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16213E),
                    border: Border.all(color: _glowColor, width: 4),
                    boxShadow: [
                        BoxShadow(
                            color: _glowColor.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 4,
                        ),
                    ],
                ),
                child: tv.busy
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.power_settings_new_rounded, color: _glowColor, size: 72),
            ),
        );
    }
}

class _ControlRow extends StatelessWidget {
    const _ControlRow({required this.tv});

    final TvProvider tv;

    @override
    Widget build(BuildContext context) {
        return Column(
            children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        _RemoteBtn(
                            icon: Icons.volume_down_rounded,
                            label: 'VOL-',
                            keyCode: 'KEY_VOLDOWN',
                            tv: tv,
                        ),
                        const SizedBox(width: 16),
                        _RemoteBtn(
                            icon: Icons.volume_mute_rounded,
                            label: 'MUTE',
                            keyCode: 'KEY_MUTE',
                            tv: tv,
                        ),
                        const SizedBox(width: 16),
                        _RemoteBtn(
                            icon: Icons.volume_up_rounded,
                            label: 'VOL+',
                            keyCode: 'KEY_VOLUP',
                            tv: tv,
                        ),
                    ],
                ),
                const SizedBox(height: 20),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        _RemoteBtn(
                            icon: Icons.expand_more_rounded,
                            label: 'CH-',
                            keyCode: 'KEY_CHDOWN',
                            tv: tv,
                        ),
                        const SizedBox(width: 48),
                        _RemoteBtn(
                            icon: Icons.expand_less_rounded,
                            label: 'CH+',
                            keyCode: 'KEY_CHUP',
                            tv: tv,
                        ),
                    ],
                ),
            ],
        );
    }
}

class _RemoteBtn extends StatelessWidget {
    const _RemoteBtn({
        required this.icon,
        required this.label,
        required this.keyCode,
        required this.tv,
    });

    final IconData icon;
    final String label;
    final String keyCode;
    final TvProvider tv;

    @override
    Widget build(BuildContext context) {
        final enabled = tv.status == TvStatus.online && !tv.busy;
        return InkWell(
            onTap: enabled ? () => tv.sendKey(keyCode) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
                width: 80,
                height: 72,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF16213E),
                    border: Border.all(
                        color: enabled ? Colors.white24 : Colors.white12,
                    ),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(
                            icon,
                            color: enabled ? Colors.white70 : Colors.white30,
                            size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                            label,
                            style: TextStyle(
                                color: enabled ? Colors.white54 : Colors.white24,
                                fontSize: 11,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}

// ── D-Pad ────────────────────────────────────────────────────────────────────

class _DPadSection extends StatelessWidget {
    const _DPadSection({required this.tv});

    final TvProvider tv;

    @override
    Widget build(BuildContext context) {
        return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
                // Directional cross + OK
                Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        _DPadBtn(icon: Icons.keyboard_arrow_up_rounded, keyCode: 'KEY_UP', tv: tv),
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                _DPadBtn(
                                    icon: Icons.keyboard_arrow_left_rounded,
                                    keyCode: 'KEY_LEFT',
                                    tv: tv,
                                ),
                                _DPadBtn(label: 'OK', keyCode: 'KEY_ENTER', tv: tv),
                                _DPadBtn(
                                    icon: Icons.keyboard_arrow_right_rounded,
                                    keyCode: 'KEY_RIGHT',
                                    tv: tv,
                                ),
                            ],
                        ),
                        _DPadBtn(icon: Icons.keyboard_arrow_down_rounded, keyCode: 'KEY_DOWN', tv: tv),
                    ],
                ),
                const SizedBox(width: 24),
                // BACK sits to the right of the D-pad
                _RemoteBtn(
                    icon: Icons.arrow_back_rounded,
                    label: 'BACK',
                    keyCode: 'KEY_RETURN',
                    tv: tv,
                ),
            ],
        );
    }
}

class _DPadBtn extends StatelessWidget {
    const _DPadBtn({
        required this.keyCode,
        required this.tv,
        this.icon,
        this.label = '',
    });

    final IconData? icon;
    final String label;
    final String keyCode;
    final TvProvider tv;

    @override
    Widget build(BuildContext context) {
        final enabled = tv.status == TvStatus.online && !tv.busy;
        return Padding(
            padding: const EdgeInsets.all(3),
            child: InkWell(
                onTap: enabled ? () => tv.sendKey(keyCode) : null,
                borderRadius: BorderRadius.circular(32),
                child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF16213E),
                        border: Border.all(
                            color: enabled ? Colors.white24 : Colors.white12,
                        ),
                    ),
                    child: label.isNotEmpty
                        ? Center(
                            child: Text(
                                label,
                                style: TextStyle(
                                    color: enabled ? Colors.white70 : Colors.white30,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                ),
                            ),
                        )
                        : Icon(
                            icon,
                            color: enabled ? Colors.white70 : Colors.white30,
                            size: 26,
                        ),
                ),
            ),
        );
    }
}
