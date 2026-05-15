// Web stub — UDP broadcast is not available in browser environments.
// Imported by default on web; wol_service_io.dart is used on native platforms.
Future<void> sendWakeOnLan(String mac) {
    return Future.error(
        UnsupportedError('Wake-on-LAN은 모바일 앱에서만 지원됩니다 (웹 미지원)'),
    );
}
