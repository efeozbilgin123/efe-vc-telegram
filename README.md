# Portal Voice 0.2.0 — Android + Windows proof of concept

Cross-platform companion voice chat for Minecraft Java Realms / Bedrock via Portal.
This source is isolated on the portal-voice-0.2 branch of an existing repository.
The default branch was not changed.

## Implemented

- Android + Windows Flutter UI, using LiveKit WebRTC for microphone voice.
- Join a passphrase-protected room via a token service.
- Microphone OFF by default, explicitly enabled by a switch.
- Android foreground microphone service intended to maintain audio while
  switching to Minecraft (device power saving can still interrupt it).
- Player positions over data channel; Euclidean distance; dimension isolation.
- Unknown/stale positions older than 5 seconds are muted, 8–96 block radius.
- Demo coordinates for tests between two devices.
- Authenticated localhost HTTP position bridge for a future ViaProxy/Geyser adapter.

## Limitations

This is a standalone companion proof of concept, not a port of the Portal 0.1.6
APK. Realm login, Geyser engine and Minecraft packet-coordinate extraction are
NOT part of this preview. True in-game proximity requires Portal's proxy to feed
current coordinates. Until then use demo coordinates for voice tests.
The volume currently gates near/far, not gradual attenuation or 3D panning.
The voice backend (LiveKit Cloud or self-hosted) and HTTPS token server must
be configured. No APK/EXE has been hardware-tested by the assistant.

## Build

Requires Flutter stable (Dart 3.10+), Windows build tools and Android SDK as
needed. On this branch:

1. flutter create --platforms=android,windows --org dev.realmbridge .
2. python3 scripts/configure_android.py
3. flutter pub get
4. flutter test
5. flutter run -d windows   (or flutter run on a connected Android device)
6. flutter build windows --release OR flutter build apk --debug

GitHub Actions builds both platforms and publishes artifacts if CI succeeds.
On Windows distribute the whole build/windows/x64/runner/Release directory,
not just the EXE.

## Token service

Use a LiveKit Cloud project or self-host LiveKit. Configure the separate
token-server process with environment variables:

LIVEKIT_URL=wss://YOUR_LIVEKIT_HOST
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
PORTAL_ROOM_PASSWORD=strong_shared_passphrase_12_characters_minimum
PORT=8787

Then run cd token-server, npm install, npm start. Put it behind an HTTPS proxy
(e.g., Caddy). Enter its public HTTPS origin in both Portal Voice clients;
use the same room and shared passphrase. Never embed LiveKit secrets in apps.
GET /health returns service health.

## Two-device test (without Minecraft)

Connect from Windows and Android, both to the same room. Enable Demo
coordinates on each, set both X to 0. Turn both microphones on explicitly.
Move one demo X to 96: at radius 32 its remote audio stops. Set it to 0 again
to resubscribe. Switching worlds by the bridge will also mute.

## Portal 0.1.6 coordinate integration contract

The embedded Geyser/ViaProxy position adapter should send a request once per
second from the same device running Portal Voice:

POST http://127.0.0.1:43128/position
X-Portal-Key: copied from the Portal Voice UI
Content-Type: application/json

JSON body: {"x":123.5,"y":64,"z":-42.75,"dimension":"minecraft:overworld"}

Example PowerShell for Windows (replace KEY):
Invoke-RestMethod -Uri 'http://127.0.0.1:43128/position' -Method Post -Headers @{'X-Portal-Key'='KEY'} -ContentType 'application/json' -Body '{"x":0,"y":64,"z":0,"dimension":"minecraft:overworld"}'

The listener binds ONLY to loopback (127.0.0.1), not a public interface.
On Android the existing Portal process needs permission to send loopback
HTTP requests. Minecraft Realm server plugins are NOT necessary if both
clients' position adapters can read their positions.

## Privacy and risks

Position is relayed to everybody in the same voice room even if they are
outside hearing radius; do not join untrusted rooms. Local client reports
of positions are not anti-cheat-grade verified. A shared room secret is not
Microsoft/Minecraft authentication. LiveKit encrypts WebRTC transport but
this version does not implement application-level end-to-end encryption.
Use TLS, authentication, logging and anti-abuse controls for Internet hosting.


## Optional Geyser extension position adapter (experimental)

The geyser-extension folder contains a Java 21 extension. Build it with Gradle:

cd geyser-extension
gradle build

Place the produced JAR in the Geyser extensions folder and start the local
ViaProxy/Geyser engine once. A bridge.properties file is created under the
extension's data folder. Copy the Local Bridge Key from Portal Voice into
bridgeKey= in that properties file and restart the engine. The extension
polls the one local connected Bedrock player's position + dimension and sends
it to 127.0.0.1:43128. It fails closed if there are zero or multiple local
Bedrock players, or if Geyser changes its session dimension getter.

This extension has not been verified against the bundled Android Geyser
2.12.0 runtime. It is not automatically installed in Portal 0.1.6.
The current key is regenerated on each Portal Voice app launch; it must be
resynchronized until a safe shared configuration interface is implemented.
