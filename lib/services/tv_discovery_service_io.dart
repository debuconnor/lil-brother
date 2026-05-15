import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/discovered_tv.dart';

void _log(String msg) => debugPrint('[TvDiscovery] $msg');

const String _ssdpAddr = '239.255.255.250';
const int _ssdpPort = 1900;

/// Fallback subnets to try when TV is not on the phone's own subnet.
/// Covers common home router defaults (192.168.0.x, 192.168.1.x, 10.0.0.x, etc.).
const List<String> _fallbackPrefixes = [
    '192.168.0', '192.168.1', '192.168.2', '192.168.100',
    '10.0.0', '10.0.1', '10.1.0',
];

const List<String> _searchTargets = [
    'urn:samsung.com:device:RemoteControlReceiver:1',
    'urn:dial-multiscreen-org:service:dial:1', // DIAL protocol — common across Samsung Smart TVs
    'upnp:rootdevice',
    'ssdp:all',
];

String _mSearch(String st) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: 3\r\n'
    'ST: $st\r\n'
    '\r\n';

/// Returns ALL non-cellular IPv4 interfaces on this device.
/// iOS: WiFi = en0, cellular = pdp_ip0/pdp_ip1/...
/// Also skips 192.0.0.0/24 (DS-Lite cellular NAT) and 100.64.0.0/10 (CGNAT).
Future<List<(InternetAddress, NetworkInterface)>> _allWifiAddresses() async {
    bool isCellular(NetworkInterface iface, InternetAddress addr) {
        if (iface.name.startsWith('pdp_ip') ||
            iface.name.startsWith('rmnet') ||
            iface.name.startsWith('ccmni')) return true;
        if (addr.address.startsWith('192.0.0.')) return true;
        final first = int.tryParse(addr.address.split('.')[0]) ?? 0;
        final second = int.tryParse(addr.address.split('.')[1]) ?? 0;
        if (first == 100 && second >= 64 && second <= 127) return true;
        return false;
    }

    final results = <(InternetAddress, NetworkInterface)>[];
    try {
        final interfaces = await NetworkInterface.list();
        _log('Network interfaces found: ${interfaces.length}');
        for (final iface in interfaces) {
            for (final addr in iface.addresses) {
                _log('  iface=${iface.name} addr=${addr.address} type=${addr.type} loopback=${addr.isLoopback}');
            }
        }

        // Pass 1: en* first (iOS primary WiFi)
        for (final iface in interfaces) {
            if (!iface.name.startsWith('en')) continue;
            for (final addr in iface.addresses) {
                if (addr.type == InternetAddressType.IPv4 &&
                    !addr.isLoopback &&
                    !addr.address.startsWith('169.254') &&
                    !isCellular(iface, addr)) {
                    _log('WiFi addr: ${addr.address} on ${iface.name} (en* pass)');
                    results.add((addr, iface));
                }
            }
        }

        // Pass 2: other non-cellular IPv4 (e.g., USB tethering, VPN)
        for (final iface in interfaces) {
            if (iface.name.startsWith('en')) continue; // already handled
            for (final addr in iface.addresses) {
                if (addr.type == InternetAddressType.IPv4 &&
                    !addr.isLoopback &&
                    !addr.address.startsWith('169.254') &&
                    !isCellular(iface, addr)) {
                    _log('WiFi addr: ${addr.address} on ${iface.name} (fallback pass)');
                    results.add((addr, iface));
                }
            }
        }

        if (results.isEmpty) _log('No suitable WiFi address found');
    } catch (e) {
        _log('_allWifiAddresses error: $e');
    }
    return results;
}

