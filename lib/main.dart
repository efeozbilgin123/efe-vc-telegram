import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'voice_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiveKitClient.initialize();
  runApp(const PortalVoiceApp());
}

class PortalVoiceApp extends StatelessWidget {
  const PortalVoiceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Portal Voice',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF48CCB8),
        brightness: Brightness.dark,
        surface: const Color(0xFF0E1622),
      ),
      scaffoldBackgroundColor: const Color(0xFF080E17),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
    home: const VoiceHome(),
  );
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key});
  @override
  State<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  final voice = PortalVoiceController();
  final endpoint = TextEditingController();
  final room = TextEditingController(text: 'realm-friends');
  final name = TextEditingController();
  final passphrase = TextEditingController();

  @override
  void dispose() {
    unawaited(voice.disconnect());
    voice.dispose();
    endpoint.dispose();
    room.dispose();
    name.dispose();
    passphrase.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await voice.connect(
        endpoint: endpoint.text,
        roomName: room.text,
        playerName: name.text,
        password: passphrase.text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF8E3441),
        ));
      }
    }
  }

  Future<void> _microphone(bool enable) async {
    try {
      await voice.setMicrophone(enable);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Microphone error: ' + e.toString())));
    }
  }

  Widget _group(String heading, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    color: const Color(0xFF101D2A),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(heading, style: const TextStyle(
          fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        child,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: voice,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.graphic_eq, color: Color(0xFF48CCB8)),
          SizedBox(width: 10),
          Text('Portal Voice', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: const Color(0xFF0D1723),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('0.2.0 PREVIEW', style: TextStyle(fontSize: 11))),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            _group('CONNECTION', Column(children: [
              TextField(
                controller: endpoint,
                enabled: !voice.connected && !voice.busy,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Token server URL (HTTPS)',
                  hintText: 'https://your-voice-token-server.example',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: room,
                enabled: !voice.connected && !voice.busy,
                decoration: const InputDecoration(
                  labelText: 'Voice room', prefixIcon: Icon(Icons.meeting_room_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                enabled: !voice.connected && !voice.busy,
                decoration: const InputDecoration(
                  labelText: 'Minecraft name', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passphrase,
                obscureText: true,
                enabled: !voice.connected && !voice.busy,
                decoration: const InputDecoration(
                  labelText: 'Voice room passphrase', prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Icon(
                  voice.connected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: voice.connected ? const Color(0xFF48CCB8) : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(voice.status)),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: voice.busy ? null :
                    (voice.connected ? () => unawaited(voice.disconnect()) : _connect),
                  icon: Icon(voice.connected ? Icons.stop : Icons.play_arrow),
                  label: Text(voice.connected ? 'Disconnect' : 'Connect'),
                ),
              ]),
            ])),
            _group('VOICE', Column(children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Microphone'),
                subtitle: const Text('Off by default. Voice never transmits until enabled.'),
                secondary: Icon(voice.microphone ? Icons.mic : Icons.mic_off),
                value: voice.microphone,
                onChanged: voice.connected ? (value) => unawaited(_microphone(value)) : null,
              ),
              Row(children: [
                const Icon(Icons.hearing_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Audible radius: ' +
                    voice.radius.round().toString() + ' blocks')),
              ]),
              Slider(
                value: voice.radius,
                min: 8, max: 96, divisions: 22,
                label: voice.radius.round().toString(),
                onChanged: voice.setRadius,
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Preview uses near/far voice gating, not smooth 3D audio panning.',
                  style: TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            ])),
            _group('POSITION SOURCE', Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Demo coordinates'),
                  subtitle: const Text('For testing two devices; not Minecraft tracking.'),
                  secondary: const Icon(Icons.tune),
                  value: voice.demo,
                  onChanged: voice.setDemo,
                ),
                if (voice.demo) ...[
                  Text('Test X coordinate: ' + voice.demoX.round().toString()),
                  Slider(
                    value: voice.demoX, min: -128, max: 128, divisions: 64,
                    label: voice.demoX.round().toString(),
                    onChanged: voice.setDemoX,
                  ),
                ],
                const Text(
                  'Real coordinates: Portal proxy must POST x/y/z/dimension to '
                  'the local bridge. Without fresh positions, audio is muted.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                const Text('Local endpoint: http://127.0.0.1:43128/position',
                  style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                const Text('Local bridge key', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 4),
                SelectableText(voice.bridgeKey, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12)),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: voice.bridgeKey));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bridge key copied')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy key'),
                  ),
                ),
                if (voice.own != null) Text(
                  'Current: ' +
                  voice.own!.dimension + ' / ' +
                  voice.own!.x.round().toString() + ', ' +
                  voice.own!.y.round().toString() + ', ' +
                  voice.own!.z.round().toString(),
                ),
              ],
            )),
            _group('PLAYERS (' + voice.peers.length.toString() + ')', Column(
              children: [
                if (voice.peers.isEmpty) const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No other voice clients connected.',
                    style: TextStyle(color: Colors.white60)),
                ),
                for (final peer in voice.peers)
                  ListTile(
                    leading: Icon(
                      voice.audible(peer.identity) ? Icons.volume_up : Icons.volume_off,
                      color: voice.audible(peer.identity)
                        ? const Color(0xFF48CCB8) : Colors.grey,
                    ),
                    title: Text(peer.name.isEmpty ? peer.identity : peer.name),
                    subtitle: Text(
                      voice.distance(peer.identity) == null
                        ? 'Unknown position / dimension'
                        : voice.distance(peer.identity)!.toStringAsFixed(1) + ' blocks away',
                    ),
                    trailing: Text(voice.audible(peer.identity) ? 'NEARBY' : 'MUTED',
                      style: const TextStyle(fontSize: 11)),
                  ),
              ],
            )),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Privacy: position packets go to participants in the same voice room. '
                'Never expose the local bridge port to the Internet.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
