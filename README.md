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
- **Hub Mode**: Connect to a Phlix Hub for centralized authentication, server discovery, and relay-aware HLS playback through direct-LAN or hub-relay tunnel
- **Skip Intro/Outro**: Automatically displayed skip buttons when playback enters marker ranges defined by the server (intro start/end, outro start/end)
- **SyncPlay**: Watch with friends in perfect sync across multiple devices with NTP-style time synchronization, group state management, and synchronized playback controls (play/pause/seek)

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

The app will prompt for server URL on first launch, or you can pre-configure:

```bash
# Edit the default server URL in source/components/PhlixApp.brs
# Or set via Settings within the app
```

### 5. Hub Mode (Optional)

Hub Mode allows you to connect to a Phlix Hub for centralized authentication and multi-server access:

1. **Enable Hub Mode**: Go to Settings in the app
2. **Enter Hub URL**: Provide your hub server URL (e.g., `http://hub.example.com:8080`)
3. **Sign In**: Authenticate with your hub credentials
4. **Select Server**: Choose from your claimed servers
5. **Choose Connection Mode**:
   - **Direct**: Connect directly to server on LAN (fastest)
   - **Relay**: Route through hub tunnel (for remote access)

#### Hub Mode Storage Keys

| Key | Description |
|-----|-------------|
| `hub_url` | Hub server URL |
| `hub_session` | Hub authentication session (JWT tokens) |
| `active_server` | Currently selected server |
| `connection_mode` | "direct" or "relay" |

### 6. SyncPlay (Watch Together)

SyncPlay allows multiple users to watch the same content together remotely, staying in sync without manual timestamp coordination.

#### Features
- **NTP-Style Time Sync**: Weighted-mean offset calculation for accurate clock synchronization
- **Group Watching**: Create or join groups to watch with friends
- **Synchronized Playback**: Play, pause, and seek commands sync across all members
- **Member Presence**: See who's in the group and get notified on join/leave
- **Automatic Position Reports**: Periodic position updates every 30 seconds

#### Usage

1. **During Playback**: Press the SyncPlay button in the player overlay
2. **Create Group**: Tap "Create Group" to start a new SyncPlay session
3. **Join Group**: Enter a 6-character Group ID to join an existing session
4. **Watch Together**: All members receive synchronized play/pause/seek commands

#### SyncPlay WebSocket Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `syncplay.join_group` | Client → Server | Join a SyncPlay group |
| `syncplay.leave_group` | Client → Server | Leave current group |
| `syncplay.playback_command` | Client → Server | Send play/pause/seek command |
| `syncplay.report_position` | Client → Server | Periodic position report |
| `syncplay.request_time_sync` | Client → Server | Request time synchronization |
| `syncplay.time_sync` | Server → Client | Time sync response (offset calculation) |
| `syncplay.group_state` | Server → Client | Current group state and members |
| `syncplay.playback_update` | Server → Client | Play/pause/seek from any member |
| `syncplay.member_joined` | Server → Client | New member joined group |
| `syncplay.member_left` | Server → Client | Member left group |

#### Time Synchronization Protocol

The client implements NTP-style time synchronization:
1. Client sends `syncplay.request_time_sync` with local timestamp
2. Server responds with `syncplay.time_sync` containing timestamps
3. Client computes: `offset = (server_time - client_send_time) + latency`
4. Rolling average of last 5 samples maintained for stability
5. `adjustedTime = Date.now() + averageOffset` used for position comparisons

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
| GET | `/api/v1/auth/me` | Get the current user (auth-gated). Returns the unwrapped `{user}`, which carries `is_admin` (TINYINT 0/1) and `status`. The Home screen calls this on init to gate the admin entry. |
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
| GET | `/api/v1/admin/livetv/channels` | Admin-gated (AdminMiddleware). Lists Live TV channels. Returns the whole `{success, channels:[...]}` envelope (admin getters do not unwrap). Each channel row carries `id` (== `channel_id`, the UUID used for `/stream`), `name`, `number` (**Integer**), `type`, `frequency` (Integer), `tuner_id`, `service_id`, `visual_id`, `description`, `icon_url`, `visibility`, `created_at`, `updated_at`. AdminMiddleware → 401 (no/invalid token) / 403 (non-admin). **If Live TV is not configured the route group is not registered → 404**; configured-but-no-tuner returns `{success, channels:[]}`. |
| GET | `/api/v1/admin/livetv/channels/{id}/stream` | Admin-gated (AdminMiddleware, Bearer). **Returns a 302 redirect** (`Location` header) to the actual stream URL. The redirect target is an **unauthenticated** tuner/HLS URL (HDHomeRun: a direct `http://<host>:5004/auto/vN` raw MPEG-TS URL; IPTV: may be an `.m3u8`). Because the Roku `Video` node cannot carry the `Authorization` header, the client resolves this 302 with Bearer and hands the final (unauthenticated) URL to the player. See the Live TV caveat below. |