/// SSDP M-SEARCH via UDP multicast. Returns discovered IPs.
/// Joins the multicast group on the WiFi interface to stabilize reception on iOS.
Future<Set<String>> _ssdpDiscover((InternetAddress, NetworkInterface) bindInfo) async {
    final (bindAddr, iface) = bindInfo;
    final ips = <String>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;
    _log('SSDP: binding to ${bindAddr.address} on ${iface.name}');
    try {
        socket = await RawDatagramSocket.bind(bindAddr, 0);
        _log('SSDP: socket bound on port ${socket.port}');
        try {
            socket.joinMulticast(InternetAddress(_ssdpAddr), iface);
            _log('SSDP: joined multicast group $_ssdpAddr on ${iface.name}');
            socket.multicastHops = 4;
            socket.multicastLoopback = false;
        } catch (e) {
            _log('SSDP: multicast options warning (non-fatal): $e');
        }
        sub = socket.listen(
            (event) {
                if (event != RawSocketEvent.read) return;
                final dg = socket?.receive();
                if (dg == null) return;
                _log('SSDP: received response from ${dg.address.address}');
                ips.add(dg.address.address);
            },
            onError: (e) { _log('SSDP listen error: $e'); },
            cancelOnError: false,
        );
        final dest = InternetAddress(_ssdpAddr);
        for (final st in _searchTargets) {
            try {
                socket.send(utf8.encode(_mSearch(st)), dest, _ssdpPort);
                _log('SSDP: sent M-SEARCH ST=$st');
            } catch (e) {
                _log('SSDP: send error for ST=$st: $e');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        _log('SSDP: waiting 2s for responses...');
        await Future<void>.delayed(const Duration(seconds: 2));
        _log('SSDP: done, discovered IPs: $ips');
    } catch (e) {
        _log('SSDP: fatal error: $e');
    } finally {
        await sub?.cancel();
        socket?.close();
    }
    return ips;
}

/// Scans every host in a /24 subnet via HTTP.
/// [prefix] is the first 3 octets, e.g. '192.168.100'.
/// [perHostTimeout] controls per-IP timeout; use shorter value for fallback subnets.
Future<List<DiscoveredTv>> _subnetScan(
    String prefix, {
    Duration perHostTimeout = const Duration(milliseconds: 800),
}) async {
    _log('SubnetScan: scanning $prefix.1 - $prefix.254 (timeout=${perHostTimeout.inMilliseconds}ms)');
    final candidates = List.generate(254, (i) => '$prefix.${i + 1}');
    const batchSize = 50;
    final found = <DiscoveredTv>[];
    for (int i = 0; i < candidates.length; i += batchSize) {
        final batch = candidates.skip(i).take(batchSize).toList();
        _log('SubnetScan $prefix: batch ${i ~/ batchSize + 1} → ${batch.first}..${batch.last}');
        final results = await Future.wait(
            batch.map((ip) => fetchTvInfo(ip, timeout: perHostTimeout)),
        );
        found.addAll(results.whereType<DiscoveredTv>());
        if (found.isNotEmpty) {
            _log('SubnetScan $prefix: found TV(s): ${found.map((t) => t.ip).join(', ')}');
            break;
        }
    }
    if (found.isEmpty) _log('SubnetScan $prefix: no TVs found');
    return found;
}

/// Top-level discovery: SSDP + parallel subnet scans across all WiFi interfaces.
/// If nothing found on own subnets, tries common home router fallback subnets.
Future<List<DiscoveredTv>> discoverSamsungTvs() async {
    _log('discoverSamsungTvs: starting');

    // Retry up to 3× in case WiFi interface isn't ready at cold start
    List<(InternetAddress, NetworkInterface)> wifiInfos = [];
    for (int i = 0; i < 3 && wifiInfos.isEmpty; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(seconds: 1));
        wifiInfos = await _allWifiAddresses();
    }
    if (wifiInfos.isEmpty) {
        _log('discoverSamsungTvs: no WiFi address, aborting');
        return const [];
    }

    // Collect unique /24 prefixes from all WiFi interfaces
    final ownPrefixes = <String>{};
    for (final (addr, _) in wifiInfos) {
        final parts = addr.address.split('.');
        if (parts.length == 4) ownPrefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
    _log('discoverSamsungTvs: own subnets=${ownPrefixes.join(', ')}');

    // Run SSDP (on primary en0 interface) + own-subnet scans in parallel
    final primaryIface = wifiInfos.first;
    final ownScanFutures = ownPrefixes.map((p) => _subnetScan(p));

    final results = await Future.wait([
        _ssdpDiscover(primaryIface).then((ips) async {
            _log('SSDP done: ${ips.length} IPs → $ips');
            if (ips.isEmpty) return <DiscoveredTv>[];
            final fetched = await Future.wait(ips.map(fetchTvInfo));
            return fetched.whereType<DiscoveredTv>().toList();
        }),
        Future.wait(ownScanFutures).then((r) => r.expand((l) => l).toList()),
    ]);

    final found = [...results[0], ...results[1]];
    _log('discoverSamsungTvs: SSDP found ${results[0].length}, own-subnet found ${results[1].length}');
    if (found.isNotEmpty) return found;

    // Fallback: try common home router subnets not already scanned
    final fallbacks = _fallbackPrefixes.where((p) => !ownPrefixes.contains(p)).toList();
    if (fallbacks.isEmpty) return const [];
    _log('discoverSamsungTvs: nothing on own subnets, trying fallbacks: $fallbacks');

    for (final prefix in fallbacks) {
        final r = await _subnetScan(prefix, perHostTimeout: const Duration(milliseconds: 400));
        if (r.isNotEmpty) {
            _log('discoverSamsungTvs: found TVs in fallback subnet $prefix');
            return r;
        }
    }

    _log('discoverSamsungTvs: no TVs found in any subnet');
    return const [];
}

/// Fetches TV MAC and model name from a known IP via the Samsung REST API.
/// Tries both path variants: /api/v2/ (trailing slash) and /api/v2.
/// wifiMac may be empty on some firmware — falls back to device id (DUID).
Future<DiscoveredTv?> fetchTvInfo(String ip,
    {Duration timeout = const Duration(seconds: 3)}) async {
    // Try trailing-slash variant first — required by some Samsung firmware versions
    for (final path in ['/api/v2/', '/api/v2']) {
        try {
            final resp = await http
                .get(Uri.parse('http://$ip:8001$path'))
                .timeout(timeout);
            if (resp.statusCode == 200) {
                final data = jsonDecode(resp.body) as Map<String, dynamic>;
                final device = data['device'] as Map<String, dynamic>?;
                if (device == null) {
                    _log('fetchTvInfo $ip$path: no device field in response');
                    continue;
                }
                _log('fetchTvInfo $ip$path: OK — modelName=${device['modelName']}, wifiMac=${device['wifiMac']}, id=${device['id']}');
                final rawMac = device['wifiMac'] as String? ?? '';
                final mac = rawMac.isNotEmpty
                    ? rawMac.replaceAll('-', ':').toUpperCase()
                    : (device['id'] as String? ?? ip);
                final model = device['modelName'] as String? ?? ip;
                return DiscoveredTv(ip: ip, mac: mac, name: model, modelName: model);
            }
            // Log failure with body for diagnostics (first 300 chars)
            final bodySnippet = resp.body.length > 300
                ? '${resp.body.substring(0, 300)}...'
                : resp.body;
            _log('fetchTvInfo $ip$path: HTTP ${resp.statusCode} — $bodySnippet');
        } catch (e) {
            // Only log non-trivial errors (skip routine timeouts/refused for port scan noise)
            if (e is! TimeoutException) {
                _log('fetchTvInfo $ip$path error: $e');
            }
        }
    }
    return null;
}
