# Phlex Media Server - Roku Application

A native Roku application for the Phlex Media Server platform. Stream your media library with full playback control, seamless authentication, and progress synchronization.

## Features

- **Secure Authentication**: Device registration with token-based session management
- **Library Browsing**: Browse movies, TV shows, and collections with intuitive navigation
- **HLS Video Playback**: Stream video content with adaptive bitrate support
- **Full Remote Control**: Complete playback control via Roku remote (play, pause, seek, stop)
- **Progress Synchronization**: Track and sync watch progress across sessions
- **Multiple User Support**: Personalized libraries and watch states per user
- **Hub Mode**: Connect to a Phlex Hub for centralized authentication, server discovery, and relay-aware HLS playback through direct-LAN or hub-relay tunnel

## Prerequisites

### Required
- **Roku Device**: Any Roku device with developer mode enabled
- **Phlex Media Server**: Running instance accessible on your network
- **Roku Developer Account**: For sideloading apps

### Development Tools
- **Roku SDK**: For packaging and deployment ( rokupkg )
- **BrightScript Editor**: VS Code extension "BrightScript" by彩虹 (or any editor)
- **curl**: For direct device communication
- **zip**: For creating packages

### Network Requirements
- Roku device and Phlex Media Server on the same network
- Phlex Media Server API accessible from Roku device

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
git clone https://github.com/your-org/phlex-roku.git
cd phlex-roku

# Review and update manifest if needed
# Edit: manifest title, version, icons
```

### 3. Install Dependencies

No external dependencies required. BrightScript is natively supported by Roku devices.

### 4. Configure Server Connection

The app will prompt for server URL on first launch, or you can pre-configure:

```bash
# Edit the default server URL in source/components/PhlexApp.brs
# Or set via Settings within the app
```

### 5. Hub Mode (Optional)

Hub Mode allows you to connect to a Phlex Hub for centralized authentication and multi-server access:

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

# This creates: phlex.zip
```

### Install to Device

```bash
# Install to configured Roku IP
make install ROKU_IP=192.168.1.100 ROKU_DEV=rokudev ROKU_PASSWORD=yourpass

# Or install with rokupkg
rokupkg --install phlex.zip
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
zip -r phlex.zip manifest source images

# Sideload via curl
curl -v -u rokudev:password -X POST \
    http://192.168.1.100:8060/install/app \
    -F "archive=@phlex.zip" \
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
# Run integration tests (requires running Phlex server)
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
3. Upload your packaged app (phlex.zip)
4. Complete store listing details
5. Submit for review

### Private Channel Testing

```bash
# Sideload directly for testing
make install

# Or use roku's dev channel mechanism
```

## API Endpoints

The app communicates with these Phlex API endpoints:

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

## Project Structure

```
phlex-roku/
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
│   │   ├── PhlexApp.brs       # Main app controller
│   │   ├── HomeScene.brs       # Home screen
│   │   ├── LibraryScene.brs    # Library browser
│   │   ├── DetailScene.brs     # Item detail view
│   │   ├── PlayerScene.brs     # Video player
│   │   ├── LoginScene.brs      # Login screen
│   │   └── GridItem.brs        # Grid item component
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

1. Verify Phlex Media Server is running
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
- Documentation: [Phlex Wiki](https://github.com/your-org/phlex-roku/wiki)
