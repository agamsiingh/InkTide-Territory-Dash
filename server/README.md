# InkTide room server

Real-time multiplayer for InkTide: Territory Dash. Players connect over
WebSocket, join a **public quick-play arena** or a **private friend room**
(4-letter code), and fight each other in real time. Empty seats are filled
with bots; bots step aside as more people join.

The server is **authoritative**: it runs the game's own simulation (the same
`lib/game/sim` code the app uses, imported directly, so rules can never drift
apart) at 30 Hz and sends snapshots at 15 Hz. Phones only send a steering
angle and draw what the server says, so they cannot cheat the result.

## Run it

```
cd server
dart run bin/server.dart            # PORT env var, default 8080
curl http://localhost:8080/health   # -> ok rooms=0 players=0
```

Single self-contained binary (no Dart needed on the host, ~7 MB):

```
cd server
dart compile exe bin/server.dart -o inktide_server
PORT=8080 ./inktide_server
```

`server/Dockerfile` builds the same thing as a tiny container (build from the
repo root; see the note in the file).

## Try it with a phone on your PC

```
adb reverse tcp:8080 tcp:8080
flutter run --release --dart-define=INKTIDE_SERVER=ws://127.0.0.1:8080
```

`dart run tool/remote_player.dart ws://127.0.0.1:8080 quick Robo` adds a
scripted second human to the public arena for testing.

## Put it on the internet

Players need a **wss://** address (TLS). Any host that runs a container or a
binary and supports WebSockets works (Fly.io, Render, Railway, Google Cloud
Run, a small VPS behind Caddy/nginx...). The server keeps everything in memory
and stores nothing on disk.

Measured with `dart run tool/bench_server.dart <rooms>` (8 humans per room,
simulation + snapshot encoding only, JIT mode, no real sockets):

| players | CPU per tick | share of one core | bandwidth |
|---|---|---|---|
| 200 | 0.4 ms | ~1% | ~6 KB/s per player |
| 400 | 0.8 ms | ~2% | ~6 KB/s per player |
| 800 | 1.5 ms | ~4% | ~6 KB/s per player |

CPU is not the limit. **Bandwidth and open connections are**: 800 players is
about 5 MB/s (40 Mbit/s) of outgoing traffic, and ~6 KB/s per player is roughly
23 MB per hour on a phone's mobile data (before WebSocket compression, which is
on by default and shrinks it further). This was NOT load-tested with that many
real sockets; do a staged test on your host before a big launch.

Then build the app pointing at it:

```
flutter build appbundle --release --dart-define=INKTIDE_SERVER=wss://play.yourdomain.com
```

Without that define the Online screen asks the player for a server address.

## Limits and abuse protection

- 4-letter room codes (no vowels, so no accidental words), 8 humans per room,
  200 rooms, 1500 connections (see `ServerConfig` in `lib/lobby.dart`).
- Input is validated: frames over 2 KB, malformed JSON, wrong types and
  non-finite angles are ignored; steering is rate-limited (40/s); sockets that
  never join a room are dropped after 10 s; the arena has 16 slots.
- Nicknames are cleaned (letters, digits, `_ - .` and spaces; 2-14 chars) and
  run through a small blocked-word filter. **It is a minimal filter, not
  moderation.** Add reporting/moderation before a large public launch.

## Known limits (be honest with yourself before launch)

- Identity is **not verified**: the server trusts the player id the app sends
  (Play Games id or a random guest id). That is fine for cosmetic nicknames
  but means nobody should get real rewards from the server. Verifying Play
  Games identity server-side needs your Google Cloud OAuth credentials.
- Wire format is JSON for easy debugging (~6 KB/s per player: trails are sent
  as appended points, the arena as changed cells). Switch to a binary format if
  bandwidth costs matter.
- No reconnect: if the connection drops, the player rejoins as a new player.
- Matchmaking is simple (fill the busiest public room). No skill or region
  matching.
