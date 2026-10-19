import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'proximity.dart';

class PortalVoiceController extends ChangeNotifier {
  Room? _room;
  EventsListener<RoomEvent>? _events;
  HttpServer? _bridge;
  Timer? _clock;
  final _remote = <String, VoicePosition>{};
  final _requested = <String, bool>{};
  bool connected = false;
  bool busy = false;
  bool microphone = false;
  bool demo = false;
  double demoX = 0;
  double radius = 32;
  String status = 'Disconnected';
  VoicePosition? own;
  String bridgeKey = List<int>.generate(
    20, (_) => Random.secure().nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<RemoteParticipant> get peers =>
      _room?.remoteParticipants.values.toList() ?? <RemoteParticipant>[];

  VoicePosition? peerPosition(String identity) => _remote[identity];

  double? distance(String identity) {
    final other = _remote[identity], me = own;
    if (other == null || me == null) return null;
    if (!me.isFresh(DateTime.now()) || !other.isFresh(DateTime.now())) return null;
    return me.distanceTo(other);
  }

  bool audible(String identity) =>
      shouldHear(own, _remote[identity], radius: radius);

  void setRadius(double value) {
    radius = value;
    _applyProximity();
    notifyListeners();
  }

  void setDemo(bool value) {
    demo = value;
    own = value ? VoicePosition(demoX, 64, 0, 'minecraft:overworld', DateTime.now()) : null;
    _applyProximity();
    notifyListeners();
    unawaited(_broadcastPosition());
  }

  void setDemoX(double value) {
    demoX = value;
    if (demo) {
      own = VoicePosition(demoX, 64, 0, 'minecraft:overworld', DateTime.now());
      _applyProximity();
      notifyListeners();
      unawaited(_broadcastPosition());
    }
  }

  Future<void> connect({
    required String endpoint,
    required String roomName,
    required String playerName,
    required String password,
  }) async {
    if (busy || connected) return;
    busy = true;
    status = 'Connecting…';
    notifyListeners();
    try {
      final api = Uri.parse(endpoint.trim());
      final local = api.host == 'localhost' || api.host == '127.0.0.1';
      if (api.scheme != 'https' && !(api.scheme == 'http' && local)) {
        throw const FormatException('Token service requires HTTPS (localhost can use HTTP).');
      }
      if (roomName.trim().isEmpty || playerName.trim().isEmpty || password.isEmpty) {
        throw const FormatException('Room, player and room password are required.');
      }
      if (Platform.isAndroid) {
        if (!await Permission.microphone.request().isGranted) {
          throw StateError('Microphone permission denied.');
        }
        final ready = await FlutterBackground.initialize(
          androidConfig: const FlutterBackgroundAndroidConfig(
            notificationTitle: 'Portal Voice',
            notificationText: 'Voice chat is running while Minecraft is open',
            notificationImportance: AndroidNotificationImportance.normal,
          ),
        );
        if (!ready || !await FlutterBackground.enableBackgroundExecution()) {
          throw StateError('Android background microphone service could not start.');
        }
      }
      // Only the local device may submit trusted position updates to this socket.
      // The random secret prevents arbitrary localhost applications from writing data.
      _bridge = await HttpServer.bind(InternetAddress.loopbackIPv4, 43128);
      _bridge!.listen(_handleBridgeRequest);
      final response = await http.post(
        api.resolve('/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'room': roomName.trim(), 'name': playerName.trim(), 'password': password}),
      ).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw StateError('Token service returned ' + response.statusCode.toString() +
            ': ' + (payload['error']?.toString() ?? 'unknown'));
      }
      final url = payload['url']?.toString() ?? '';
      final token = payload['token']?.toString() ?? '';
      if (!url.startsWith('wss://') || token.isEmpty) {
        throw StateError('Invalid LiveKit connection details.');
      }
      final room = Room();
      _room = room;
      _events = room.createListener()
        ..on<DataReceivedEvent>((e) {
          if (e.topic != 'portal.position.v1' || e.participant == null) return;
          try {
            final parsed = VoicePosition.fromJson(jsonDecode(utf8.decode(e.data)));
            if (parsed != null) {
              _remote[e.participant!.identity] = parsed;
              _applyProximity();
              notifyListeners();
            }
          } catch (_) { /* Malformed remote position is discarded. */ }
        })
        ..on<ParticipantConnectedEvent>((_) { _applyProximity(); notifyListeners(); })
        ..on<ParticipantDisconnectedEvent>((e) {
          _remote.remove(e.participant.identity);
          _requested.clear();
          notifyListeners();
        })
        ..on<TrackPublishedEvent>((_) { _applyProximity(); notifyListeners(); })
        ..on<TrackSubscribedEvent>((_) { notifyListeners(); });
      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(false);
      microphone = false;
      connected = true;
      busy = false;
      status = 'Connected to ' + roomName.trim();
      _clock = Timer.periodic(const Duration(milliseconds: 850), (_) {
        if (demo) {
          own = VoicePosition(demoX, 64, 0, 'minecraft:overworld', DateTime.now());
        }
        _applyProximity();
        unawaited(_broadcastPosition());
        notifyListeners();
      });
      _applyProximity();
      unawaited(_broadcastPosition());
      notifyListeners();
    } catch (e) {
      await disconnect();
      status = 'Failed: ' + e.toString();
      busy = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setMicrophone(bool value) async {
    if (!connected) return;
    await _room?.localParticipant?.setMicrophoneEnabled(value);
    microphone = value;
    notifyListeners();
  }

  Future<void> _handleBridgeRequest(HttpRequest req) async {
    void reply(int statusCode, String body) {
      req.response.statusCode = statusCode;
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      unawaited(req.response.close());
    }
    if (req.method != 'POST' || req.uri.path != '/position') {
      reply(404, '{"error":"not_found"}');
      return;
    }
    if (req.headers.value('X-Portal-Key') != bridgeKey) {
      reply(403, '{"error":"forbidden"}');
      return;
    }
    if (req.contentLength > 2048) {
      reply(413, '{"error":"too_large"}');
      return;
    }
    try {
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > 2048) throw const FormatException('Body too large');
      }
      final pos = VoicePosition.fromJson(jsonDecode(utf8.decode(bytes)));
      if (pos == null) throw const FormatException('Invalid coordinate payload');
      demo = false;
      own = pos;
      _applyProximity();
      notifyListeners();
      unawaited(_broadcastPosition());
      reply(200, '{"ok":true}');
    } catch (_) {
      reply(400, '{"error":"invalid_position"}');
    }
  }

  Future<void> _broadcastPosition() async {
    final r = _room, p = own;
    if (!connected || r?.localParticipant == null || p == null ||
        !p.isFresh(DateTime.now())) return;
    try {
      await r!.localParticipant!.publishData(
        utf8.encode(jsonEncode(p.toJson())),
        reliable: false,
        topic: 'portal.position.v1',
      );
    } catch (_) { /* Room reconnection can interrupt a data packet. */ }
  }

  void _applyProximity() {
    final r = _room;
    if (r == null) return;
    for (final peer in r.remoteParticipants.values) {
      // Conservative default: missing or stale coordinates mean muted audio.
      final hear = audible(peer.identity);
      for (final publication in peer.audioTrackPublications) {
        final id = peer.identity + ':' + publication.sid;
        if (_requested[id] == hear) continue;
        _requested[id] = hear;
        if (hear) {
          unawaited(publication.subscribe().catchError((Object _) {}));
        } else {
          unawaited(publication.unsubscribe().catchError((Object _) {}));
        }
      }
    }
  }

  Future<void> disconnect() async {
    _clock?.cancel();
    _clock = null;
    final b = _bridge;
    _bridge = null;
    await b?.close(force: true);
    final listener = _events;
    _events = null;
    await listener?.dispose();
    final room = _room;
    _room = null;
    try { await room?.disconnect(); } catch (_) {}
    try { await room?.dispose(); } catch (_) {}
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      try { await FlutterBackground.disableBackgroundExecution(); } catch (_) {}
    }
    connected = false;
    microphone = false;
    busy = false;
    own = null;
    _remote.clear();
    _requested.clear();
    status = 'Disconnected';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
