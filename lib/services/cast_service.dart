import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bonsoir/bonsoir.dart';

class CastDevice {
  final String name;
  final String host;
  final int port;
  CastDevice({required this.name, required this.host, required this.port});
}

class CastService {
  SecureSocket? _socket;
  int _requestId = 0;

  Future<List<CastDevice>> discoverDevices({Duration timeout = const Duration(seconds: 5)}) async {
    final results = <CastDevice>[];
    try {
      print('[Cast] Searching for devices...');
      final discovery = BonsoirDiscovery(type: '_googlecast._tcp');
      await discovery.initialize();

      discovery.eventStream!.listen((event) async {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          discovery.serviceResolver.resolveService(event.service);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final service = event.service;
          final rawHost = service.toJson()['service.ip'] ?? service.toJson()['service.host'];
          final port = service.port;
          final fn = service.attributes['fn'] ?? service.name;
          final md = service.attributes['md'] ?? '';
          final name = md.isNotEmpty ? '$md - $fn' : fn;

          if (rawHost != null && port > 0) {
            String host = rawHost.toString();
            if (host.endsWith('.local')) {
              try {
                final addrs = await InternetAddress.lookup(host);
                // Prefer IPv4
                final ipv4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
                host = ipv4.isNotEmpty ? ipv4.first.address : addrs.first.address;
              } catch (_) {
                return;
              }
            }
            // Skip IPv6 addresses
            if (host.contains(':')) return;
            print('[Cast]   Found: $name ($host:$port)');
            results.add(CastDevice(name: name, host: host, port: port));
          }
        }
      });

      await discovery.start();
      await Future.delayed(timeout);
      await discovery.stop();
      print('[Cast] Found ${results.length} devices');
    } catch (e) {
      print('[Cast] Discovery error: $e');
    }
    return results;
  }

  /// Cast a YouTube video using the Cast V2 protocol over TLS
  Future<bool> castYouTubeVideo(CastDevice device, String videoId) async {
    try {
      print('[Cast] Connecting to ${device.name} (${device.host}:${device.port}) via Cast V2...');

      // Connect via TLS (Cast V2 uses port 8009 with self-signed certs)
      _socket = await SecureSocket.connect(
        device.host,
        device.port,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 10),
      );

      _requestId = 0;

      // Step 1: Connect to receiver
      _sendCastMessage('sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.tp.connection', {'type': 'CONNECT'});

      // Step 2: Get current status
      await Future.delayed(const Duration(milliseconds: 500));
      _sendCastMessage('sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.receiver', {
        'type': 'GET_STATUS',
        'requestId': ++_requestId,
      });

      // Step 3: Launch YouTube app
      await Future.delayed(const Duration(milliseconds: 500));
      _sendCastMessage('sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.receiver', {
        'type': 'LAUNCH',
        'appId': '233637DE',
        'requestId': ++_requestId,
      });

      // Step 4: Wait for YouTube to load, then request status again to get its transportId
      await Future.delayed(const Duration(seconds: 5));
      _sendCastMessage('sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.receiver', {
        'type': 'GET_STATUS',
        'requestId': ++_requestId,
      });

      // Step 3: Wait for YouTube app to load, then send video
      final completer = Completer<bool>();
      String? transportId;

      // Accumulate data across TCP packets
      final accumulator = BytesBuilder();

      _socket!.listen((data) {
        accumulator.add(data);
        final allBytes = accumulator.toBytes();
        final str = utf8.decode(allBytes, allowMalformed: true);

        // Respond to PING immediately
        if (str.contains('"type":"PING"')) {
          _sendCastMessage('sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.tp.heartbeat', {'type': 'PONG'});
        }

        // Look for transportId in the accumulated data
        if (transportId == null) {
          // Extract only printable ASCII + common JSON chars
          final printable = str.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');

          // Log when we see YouTube app
          if (printable.contains('233637DE')) {
            print('[Cast] Found YouTube app in stream!');
            // Find transportId near the YouTube appId
            final around = RegExp(r'transportId[^a-zA-Z0-9_-]*([\w-]+)');
            final allTids = around.allMatches(printable);
            for (final m in allTids) {
              print('[Cast] transportId candidate: ${m.group(1)}');
            }
          }

          // Try multiple patterns to find transportId
          final tidPattern = RegExp(r'"transportId"\s*:\s*"([^"]+)"');
          final tidMatch = tidPattern.firstMatch(printable);

          if (tidMatch != null && printable.contains('233637DE')) {
            // Find transportId specifically associated with YouTube (233637DE)
            // Look for transportId that appears AFTER 233637DE in the text
            final ytIndex = printable.indexOf('233637DE');
            final afterYt = printable.substring(ytIndex);
            final ytTidMatch = tidPattern.firstMatch(afterYt);

            if (ytTidMatch != null) {
              transportId = ytTidMatch.group(1);
              print('[Cast] >>> YouTube transportId: $transportId');
            } else {
              // Fallback — use last transportId (YouTube is last app)
              final allTids = tidPattern.allMatches(printable).map((m) => m.group(1)!).toList();
              print('[Cast] All transportIds: $allTids');
              transportId = allTids.last;
              print('[Cast] >>> Using last transportId: $transportId');
            }
          }

          if (transportId != null) {
            // Connect to the YouTube app transport
            _sendCastMessage('sender-0', transportId!, 'urn:x-cast:com.google.cast.tp.connection', {'type': 'CONNECT'});

            // Send video after a delay
            Future.delayed(const Duration(seconds: 2), () {
              print('[Cast] Sending video $videoId to transport $transportId');

              // YouTube MDX fling
              _sendCastMessage('sender-0', transportId!, 'urn:x-cast:com.google.youtube.mdx', {
                'type': 'flingVideo',
                'data': {
                  'currentTime': 0,
                  'videoId': videoId,
                },
              });

              // Standard media LOAD
              _sendCastMessage('sender-0', transportId!, 'urn:x-cast:com.google.cast.media', {
                'type': 'LOAD',
                'requestId': ++_requestId,
                'autoplay': true,
                'currentTime': 0,
                'media': {
                  'contentId': videoId,
                  'contentType': 'x-youtube/video',
                  'streamType': 'BUFFERED',
                },
              });

              if (!completer.isCompleted) completer.complete(true);
            });

            // Clear accumulator since we found what we need
            accumulator.clear();
          }
        }
      }, onError: (e) {
        print('[Cast] Socket error: $e');
        if (!completer.isCompleted) completer.complete(false);
      }, onDone: () {
        print('[Cast] Socket closed');
        if (!completer.isCompleted) completer.complete(false);
      });

      return await completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          print('[Cast] Timeout');
          return false;
        },
      );
    } catch (e) {
      print('[Cast] Error: $e');
      return false;
    }
  }

  void _sendCastMessage(String sourceId, String destinationId, String namespace, Map<String, dynamic> payload) {
    if (_socket == null) return;

    final payloadStr = jsonEncode(payload);

    // Cast V2 protobuf message format (simplified)
    // Protocol version (0), source, dest, namespace, payload type (0=string), payload
    final msg = _buildCastMessage(sourceId, destinationId, namespace, payloadStr);

    // Length prefix (4 bytes big-endian)
    final lenBytes = ByteData(4)..setUint32(0, msg.length, Endian.big);
    _socket!.add(lenBytes.buffer.asUint8List());
    _socket!.add(msg);

    print('[Cast] Sent: $namespace -> ${payload['type']}');
  }

  Uint8List _buildCastMessage(String sourceId, String destId, String namespace, String payload) {
    // Simplified protobuf encoding for CastMessage
    final buf = BytesBuilder();

    // Field 1: protocol_version (varint) = 0 (CASTV2_1_0)
    buf.addByte(0x08); buf.addByte(0x00);
    // Field 2: source_id (string)
    buf.addByte(0x12); _writeString(buf, sourceId);
    // Field 3: destination_id (string)
    buf.addByte(0x1a); _writeString(buf, destId);
    // Field 4: namespace (string)
    buf.addByte(0x22); _writeString(buf, namespace);
    // Field 5: payload_type (varint) = 0 (STRING)
    buf.addByte(0x28); buf.addByte(0x00);
    // Field 6: payload_utf8 (string)
    buf.addByte(0x32); _writeString(buf, payload);

    return buf.toBytes();
  }

  void _writeString(BytesBuilder buf, String str) {
    final bytes = utf8.encode(str);
    _writeVarint(buf, bytes.length);
    buf.add(bytes);
  }

  void _writeVarint(BytesBuilder buf, int value) {
    while (value > 0x7F) {
      buf.addByte((value & 0x7F) | 0x80);
      value >>= 7;
    }
    buf.addByte(value & 0x7F);
  }

  Future<void> disconnect() async {
    try { _socket?.close(); } catch (_) {}
    _socket = null;
  }
}