## Remote Control Reference

| Button | Action |
|--------|--------|
| Select/Play | Play / Pause toggle |
| Back | Go back / Close detail view |
| Left | Seek backward 30 seconds |
| Right | Seek forward 30 seconds |
| Rewind | Seek backward 10 seconds |
| Fast Forward | Seek forward 10 seconds |
| Options | Show/hide playback info |
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
  `Home → Admin (menu) → Dashboard | Libraries | Users | Live TV`. The Admin menu has four rows:
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
    actions screen has five buttons — **Approve**, **Disable**, **Make Admin / Remove Admin** (a
    toggle whose title reflects the user's current admin state), **Reset Password**, and **Refresh** —
    plus a multi-line detail line summarizing the user (username / email / status / admin). Approve /
    Disable / Set-Admin call the server and then re-fetch and re-render the user's state; only one
    request runs at a time. **Reset Password** shows the server's one-time `new_password` **once** in
    the status line (it is not re-fetched afterward, so the password stays visible). State is refreshed
    **manually** via the Refresh button — there is no auto-poll. The server enforces guards (cannot
    disable/demote yourself or the last admin) and returns those messages, which are surfaced verbatim.
    **Deferred / future work:** creating and editing users (need an on-screen keyboard) and deleting or
    rejecting users (destructive removal with no on-TV confirmation dialog) are intentionally not shipped
    in this surface — the actions included are all recoverable/reversible.
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

    **Scope:** channels list + playback only. **Deferred / future work:** guide/EPG, recordings,
    and series-rules (read) arrive in **F9b**; channel edit (PUT) and recording / series-rule
    mutations are deferred (they need on-screen pickers/keyboard).

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
│   │   └── Utilities.brs        # Helper functions
│   ├── components/
│   │   ├── PhlixApp.brs       # Main app controller
│   │   ├── HomeScene.brs       # Home screen
│   │   ├── LibraryScene.brs    # Library browser
│   │   ├── DetailScene.brs     # Item detail view
│   │   ├── CollectionsScene.brs # Collections list (LabelList of collection names, read-only)
│   │   ├── CollectionScene.brs  # One collection's items (poster grid; raw rows normalized client-side)
│   │   ├── AdminScene.brs       # Admin menu (LabelList; is_admin-gated entry; rows: Dashboard, Libraries, Users, Live TV)
│   │   ├── DashboardScene.brs   # Read-only admin dashboard (now-playing / storage / activity in one list)
│   │   ├── LibraryAdminScene.brs # Admin libraries list (LabelList; drills into per-library actions)
│   │   ├── LibraryAdminActionsScene.brs # Per-library admin actions (Scan / Rescan / Match Metadata / Refresh Status + scan-status line)
│   │   ├── UserAdminScene.brs    # Admin users list (LabelList of all users; drills into per-user actions)
│   │   ├── UserAdminActionsScene.brs # Per-user admin actions (Approve / Disable / Make-or-Remove Admin / Reset Password / Refresh + user detail line)
│   │   ├── LiveTvScene.brs       # Admin Live TV channels list (one-shot LabelList; row-select resolves stream → live player)
│   │   ├── LivePlayerScene.brs   # Dedicated lightweight live Video player (no sessions/progress/transcode/markers)
│   │   ├── PlayerScene.brs     # Video player
│   │   ├── LoginScene.brs      # Login screen
│   │   └── GridItem.brs        # Grid item component
│   ├── player/
│   │   ├── HlsPlayer.brs       # HLS playback handler
│   │   └── SkipButton.brs      # Skip intro/outro button
│   ├── hub/
│   │   ├── HubAuth.brs         # Hub authentication
│   │   └── HubConfig.brs      # Hub configuration
│   ├── syncplay/
│   │   ├── SyncPlayTimeSync.brs # NTP-style time synchronization
│   │   └── SyncPlayService.brs  # SyncPlay WebSocket service
│   ├── pages/
│   │   ├── HomePage.brs        # Home page controller
│   │   ├── LibraryPage.brs      # Library page controller
│   │   └── SettingsPage.brs    # Settings page controller
│   └── data/
│       └── Theme.brs           # Theme constants
├── tests/
│   ├── unit/                   # Unit tests
│   ├── hub/                    # Hub mode tests
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
3. Verify correct server URL in app settings
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
