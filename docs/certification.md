# Roku Channel Certification Checklist

**Source:** Roku Channel Certification Requirements (developer.roku.com)
**Date Retrieved:** August 2026
**Channel:** Phlix (com.phlix)
**Version:** 1.0.1

---

## 1. General Certification Requirements

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1.1 | Application launches without crashing | UNVERIFIED — needs device | |
| 1.2 | Application responds to user input within 2 seconds | UNVERIFIED — needs device | |
| 1.3 | No ANR (Application Not Responding) dialogs | UNVERIFIED — needs device | |
| 1.4 | Memory usage acceptable (< 512MB typical) | UNVERIFIED — needs device | |
| 1.5 | All required manifest keys present | PASS | R6.1 fixed manifest (mm_icon_focus_sd, splash_min_time, rsg_version, screensaver keys) |
| 1.6 | Version numbers consistent (manifest, package.json, Makefile) | PASS | All 1.0.1 per R6.1 |

---

## 2. Deep Linking & Content Discovery

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 2.1 | Cold-launch deep linking (contentId + mediaType) | PASS | Implemented R6.3: main.brs reads args, validates, routes |
| 2.2 | Warm deep linking (roInput) | PASS | Implemented R6.4: roInput in main loop, HandleWarmDeepLink |
| 2.3 | supports_input_launch in manifest | PASS | Added in R6.4 |
| 2.4 | Deep link works when not authenticated | PASS | Deep link stashed to Storage, resumed after login |
| 2.5 | Content-not-found handled gracefully | PASS | ShowContentNotFoundDialog (R3.1) |

---

## 3. User Interface & UX

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 3.1 | All remote keys handled (including instantreplay, info) | PASS | R6.9: instantreplay, info implemented; intervals corrected |
| 3.2 | Transport key intervals follow convention | PASS | R6.9: rewind/fastforward=30s, left/right=10s |
| 3.3 | Back button exits channel from root | PASS | R0.3: OnKeyEvent returns false at root |
| 3.4 | Focus does not steal from user | PASS | R5.10: HomeScene.SetFocus only on first load |
| 3.5 | Trickplay thumbnails on scrub | FAIL | R6.10: Server provides sprite sheets, Roku requires BIF format |
| 3.6 | Channel icon appears correctly in Roku UI | FAIL | R6.2: All image assets are placeholder sizes (166B-6917B) |
| 3.7 | Splash screen displays correctly | FAIL | R6.2: Splash images are placeholders (237-426 bytes) |

---

## 4. Video Playback

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 4.1 | Video plays without stuttering | UNVERIFIED — needs device | |
| 4.2 | Audio track switching works | PASS | R6.7: audioTrack field used (was false claim it didn't work) |
| 4.3 | Subtitle track selection works | PASS | R6.6: currentSubtitleTrack (string TrackName) |
| 4.4 | Global caption mode respected | PASS | R6.5: roDeviceInfo.GetCaptionsMode observed |
| 4.5 | Caption toggle in overlay | PASS | R6.5: On/Off/Instant replay/When mute |
| 4.6 | Playback progress reported | PASS | R4.11: progress buffered until API session ready |
| 4.7 | Playback completion reported | PASS | R4.4: completeSession implemented |
| 4.8 | Transcode handled when needed | PASS | R1.5: transcode flow exists; R6.8: CanDecodeVideo gating |

---

## 5. Network & Performance

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 5.1 | Network calls off render thread | PASS | R1.1-R1.3: ApiTask pattern |
| 5.2 | Login does not block render thread | PASS | R1.2: async login |
| 5.3 | Paging implemented for large lists | PASS | R5.1-R5.4: LibraryScene, SearchScene, SeriesScene, SeasonScene, FavoritesScene |
| 5.4 | HTTP response caching | PASS | R5.9: LRU cache, 50 entries, 60s TTL |
| 5.5 | Device capability detection | PASS | R6.8: CanDecodeVideo, GetVideoMode, GetModel, memory tier |
| 5.6 | No 1Hz no-op timer | PASS | R5.5: removed dead timer |
| 5.7 | Exponential backoff on polling | PASS | R5.6: transcode poll 1s→1.5x→10s cap, 120s budget |

---

## 6. Error Handling

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 6.1 | User-visible error dialogs | PASS | R3.1: ShowErrorDialog, ShowContentNotFoundDialog |
| 6.2 | Network errors handled gracefully | PASS | R3.2-R3.5: various error handlers |
| 6.3 | Playback errors shown to user | PASS | R3.1: SetProgressWarning, ShowProgressAuthError |

---

## 7. SyncPlay / Watch Together

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 7.1 | SyncPlay session can be joined | PASS | R4.0-R4.2: SyncPlay contracts, REST, field casing |
| 7.2 | Progress buffered until session exists | PASS | R4.11: m.apiSessionReady tracking |
| 7.3 | Heartbeat not sent when not joined | PASS | R4.12: m.yourId check in SendTimePing |
| 7.4 | SyncPlay task lifecycle managed | PASS | R5.10: control="stop" on leave/close |

---

## 8. Certification Items from client_missing.md §3.10

| # | Issue | Fix Phase | Status |
|---|-------|-----------|--------|
| 8.1 | No deep linking | R6.3, R6.4 | PASS |
| 8.2 | No trick-play UI / pause indicator | R2.1, R2.2, R6.10 | FAIL (server BIF gap) |
| 8.3 | No user-visible error dialogs | R3.1 | PASS |
| 8.4 | Global caption setting ignored | R6.5 | PASS |
| 8.5 | Missing mm_icon_focus_sd, placeholder art, wrong splash dims | R6.1, R6.2 | FAIL (art not commissioned) |
| 8.6 | Back never exits the channel | R0.3 | PASS |
| 8.7 | Blocking network on the render thread at login | R1.2 | PASS |

---

## FAIL Items Requiring Attention

1. **Trickplay (3.5):** Server provides sprite sheet format; Roku requires BIF binary format. Server-side gap: getTrickplay endpoint does not expose a BIF URL.
2. **Channel icon (3.6):** All image assets are placeholder sizes (166B-6917B). Proper 24-bit PNG assets must be commissioned per R6.2 findings.
3. **Splash screen (3.7):** Splash images are placeholders (237-426 bytes). Must be replaced with proper branded assets.

## UNVERIFIED Items Needing Device

- Application launches without crashing (1.1)
- Application responds to user input within 2 seconds (1.2)
- No ANR dialogs (1.3)
- Memory usage acceptable (1.4)
- Video plays without stuttering (4.1)
- All playback quality checks

## Required for Submission

1. Commission proper channel art (7 assets per R6.2)
2. Server-side: expose BIF URL in getTrickplay endpoint, OR implement sprite-based preview in R2.1 overlay
