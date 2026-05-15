class TvConfig {
    final String ip;
    final String mac;

    const TvConfig({required this.ip, required this.mac});

    bool get isConfigured => ip.isNotEmpty && mac.isNotEmpty;

    TvConfig copyWith({String? ip, String? mac}) => TvConfig(
        ip: ip ?? this.ip,
        mac: mac ?? this.mac,
    );
}
