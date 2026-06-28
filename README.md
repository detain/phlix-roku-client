# Phlix Media Server - Roku Application

[![Lint](https://github.com/detain/phlix-roku-client/actions/workflows/lint.yml/badge.svg)](https://github.com/detain/phlix-roku-client/actions/workflows/lint.yml)
[![Tests](https://github.com/detain/phlix-roku-client/actions/workflows/test.yml/badge.svg)](https://github.com/detain/phlix-roku-client/actions/workflows/test.yml)
[![Package](https://github.com/detain/phlix-roku-client/actions/workflows/package.yml/badge.svg)](https://github.com/detain/phlix-roku-client/actions/workflows/package.yml)
![Platform](https://img.shields.io/badge/platform-Roku-662D91?logo=roku&logoColor=white)
![Language](https://img.shields.io/badge/BrightScript-SceneGraph-662D91)

A native Roku application for the Phlix Media Server platform. Stream your media library with full playback control, seamless authentication, and progress synchronization.

## Features

- **Secure Authentication**: Device registration with token-based session management
- **Library Browsing**: Browse movies, TV shows, and collections with intuitive navigation
- **HLS Video Playback**: Stream video content with adaptive bitrate support
- **Full Remote Control**: Complete playback control via Roku remote (play, pause, seek, stop)
- **Progress Synchronization**: Track and sync watch progress across sessions
- **Multiple User Support**: Personalized libraries and watch states per user
- **Hub / Multi-Server Mode**: Point the Connect screen at a Phlix Hub instead of a single server — after login the client detects the hub (`GET /api/v1/me/servers`), shows a server picker, and routes all media requests to the chosen server through the hub's relay proxy (the hub Bearer is the relay auth). See "Hub / multi-server mode" below for the known PUT/DELETE-over-relay limitation.
- **Skip Intro/Outro**: Automatically displayed skip buttons when playback enters marker ranges defined by the server (intro start/end, outro start/end)
- **SyncPlay / Watch Together** *(built to a not-yet-deployed server target; device-unverifiable — see the LIMITATIONS box under "SyncPlay (Watch Together)")*: a hand-rolled RFC6455 WebSocket client (`source/lib/SyncPlayProtocol.brs` + `components/SyncPlayTask.{xml,brs}`) lets several devices watch the same content in sync. Open the **Watch Together** overlay in the player (the `*`/Options key), pick a group from the list (or Create), and playback follows the host (play/pause/seek) with NTP-style drift correction. **Direct mode only** (disabled in hub mode), and **`ws://` only** because Roku's `roStreamSocket` has no TLS.
- **Profile Management (admin)**: View a user's profiles and adjust the parental-control rating or clear a forgotten PIN — button-driven, no keyboard. Reached via `Admin → Users → (select user) → Profiles`

## Prerequisites

### Required
- **Roku Device**: Any Roku device with developer mode enabled
- **Phlix Media Server**: Running instance accessible on your network
- **Roku Developer Account**: For sideloading apps

### Development Tools
- **Roku SDK**: For packaging and deployment ( rokupkg )
- **BrightScript Editor**: VS Code extension "BrightScript" by彩虹 (or any editor)
- **curl**: For direct device communication
- **zip**: For creating packages

### Network Requirements
- Roku device and Phlix Media Server on the same network
- Phlix Media Server API accessible from Roku device

## Installation

### 1. Enable Developer Mode on Roku

Press the following button sequence on your Roku remote:
1. Home (5 times)
2. Up (2 times)
3. Right (1 time)
4. Left (1 time)
5. Right (1 time)
6. Left (1 time)
7. Right (1 time)

Note the IP address shown and enable dev mode via the web interface at `http://<ROKU_IP>`.

### 2. Clone and Configure

```bash
# Clone the repository
git clone https://github.com/your-org/phlix-roku.git
cd phlix-roku

# Review and update manifest if needed
# Edit: manifest title, version, icons
```

### 3. Install Dependencies

No external dependencies required. BrightScript is natively supported by Roku devices.

### 4. Configure Server Connection

There is **nothing to pre-configure** — the server URL is entered in-app on first launch.

On first run (no `server_url` persisted yet) the boot flow shows a **Connect to server**
screen (`ConnectScene`):

1. Enter your server's address (a direct Phlix server **or** a Phlix Hub — both expose
   `/health` identically), e.g. `https://my.phlix.server` or `http://192.168.1.100:8096`.
2. Press **Connect**. The URL is normalized (a missing scheme is inferred — `http://` for
   LAN/loopback hosts, `https://` otherwise — and a trailing `/` is stripped) and probed
   via `GET {url}/health`.
3. On a healthy probe the URL is persisted to registry storage under `server_url` and the
   app proceeds to the login screen, then Home.
4. If the probe fails (server unreachable, or `/health` is blocked), an error is shown and
   a **Connect anyway** button appears — pressing it persists the entered URL and proceeds
   regardless.

On subsequent launches the persisted `server_url` is reused and the Connect screen is
skipped (boot goes straight to login or, if a session is restored, Home). The login screen
itself only collects username/password — it no longer has a server-URL field.

### 5. Hub / multi-server mode

The connect URL entered on the Connect screen can be **either a direct Phlix server or a
Phlix Hub** — they expose `/health` and `POST /api/v1/auth/login` identically, so the
connect + login flow is the same for both. The client decides which it is talking to
**after login**, transparently:

1. **Probe.** Immediately after a successful login the client calls
   `GET /api/v1/me/servers`.
   - A **hub** returns `{servers:[ … ]}` (camelCase rows). The client persists
     `connection_kind = "hub"` and routes to a new **server picker** screen
     (`ServerPickerScene`).
   - A **direct server** has no such route (404 / no `servers` array). The client persists
     `connection_kind = "direct"` and goes straight to Home, exactly as before. Direct mode
     is unchanged from F12a.
2. **Pick a server.** The picker lists each claimed server with its name, online/offline
   status, and library count. Selecting one persists `active_server_id` (and
   `active_server_name` for display) and proceeds to Home.
3. **Relay routing.** Once a server is picked, the media `ApiClient` is rebuilt against the
   hub's **relay proxy** base — `{hub}/api/v1/servers/{serverId}/proxy` — so every existing
   scene and background task transparently routes its requests through the hub to the chosen
   server with **no per-scene changes**. The **hub Bearer token is the relay auth**: the hub
   strips the client's `Authorization`/`Cookie` headers, verifies the logged-in user owns the
   target server (403 otherwise), injects `X-Phlix-Relay-User`, and tunnels the request over
   its WSS connection to the server, which trusts the tunnel. No separate per-server token is
   involved.
4. **Boot / session validation.** On a subsequent launch in hub mode the persisted **hub**
   session is validated against the **hub directly** (`GET /api/v1/auth/me` on the bare hub
   URL, not over the relay — `/auth/me` over the relay returns the hub-user perspective and is
   unreliable). If valid and a server is already picked → Home; if valid but no server picked →
   the server picker; otherwise → login. Logging out clears `connection_kind`,
   `active_server_id`, and `active_server_name` but keeps `server_url`, so you return to the
   login screen on the same hub/server.

#### Hub mode storage keys

| Key | Description |
|-----|-------------|
| `server_url` | The connect endpoint — a hub URL **or** a direct server URL (set on the Connect screen). |
| `auth_token` / `refresh_token` | The login token. In hub mode this is the **hub** token, which doubles as the relay Bearer. |
| `connection_kind` | `"hub"` or `"direct"`. Absent / unrecognized is treated as `"direct"`. |
| `active_server_id` | The hub server chosen in the picker; appended to the relay proxy base. |
| `active_server_name` | Display name of the chosen server. |

#### Known limitation — non-GET/POST verbs over the relay

The hub registers **only `GET` and `POST`** on its relay proxy route
(`/api/v1/servers/{id}/proxy/{path:.*}`). In hub mode the media `ApiClient` is bound to the
relay base, so `PUT`/`DELETE` calls cannot be tunneled to the server and degrade:

- **favorites-remove** (`DELETE /media/{id}/favorite`),
- **rating set / clear** (`PUT` / `DELETE /media/{id}/rating`),
- **server-side session-end on logout** (`DELETE /sessions/{id}` — the local token still
  clears, so logout works, but the server session is not ended).

The core flows — connect, login, server pick, browse, play, resume, search, and
**favorites-add** — all use `GET`/`POST` and work over the relay. **Direct mode is
unaffected** (all verbs reach the server). **Recommended follow-up:** a phlix-hub change to
register `PUT`/`DELETE`/`PATCH` on the proxy handler.

> **Hub-token refresh-over-relay is not wired.** The `ApiClient` refresh-on-401 path would, in
> hub mode, attempt to refresh through the relay against the server rather than against the hub.
> The hub token's `expires_in` is 3600s; on expiry the relay 401 does not refresh correctly, the
> token clears, and the next boot/login re-authenticates. Routing refresh to the hub in relay
> mode is a planned follow-up.

### 6. SyncPlay (Watch Together)

SyncPlay lets several devices watch the same content together, staying in sync without manual
timestamp coordination. It is a **TV-friendly, button-driven overlay inside the player** — there is
no separate SyncPlay scene; all playback control stays in `PlayerScene`, so when the overlay is
never opened the player path is byte-identical to a non-SyncPlay build.

> ## ⚠️ LIMITATIONS — read before relying on SyncPlay
>
> - **DEVICE-UNVERIFIABLE.** Roku BrightScript only runs on hardware (there is no host runner), so
>   this code has been verified by `brighterscript` (bsc) + code review **only** — never executed.
> - **Built to a not-yet-deployed server target.** The whole slice targets the *post-`SP*`*
>   phlix-server SyncPlay wire contract. **The server's SyncPlay WebSocket worker is not live yet**
>   (`phlix-server/start.php` still stubs the `:8097` worker as `(Future)`), so SyncPlay cannot
>   actually connect or function until phlix-server Phase 8 (SP1/SP2/SP4/SP7) ships.
> - **`ws://` only — `wss://` is impossible.** Roku's `roStreamSocket` is plaintext TCP with **no
>   TLS**, so the hand-rolled WebSocket can speak `ws://` only. On a TLS-fronted production box
>   (HAProxy terminating TLS) SyncPlay connects **only if the server's plaintext `:8097` is reachable
>   from the Roku** (same LAN, or a documented plaintext exposure). The client derives a plaintext
>   `ws://<host>:8097/syncplay?token=…` URL from the connected server origin.
> - **Hub mode: disabled.** The hub relay proxy is HTTP-only (it strips the `Upgrade` header), so
>   there is no WebSocket path through the hub. In hub mode the overlay refuses to open with a
>   friendly message ("Watch Together isn't available in hub mode yet").
> - **Deferred:** chat / typing, host transfer, playback queue, periodic `playback_sync` broadcast,
>   group passwords (password-gated groups simply fail to join), WS reconnect/backoff (a disconnect
>   ends the session — no auto re-join), and strict `Sec-WebSocket-Accept` SHA-1 verification (the
>   client sends a valid random key and accepts the `101` without verifying the accept hash).

#### Usage

1. **Open the overlay.** During playback, press the **`*` / Options** key to open the **Watch
   Together** overlay (direct mode only — in hub mode it shows the disabled message).
2. **Pick or create a group.** The overlay lists existing groups (a read-only snapshot from
   `GET /api/v1/syncplay/groups`, so no group-id typing on the TV). Select one to **Join**, press
   **Create Group** to start a new room (named `"<device>'s Room"`, no keyboard), or **Leave** to
   exit. A status line shows the connection state, group name, member count, and sync (offset/stable)
   indicator.
3. **Watch together.** Playback follows the group **host**: inbound host `play` / `pause` / `seek`
   are applied to the local `Video` node with NTP drift correction (ms→s at the boundary) and
   echo-suppressed by your own member id. When **this** device is the host, your local play / pause /
   seek are broadcast to the group.

#### Wire contract (canonical `syncplay_*`)

The on-the-wire protocol mirrors `@phlix/syncplay` and the phlix-server `Messages::TYPE_*`
constants. The transport implementation is `source/lib/SyncPlayProtocol.brs` (pure RFC6455 framing +
flat codec + NTP TimeSync, no I/O), driven by the long-lived `components/SyncPlayTask.{xml,brs}`
node (socket I/O off the render thread).

- **Framing is FLAT.** Every message, in and out, is a single flat JSON object — payload fields
  spread at the **top level**, *not* nested under `data`:
  `{ "type": "syncplay_<name>", "protocol_version": 1, "timestamp": <ms>, …payload }`. The repo's
  old `syncplay.<dot>` event notation was wrong and never implemented — the real types use the
  **`syncplay_` underscore** prefix.
- `protocol_version` is always `1`; `timestamp` is sender wall-clock **milliseconds**; **all
  positions / durations on the wire are milliseconds** (Roku `Video` position/seek are seconds → the
  client converts at the boundary).
- **`syncplay_group_state` is the one nested case:** `{ type, protocol_version, timestamp,
  group:{…}, your_id:"…" }` — `group` and `your_id` sit flat at the top level, but `group` is itself
  an object (`group_id`, `group_name`, `member_count`, `members:[{id,name,is_host,joined_at}]`,
  `host_id`, `current_media_id`, `playback_position` (ms), `playback_state`, …). The client learns
  its **real** member id from `group_state.your_id` (used for echo-suppression and host detection).
- **Auth + URL:** the WS connection is authenticated on the upgrade via `?token=<access_token>` (the
  same access token the REST client holds in Storage `auth_token`); unauthenticated sockets are
  rejected before any frame. The canonical URL is `wss://<host>/syncplay` → server **`:8097`**, but
  since Roku can't do TLS the client connects to the derived plaintext
  `ws://<host>:8097/syncplay?token=…`.

The 19 canonical message types (F13 implements the TV-friendly subset shown below; chat / typing /
host_transfer / queue / sync are deferred):

| Type (`syncplay_*`) | Direction | F13 | Notes |
|---|---|---|---|
| `syncplay_group_create` | Client → Server | ✅ | `group_name`, `member_name?` (sent on Create) |
| `syncplay_group_join` | Client → Server | ✅ | `group_id`, `member_name?` (sent on Join) |
| `syncplay_group_leave` | Client → Server | ✅ | `group_id`, `member_id` (sent on Leave) |
| `syncplay_group_list` | Client → Server | — | group browse uses the REST snapshot instead |
| `syncplay_playback_play` | both | ✅ | `group_id`, `member_id`, `position` (ms), `server_time` (ms) |
| `syncplay_playback_pause` | both | ✅ | same payload as `_play` |
| `syncplay_playback_seek` | both | ✅ | `from_position`, `to_position`, `server_time` (all ms) |
| `syncplay_playback_queue` | both | — | deferred (no queue UI) |
| `syncplay_playback_sync` | both | — | deferred (no periodic broadcast) |
| `syncplay_chat` / `syncplay_typing` | both | — | deferred (no chat UI) |
| `syncplay_host_transfer` | Client → Server | — | deferred |
| `syncplay_time_ping` | Client → Server | ✅ | `client_time` (ms = t1); sent on the periodic tick |
| `syncplay_time_pong` | Server → Client | ✅ | `client_time` (echoed t1), `server_time` (t2) |
| `syncplay_group_state` | Server → Client | ✅ | nested `group` + `your_id` (see above) |
| `syncplay_host_elect` | Server → Client | ✅ | `elected_id`, `elected_by` (re-election on host leave) |
| `syncplay_time_sync` | Server → Client | — | not consumed (client maintains its own offset) |
| `syncplay_info` | Server → Client | ✅ | `message` (+ `member_id`/`member_name` on member JOIN) |
| `syncplay_error` | Server → Client | ✅ | `error_code` (fallback `code`) + `message` |

#### Time Synchronization Protocol (NTP-style, milliseconds)

Implemented in `SyncPlayProtocol.brs` TimeSync, mirroring `@phlix/syncplay` SPEC §5:

1. Every tick (~4s) the client sends `syncplay_time_ping` with `client_time` = t1 (ms).
2. The server replies `syncplay_time_pong` with `client_time` (echoed t1) and `server_time` (t2 =
   server receive time; there is **no** t3/`server_receive_time` field).
3. Per pong (t3 = t2, t4 = local `NowMs()`): `rtt = t4 - t1`; `oneWay = rtt/2`;
   `offset = t2 - t1 + oneWay`. Samples with `rtt < 0` or `rtt > 1000` are rejected.
4. `offset` is the **weighted mean** (weight `1/max(1,rtt)`) over the last 5 samples; it is
   considered **stable** when there are ≥5 samples and the recent-offset variance is `< 50`.
5. A drift-rate EMA `1.0 + 0.1*(Δoffset/Δt)/1000` (clamped to `[0.99, 1.01]`) scales the follow
   position: adjusted ms = `position + (NowMs() + offset - serverTime) * driftRate`, converted to
   seconds before any `video.seek`.

## Configuration

### Environment Variables

| Variable | Description | Default |
|---------|-------------|---------|
| `ROKU_IP` | IP address of Roku device | `192.168.1.100` |
| `ROKU_DEV` | Developer username | `rokudev` |
| `ROKU_PASSWORD` | Developer password | `rokipassword` |

### Manifest Configuration

Edit `manifest` to customize:
- `title`: Application name
- `major_version`, `minor_version`, `build_version`: Version numbers
- `ui_resolutions`: Supported resolutions (hd, fhd, uhd)

### BrightScript Configuration

The app uses these configurable constants (in source files):

```brightscript
' In ApiClient.brs - Device capabilities
deviceProfile: {
    MaxStreamingBitrate: 30000000  ' 30 Mbps
    MaxStaticBitrate: 30000000
    SupportedMediaTypes: ["Video", "Audio"]
}
```

## Building the App

### Standard Build

```bash
# Create package for sideloading
make package

# This creates: phlix.zip
```

### Install to Device

```bash
# Install to configured Roku IP
make install ROKU_IP=192.168.1.100 ROKU_DEV=rokudev ROKU_PASSWORD=yourpass

# Or install with rokupkg
rokupkg --install phlix.zip
```

### Development Workflow

```bash
# 1. Make code changes
# 2. Package and install
make package install ROKU_IP=192.168.1.100

# 3. Launch app
make launch ROKU_IP=192.168.1.100

# 4. Debug via telnet on port 8080
telnet 192.168.1.100 8080
```

### Manual Deployment

```bash
# Create package manually
zip -r phlix.zip manifest source images

# Sideload via curl
curl -v -u rokudev:password -X POST \
    http://192.168.1.100:8060/install/app \
    -F "archive=@phlix.zip" \
    -F "manifest=@manifest"
```

## Testing

### Unit Tests

Unit tests are located in `tests/unit/` and use BrightScript's testing patterns.

```bash
# List available tests
make test

# Output shows:
# Found test: tests/unit/ApiClient.test.brs
# Found test: tests/unit/Storage.test.brs
# Found test: tests/unit/Utilities.test.brs
```

### Running Tests on Device

1. Deploy to device: `make install`
2. Tests run automatically via the test framework when accessed via developer portal

### Integration Tests

Integration tests in `tests/integration/` test API client against a live server.

```bash
# Run integration tests (requires running Phlix server)
# Deploy tests to device and run via developer portal
```

### Test Structure

```
tests/
├── unit/
│   ├── ApiClient.test.brs      # API client unit tests
│   ├── Storage.test.brs         # Storage unit tests
│   └── Utilities.test.brs       # Utilities unit tests
└── integration/
    └── ApiIntegration.test.brs  # API integration tests
```

## Deployment to Roku

### Pre-production Checklist

- [ ] Test on physical Roku device
- [ ] Verify all remote buttons work
- [ ] Check video playback with various formats
- [ ] Verify authentication flow
- [ ] Test library browsing
- [ ] Check network timeout handling
- [ ] Verify progress sync

### Publishing to Roku Channel Store

1. Create developer account at [developer.roku.com](https://developer.roku.com)
2. Sign in and go to Dashboard
3. Upload your packaged app (phlix.zip)
4. Complete store listing details
5. Submit for review

### Private Channel Testing

```bash
# Sideload directly for testing
make install

# Or use roku's dev channel mechanism
```

## API Endpoints

The app communicates with these Phlix API endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/Auth/Login` | User authentication with device info |
| DELETE | `/api/v1/Sessions/{id}` | End session |
| GET | `/api/v1/Sessions` | List active sessions |
| POST | `/api/v1/Sessions` | Create new session |
| GET | `/api/v1/Library/VirtualFolders` | Get library folders |
| GET | `/api/v1/Items` | Get items with filtering |
| GET | `/api/v1/Items/{id}` | Get single item details |
| GET | `/api/v1/Items/{id}/PlaybackInfo` | Get playback URLs and info |
| POST | `/api/v1/Sessions/Play` | Start playback session |
| POST | `/api/v1/Playstate` | Update playstate (play/pause/stop) |
| POST | `/api/v1/Playstate/Progress` | Report playback progress |
| POST | `/api/v1/Items/{id}/UserData` | Update user data (watched, etc.) |
| GET | `/api/v1/Users/Me` | Get current user info |
| GET | `/api/v1/collections` | List collections (read-only). Returns `{collections:[...]}`. Currently unauthenticated server-side. |
| GET | `/api/v1/collections/{id}` | Get one collection with its items (read-only). Returns `{collection, items, total}`; `items` are raw DB rows normalized client-side. Currently unauthenticated server-side. |
| GET | `/api/v1/syncplay/groups` | SyncPlay group-list snapshot (read-only; server SP5). Returns the whole `{groups:[{id, name, member_count, has_password, current_media, is_playing}]}` envelope (NOT unwrapped) — note the list uses `id`/`name`, **not** `group_id`/`group_name`. Used to populate the Watch Together overlay without typing a group id on the TV; group create/join/leave go over the WebSocket, not REST. See "SyncPlay (Watch Together)". |
| GET | `/api/v1/auth/me` | Get the current user (auth-gated). Returns the unwrapped `{user}`, which carries `is_admin` (TINYINT 0/1) and `status`. The Home screen calls this on init to gate the admin entry. In **hub mode** the boot session-validation hits this against the **hub directly** (not over the relay), because `/auth/me` over the relay returns the hub-user perspective on the server and is unreliable. |
| GET | `/api/v1/me/servers` | Hub-only. Returns `{servers:[ … ]}` (**camelCase** rows: `serverId`, `userId`, `serverName`, `version`, `lastSeenAt`, `status` `"online"`/`"offline"`/`"claiming"`/`"disabled"`, `hostnameCandidates:[url]`, `relayActive` (bool), `libraryCount`). A **direct** server has no such route → 404 / no `servers` array. The client calls this right after login to detect hub vs direct, and the server picker reads the whole `{servers}` envelope. |
| GET/POST | `/api/v1/servers/{serverId}/proxy/{path:.*}` | Hub relay proxy (the **only** registered relay route). In hub mode, after a server is picked, the media `ApiClient` is bound to `{hub}/api/v1/servers/{serverId}/proxy` and sends the **hub** Bearer; the hub strips client auth, verifies server ownership (403 `server.not_owned` otherwise), injects `X-Phlix-Relay-User`, and tunnels the request to the server (which trusts the tunnel). **Only `GET`/`POST` are registered** — `PUT`/`DELETE` are not routable over the relay (see the known limitation under "Hub / multi-server mode"). |
| GET | `/api/v1/admin/dashboard/now-playing` | Admin-gated, read-only. Active streams. Envelope `{success, data, count}`; `data[]` rows carry `username`, `media_title`, `progress_percent`, etc. AdminMiddleware → 401 (no/invalid token) / 403 (non-admin). |
| GET | `/api/v1/admin/dashboard/storage` | Admin-gated, read-only. Per-type storage usage. Envelope `{success, data, count}`; `data[]` rows carry `media_type`, `item_count`, server-preformatted `formatted_total`. AdminMiddleware → 401/403. |
| GET | `/api/v1/admin/dashboard/activity` | Admin-gated, read-only. Recent activity (optional `?limit=N`). Envelope `{success, data, count}`; `data[]` rows carry `occurred_at`, `username`, `event_type`. AdminMiddleware → 401/403. |
| POST | `/api/v1/libraries/{id}/scan` | Admin-gated (internal `requireAdmin`). Enqueues an **incremental** scan job. **202** `{job_id, status, message}`. Sent as a bodyless POST. |
| POST | `/api/v1/libraries/{id}/rescan` | Admin-gated (internal `requireAdmin`). Enqueues a **full** rescan job. **202** `{job_id, status, message}`. Sent as a bodyless POST. |
| POST | `/api/v1/libraries/{id}/match-metadata` | Admin-gated (internal `requireAdmin`). Enqueues a metadata-matching job. **202** `{job_id, status, message}`. Sent as a bodyless POST. |
| GET | `/api/v1/libraries/{id}/scan-status` | Admin-gated (internal `requireAdmin`). Returns the latest scan job for the library: `{scan_status: <job row | null>}`. **200** even when never scanned (`scan_status` is `null`). Job row carries `job_type`, `status`, `current_path`, `started_at`, `completed_at`. |
| GET | `/api/v1/admin/users` | Admin-gated (AdminMiddleware). Lists all users (optional `?status=pending\|active\|disabled`). Returns the whole `{users:[...]}` envelope; each user row carries `id` (UUID), `username`, `email`, `display_name`, `is_admin` (TINYINT 0/1), `status` (`pending`/`active`/`disabled`), `created_at`, `last_login`. AdminMiddleware → 401 (no/invalid token) / 403 (non-admin). |
| GET | `/api/v1/admin/users/{id}` | Admin-gated (AdminMiddleware). Returns one user: `{user}` (whole envelope). 404 `{error}` if not found. |
| POST | `/api/v1/admin/users/{id}/approve` | Admin-gated (AdminMiddleware). Approves a pending user. Bodyless POST. `{message}` on success; 404 `{error}`. |
| POST | `/api/v1/admin/users/{id}/disable` | Admin-gated (AdminMiddleware). Disables a user. Bodyless POST. `{message}` on success; 404 / 400 `{error}` (cannot disable self; cannot disable last admin). |
| POST | `/api/v1/admin/users/{id}/set-admin` | Admin-gated (AdminMiddleware). Promotes/demotes a user; body `{is_admin: bool}`. `{message}` on success; 404 / 400 `{error}` (cannot demote self; cannot demote last admin). |
| POST | `/api/v1/admin/users/{id}/reset-password` | Admin-gated (AdminMiddleware). Resets the user's password. Bodyless POST. `{message, new_password}` on success (the new password is shown once); 404 `{error}`. |
| GET | `/api/v1/admin/users/{userId}/profiles` | Admin-gated (AdminMiddleware). Lists a user's profiles. Returns the whole `{profiles:[...]}` envelope (admin getters do not unwrap). Each profile row carries `id` (UUID), `user_id`, `name`, `avatar_url`\|null, `is_active` (bool/TINYINT), `is_admin` (bool/TINYINT), `rating` (computed **Integer** 0-6: `G=0, PG=1, PG-13=2, R=3, NC-17=4, X=5, UNRATED=6`), `created_at`, `updated_at`, and an optional `settings` object (`content_rating` label string, `pin_required_for_admin` bool, `max_daily_watch_time`, `allow_unrated`, …). 404 `{error}` if the user is not found. |
| GET | `/api/v1/admin/profiles/{id}` | Admin-gated (AdminMiddleware). Returns one profile: `{profile}` (whole envelope). 404 `{error}` if not found. |
| PUT | `/api/v1/admin/profiles/{id}` | Admin-gated (AdminMiddleware). Updates a profile; F10 sends `{rating: <int 0-6>}` only (name/PIN edits deferred). `{message}` on success; 400 `{error, field_errors?}` / 404 `{error}`. |
| DELETE | `/api/v1/admin/profiles/{id}/pin` | Admin-gated (AdminMiddleware). Clears (removes) the profile's PIN. Bodyless DELETE. `{message}` on success; 404 `{error}`. |
| GET | `/api/v1/admin/livetv/channels` | Admin-gated (AdminMiddleware). Lists Live TV channels. Returns the whole `{success, channels:[...]}` envelope (admin getters do not unwrap). Each channel row carries `id` (== `channel_id`, the UUID used for `/stream`), `name`, `number` (**Integer**), `type`, `frequency` (Integer), `tuner_id`, `service_id`, `visual_id`, `description`, `icon_url`, `visibility`, `created_at`, `updated_at`. AdminMiddleware → 401 (no/invalid token) / 403 (non-admin). **If Live TV is not configured the route group is not registered → 404**; configured-but-no-tuner returns `{success, channels:[]}`. |
| GET | `/api/v1/admin/livetv/channels/{id}/stream` | Admin-gated (AdminMiddleware, Bearer). **Returns a 302 redirect** (`Location` header) to the actual stream URL. The redirect target is an **unauthenticated** tuner/HLS URL (HDHomeRun: a direct `http://<host>:5004/auto/vN` raw MPEG-TS URL; IPTV: may be an `.m3u8`). Because the Roku `Video` node cannot carry the `Authorization` header, the client resolves this 302 with Bearer and hands the final (unauthenticated) URL to the player. See the Live TV caveat below. |
| GET | `/api/v1/admin/livetv/guide` | Admin-gated (AdminMiddleware). Read-only EPG. Returns the whole `{success, programs:[...]}` envelope (admin getters do not unwrap). The client sends no query params → upcoming programs across **all** channels (next 7 days, capped 500 server-side). Each program row carries `id` (== `program_id`), `channel_id`, `title`, `description`, `start_time` / `end_time` (**Integer**, UNIX seconds), `duration` (Integer, seconds), `category`, `series_id`, `episode_number` (Integer\|null), `episode_title`, `rating`, `year` (Integer\|null), `is_repeat` / `is_film` (Bool), `created_at`, `updated_at`. AdminMiddleware → 401/403. **If Live TV is not configured the route group is not registered → 404** (treated as "Live TV unavailable"). |
| GET | `/api/v1/admin/livetv/recordings` | Admin-gated (AdminMiddleware). Read-only recordings list. Returns the whole `{success, recordings:[...]}` envelope. Each recording row carries `id` (== `recording_id`), `channel_id`, `program_id`\|null, `user_id`\|null, `title`, `description`\|null, `start_time` / `end_time` (**Integer**, UNIX seconds), `duration` (Integer, seconds), `priority` (Integer), `quality`\|null, `storage_path`\|null, `storage_size` (Integer), `status` (String), `series_rule_id`\|null, `created_at`, `updated_at`. AdminMiddleware → 401/403; route group absent → 404 ("Live TV unavailable"). |
| GET | `/api/v1/admin/livetv/series-rules` | Admin-gated (AdminMiddleware). Read-only series-recording rules. Returns the whole `{success, rules:[...]}` envelope. ⚠️ Each rule row has **no top-level `id`** — the key is `rule_id`. Rows carry `rule_id`, `series_id`, `channel_id`\|null, `title`, `priority` (**Integer**), `pre_padding_seconds` / `post_padding_seconds` (Integer), `max_recordings` (Integer\|null), `days_ahead` (Integer), `is_active` (Bool), `created_at`\|null, `updated_at`\|null. AdminMiddleware → 401/403; route group absent → 404 ("Live TV unavailable"). |

## Remote Control Reference

| Button | Action |
|--------|--------|
| Select/Play | Play / Pause toggle |
| Back | Go back / Close detail view |
| Left | Seek backward 30 seconds |
| Right | Seek forward 30 seconds |
| Rewind | Seek backward 10 seconds |
| Fast Forward | Seek forward 10 seconds |
| Options (`*`) | Open/close the **Watch Together** (SyncPlay) overlay (direct mode only; shows a disabled message in hub mode). While the overlay is open, Back/Options close it. |
| Skip Button | Skip intro/outro section (shown automatically during marker ranges) |

### Home Header Navigation

The Home screen header has up to four buttons. Use Left/Right to cycle between them (stops at the
ends — never wraps):

`Search ↔ Favorites ↔ Collections ↔ Admin`

- **Search** — open the search screen.
- **Favorites** — browse your favorited items.
- **Collections** — open the read-only Collections browse flow: `Home → Collections (list of
  collection names) → a collection's items (poster grid) → item detail`. Items are type-routed
  exactly like Library/Favorites (series → series view, season → season view, otherwise → detail).
- **Admin** — shown **only for admin users**. On Home init the app calls `GET /auth/me` and reveals
  the button when the returned user is `is_admin`; for non-admins the button stays hidden and the
  Right-nav skips it (no dead end / no focus on a hidden node). Opens the read-only admin flow:
  `Home → Admin (menu) → Dashboard | Libraries | Users | Live TV | TV Guide | Recordings | Series Rules`.
  The Admin menu has seven rows:
  - **Dashboard** — a read-only stats view (now-playing / storage / recent-activity) in a single list.
  - **Libraries** — a button-driven library admin surface (no keyboard required):
    `Admin → Libraries (LabelList of libraries) → a library's actions`. The per-library actions screen
    has four buttons — **Scan (incremental)**, **Rescan (full)**, **Match Metadata**, and **Refresh
    Status** — plus a scan-status summary line. Selecting Scan / Rescan / Match Metadata enqueues an
    asynchronous job on the server (202 `{job_id, status, message}`) and then refreshes the status line;
    only one request runs at a time. The status line shows the latest job's type / status / current path
    / started / completed, or **"Never scanned"** when the library has no scan job yet. Status is
    refreshed **manually** via the Refresh Status button — there is no auto-poll.
  - **Users** — a button-driven user admin surface (no keyboard required):
    `Admin → Users (LabelList of all users) → a user's actions`. The list shows every user (no
    status-filter tabs) with a caption combining username, status, and an admin tag. The per-user
    actions screen has six buttons — **Approve**, **Disable**, **Make Admin / Remove Admin** (a
    toggle whose title reflects the user's current admin state), **Reset Password**, **Profiles**, and
    **Refresh** — plus a multi-line detail line summarizing the user (username / email / status /
    admin). Approve /
    Disable / Set-Admin call the server and then re-fetch and re-render the user's state; only one
    request runs at a time. **Reset Password** shows the server's one-time `new_password` **once** in
    the status line (it is not re-fetched afterward, so the password stays visible). State is refreshed
    **manually** via the Refresh button — there is no auto-poll. The server enforces guards (cannot
    disable/demote yourself or the last admin) and returns those messages, which are surfaced verbatim.
    **Deferred / future work:** creating and editing users (need an on-screen keyboard) and deleting or
    rejecting users (destructive removal with no on-TV confirmation dialog) are intentionally not shipped
    in this surface — the actions included are all recoverable/reversible.
    - **Profiles** — a per-user profile admin surface (no keyboard required), reached from the
      user's actions screen: `Admin → Users → (select user) → Profiles (LabelList of the user's
      profiles) → a profile's actions`. Because the server's profile-listing route is **per-user**
      (`GET /api/v1/admin/users/{userId}/profiles`), the Profiles button hangs off the selected
      user rather than being a top-level Admin row. The profile list is a one-shot fetch reading the
      whole `{profiles:[...]}` envelope; each row shows the profile name plus tags (rating label,
      `admin`, `active`, `PIN`). Bool/TINYINT flags (`is_admin`, `is_active`,
      `settings.pin_required_for_admin`) are read through type-guarded helpers and the computed
      `rating` Integer (0-6) is mapped to a label — neither is ever string-compared. The per-profile
      actions screen has nine buttons: seven flat **Rating: G / PG / PG-13 / R / NC-17 / X /
      UNRATED** buttons (each sends `PUT /api/v1/admin/profiles/{id}` with `{rating: <int 0-6>}`),
      **Clear PIN** (`DELETE /api/v1/admin/profiles/{id}/pin`), and **Refresh** — plus a multi-line
      detail summary (Name / Rating / Admin / Active / PIN required). Set-Rating and Clear-PIN call
      the server then re-fetch and re-render the profile; only one request runs at a time, and state
      is refreshed **manually** (no auto-poll). **Deferred / future work:** creating a profile,
      editing a profile's name, and setting a PIN all need an on-screen keyboard, and deleting a
      profile is a destructive action with no on-TV confirmation dialog — so they are intentionally
      not shipped. The shipped subset ("view profiles + adjust the parental-control rating + clear a
      forgotten PIN") is the genuinely useful button-driven slice for a 10-foot remote.

      > **Upstream gap.** There is **no user-facing profile route** — profile management is
      > admin-gated only (the same gap the mobile E5 slice flagged). A self-service on-TV profile
      > switcher would need a `/users/me/profiles` route plus a profile-context request header.
  - **Live TV** — a channels list + channel playback surface:
    `Admin → Live TV (LabelList of channels) → select a channel → live player`. The list is a
    one-shot `GET /api/v1/admin/livetv/channels` (AdminMiddleware-gated; the whole
    `{success, channels:[...]}` envelope is read). Each channel row shows **`<number>  <name>`**
    (the Integer `number` is stringified, not string-compared). Selecting a channel resolves its
    stream — the client issues the Bearer-gated `GET /api/v1/admin/livetv/channels/{id}/stream`,
    reads the **302 `Location`** header (without following the redirect), and opens a dedicated
    lightweight live player (`LivePlayerScene`) on the final (unauthenticated) tuner/HLS URL. The
    live player has **no sessions / progress / transcode / markers** — it does not reuse the VOD
    `PlayerScene`. The status line surfaces friendly errors ("Tuning…", "Couldn't start channel",
    "Live TV unavailable", "Playback failed"). The route group is **not registered when Live TV is
    not configured** (the list then reports "Live TV unavailable").

    > **Streaming caveat (device-only-verifiable).** Channel playback hinges on resolving a
    > Bearer-gated **302** and reading the `Location` header _without following it_. Roku's
    > `roUrlTransfer` redirect-follow behavior is **firmware-dependent** and there is no documented
    > "don't follow redirects" setter: if the firmware auto-follows, `GetResponseCode()` returns
    > 200, no `Location` header is exposed, the resolved stream URL is empty, and live playback
    > fails with a friendly error. This cannot be verified without a physical device. **Recommended
    > upstream mitigation:** add a JSON `GET .../stream-url` endpoint (or a signed live-TV URL) so a
    > TV `Video` node can obtain the stream URL without resolving an authenticated redirect. The
    > `mpegts`-vs-`hls` `streamFormat` heuristic (`.m3u8` in the URL → `hls`, otherwise `mpegts`)
    > and raw-TS playback are likewise only verifiable on a device.

    **Scope:** channels list + playback only.
  - **TV Guide** — a read-only EPG list (`Admin → TV Guide`). A one-shot
    `GET /api/v1/admin/livetv/guide` (AdminMiddleware-gated; the whole `{success, programs:[...]}`
    envelope is read, sent with no query params → upcoming programs across all channels). Each row
    shows **`<start time>  <title>`** where the start time is the Integer `start_time` (UNIX seconds)
    rendered by `Utilities.FormatUnixTime` as a local `"M/D H:MM"` wall-clock string (the Integer is
    never string-compared). **Selection is inert** (read-only view). Empty result → "No programs";
    missing `programs` key / unregistered route → "Live TV unavailable".
  - **Recordings** — a read-only recordings list (`Admin → Recordings`). A one-shot
    `GET /api/v1/admin/livetv/recordings` (whole `{success, recordings:[...]}` envelope). Each row
    shows **`<title>  (<status>)`** plus ` — <start time>` (via `FormatUnixTime`) when present, falling
    back to the status or "(recording)" when there is no title. **Selection is inert.** Empty →
    "No recordings"; missing key / unregistered route → "Live TV unavailable".
  - **Series Rules** — a read-only series-recording-rule list (`Admin → Series Rules`). A one-shot
    `GET /api/v1/admin/livetv/series-rules` (whole `{success, rules:[...]}` envelope). Each row shows
    the rule **`title`** (falling back to `series_id`, then "(rule)"), optionally with `  (priority N)`
    where `N` is the Integer `priority`. The rule row has **no top-level `id`** — only `rule_id` is
    read. **Selection is inert.** Empty → "No rules"; missing key / unregistered route → "Live TV
    unavailable".

    With these three views, **F9 (live TV) is complete**. **Deferred / future work:** a guide
    channel-filter picker, recording create / delete + recording playback, series-rule CRUD, and
    channel edit (PUT) are intentionally not shipped — they need on-screen pickers / keyboard (or an
    unscouted route), so all four Live TV admin surfaces remain read-only.

## Project Structure

```
phlix-roku/
├── source/
│   ├── main.brs                 # Main entry point
│   ├── lib/
│   │   ├── ApiClient.brs       # API client (communication layer)
│   │   ├── Storage.brs        # Persistent storage (registry)
│   │   ├── AuthManager.brs     # Authentication manager
│   │   ├── SessionManager.brs  # Session management
│   │   ├── LibraryManager.brs  # Library browsing logic
│   │   ├── TaskManager.brs     # Background task management
│   │   ├── SyncPlayProtocol.brs # SyncPlay: pure RFC6455 WS framing + flat syncplay_* codec + NTP TimeSync (no I/O / no UI)
│   │   └── Utilities.brs        # Helper functions
│   ├── components/
│   │   ├── PhlixApp.brs       # Main app controller
│   │   ├── HomeScene.brs       # Home screen
│   │   ├── LibraryScene.brs    # Library browser
│   │   ├── DetailScene.brs     # Item detail view
│   │   ├── CollectionsScene.brs # Collections list (LabelList of collection names, read-only)
│   │   ├── CollectionScene.brs  # One collection's items (poster grid; raw rows normalized client-side)
│   │   ├── AdminScene.brs       # Admin menu (LabelList; is_admin-gated entry; rows: Dashboard, Libraries, Users, Live TV, TV Guide, Recordings, Series Rules)
│   │   ├── DashboardScene.brs   # Read-only admin dashboard (now-playing / storage / activity in one list)
│   │   ├── LibraryAdminScene.brs # Admin libraries list (LabelList; drills into per-library actions)
│   │   ├── LibraryAdminActionsScene.brs # Per-library admin actions (Scan / Rescan / Match Metadata / Refresh Status + scan-status line)
│   │   ├── UserAdminScene.brs    # Admin users list (LabelList of all users; drills into per-user actions)
│   │   ├── UserAdminActionsScene.brs # Per-user admin actions (Approve / Disable / Make-or-Remove Admin / Reset Password / Profiles / Refresh + user detail line)
│   │   ├── ProfilesScene.brs     # Per-user profile list (one-shot LabelList; read-only; drills into per-profile actions)
│   │   ├── ProfileActionsScene.brs # Per-profile admin actions (7 Rating buttons / Clear PIN / Refresh + profile detail line)
│   │   ├── LiveTvScene.brs       # Admin Live TV channels list (one-shot LabelList; row-select resolves stream → live player)
│   │   ├── LivePlayerScene.brs   # Dedicated lightweight live Video player (no sessions/progress/transcode/markers)
│   │   ├── GuideScene.brs        # Admin Live TV guide/EPG list (one-shot LabelList; read-only, selection inert)
│   │   ├── RecordingsScene.brs   # Admin Live TV recordings list (one-shot LabelList; read-only, selection inert)
│   │   ├── SeriesRulesScene.brs  # Admin Live TV series-rules list (one-shot LabelList; read-only, selection inert)
│   │   ├── PlayerScene.brs     # Video player (+ additive "Watch Together" SyncPlay overlay, opened with the "*"/Options key; gated, hub-disabled, ws:// only)
│   │   ├── SyncPlayTask.{xml,brs} # Long-lived Task running the SyncPlay ws:// socket off the render thread (roStreamSocket; RunSocket loop; flat syncplay_* frames)
│   │   ├── ConnectScene.brs    # First-run "Connect to server" screen (normalizes + probes /health, persists server_url, then proceeds to login)
│   │   ├── LoginScene.brs      # Login screen (username/password only); after login probes GET /me/servers to detect hub vs direct
│   │   ├── ServerPickerScene.brs # Hub mode: "Choose a server" list (one-shot GET /me/servers); pick persists active_server_id → relay routing
│   │   └── GridItem.brs        # Grid item component
│   ├── player/
│   │   └── SkipButton.brs      # Skip intro/outro button
│   ├── pages/
│   │   ├── HomePage.brs        # Home page controller
│   │   ├── LibraryPage.brs      # Library page controller
│   │   └── SettingsPage.brs    # Settings page controller
│   └── data/
│       └── Theme.brs           # Theme constants
├── tests/
│   ├── unit/                   # Unit tests
│   └── integration/            # Integration tests
├── images/                      # App icons and splash screens
├── manifest                    # App manifest
├── Makefile                    # Build automation
├── README.md                   # This file
└── DEVELOPER.md                # Developer documentation
```

## Troubleshooting

### App Won't Install

1. Verify Roku IP address is correct
2. Check developer credentials
3. Ensure dev mode is enabled on Roku
4. Try: `curl -u user:pass http://ROKU_IP:8060/` to verify connectivity

### API Connection Failed

1. Verify Phlix Media Server is running
2. Check network connectivity from Roku
3. Verify the server URL entered on the first-run Connect screen is correct (the
   `/health` probe surfaces "Couldn't reach that server" when it is wrong/unreachable)
4. Check server logs for connection attempts

### Video Playback Issues

1. Verify HLS support on your server
2. Check network bandwidth
3. Try lower quality streams
4. Verify codec support (H.264/H.265 for video, AAC/AC3 for audio)

### Debugging

```bash
# Connect to Roku debug console
telnet ROKU_IP 8080

# Check app logs
# View variable values
# Step through BrightScript code
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request
5. Ensure CI passes

## License

MIT License - See LICENSE file for details

## Support

- Issue Tracker: GitHub Issues
- Documentation: [Phlix Wiki](https://github.com/your-org/phlix-roku/wiki)
