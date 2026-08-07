# Trickplay Thumbnail Specification (BIF Format)

**For**: Phlix Media Server Development Team  
**Purpose**: Document the Roku trickplay thumbnail requirement and current server gap  
**Last updated**: 2026-08-07

---

## Overview

Roku's Video node supports **trickplay thumbnails** — a strip of preview images that appear during rewind/fast-forward scrubbing, giving users visual feedback of their position in the video. This is separate from and in addition to the standard seek bar.

**Trickplay thumbnails on Roku require the binary BIF (BIF Image Format)** format, not the sprite-sheet format that the current Phlix server provides.

---

## Current State (as of 2026-08-07)

| Component     | Status | Detail                                                                 |
| ------------- | ------ | --------------------------------------------------------------------- |
| **Server**    | ❌ GAP | Server currently exposes sprite-sheet images (`sprite.jpg` + `timeline.json`) |
| **Roku client** | ✅ OK | PlayerScene code is fully wired for trickplay; just lacks valid BIF data |

### What the Server Currently Provides

The server provides a sprite-sheet JPEG + JSON timeline:

```
GET /api/media/{id}/trickplay
Response: {
  "sprite_url": "https://server/media/items/{id}/sprite.jpg",
  "timeline_url": "https://server/media/items/{id}/timeline.json",
  "frame_count": 120,
  "interval_ms": 5000
}
```

- `sprite.jpg` — a horizontally-stitched strip of thumbnail frames (each frame ~160×90 px)
- `timeline.json` — maps timestamps to X-offset positions in the sprite image

### What Roku Requires

Roku's `Video` node has a `bifDisplay` field that accepts a **BIF file URL**. The BIF file is a binary format with a specific header structure.

**Roku expects**: A remote URL (or `pkg://` local path) to a `.bif` file that gets downloaded to the device.

**The `Video` node field**: `m.videoPlayer.bifDisplay = "https://server/media/items/{id}/trickplay.bif"`

---

## BIF File Format

The BIF format is a simple binary structure:

```
[4 bytes]  Magic number: 0x42494600 ("BIF\0")
[4 bytes]  Version (always 0)
[4 bytes]  Frame count (uint32)
[4 bytes]  Reserved
[4 bytes]  Frame width (uint32)
[4 bytes]  Frame height (uint32)
[4 bytes]  Per-frame interval in ms (uint32)
[n bytes]  Frame data — each frame is width×height×3 bytes (RGB), packed consecutively
```

**Total file size**: ~frame_count × frame_width × frame_height × 3 + 32 bytes header

### Example BIF Generation (Python)

```python
import struct

def create_bif(frames, width, height, interval_ms, output_path):
    """
    frames: list of PIL.Image objects (RGB)
    width, height: frame dimensions in pixels
    interval_ms: time between frames in milliseconds
    output_path: where to write the .bif file
    """
    with open(output_path, 'wb') as f:
        # Header
        f.write(b'BIF\x00')           # Magic
        f.write(struct.pack('<I', 0)) # Version
        f.write(struct.pack('<I', len(frames)))  # Frame count
        f.write(struct.pack('<I', 0)) # Reserved
        f.write(struct.pack('<I', width))   # Frame width
        f.write(struct.pack('<I', height))   # Frame height
        f.write(struct.pack('<I', interval_ms))  # Interval
        
        # Frame data
        for frame in frames:
            f.write(frame.tobytes())
```

Or use ffmpeg to generate a BIF from a video:
```bash
ffmpeg -i input.mkv -vf "fps=0.2,scale=160:90" -c:v mjpeg -f image2pipe -frames:v 120 | \
  python3 convert_to_bif.py > output.bif
```

---

## Server Changes Required

### Option A: Generate BIF on-demand (Recommended)

Add a new endpoint that generates a BIF file from the video file:

```
GET /api/media/{id}/trickplay.bif

Response: Binary BIF file
Content-Type: application/octet-stream
```

**Pros**: No storage overhead, always matches current video  
**Cons**: CPU-intensive for large videos, adds latency on first scrub

### Option B: Pre-generate and cache BIF files

Generate BIF files during media import/encoding and store alongside the sprite assets:

```
/storage/trickplay/{id}/trickplay.bif
```

**Pros**: Fast lookup, can use CDN caching  
**Cons**: Storage cost, requires re-generation on re-encode

### Option C: Convert existing sprite to BIF on ingest

When a new item is added, convert the sprite.jpg + timeline.json into a BIF file automatically.

---

## Client Integration (Already Done)

The Roku client code is already wired:

1. **PlayerScene.brs** — during playback initialization, the client requests trickplay data from the server
2. **PlayerScene.brs** — if the server returns a `trickplay_bif_url` field, it sets `m.videoPlayer.bifDisplay = url`
3. **If no BIF URL is provided**, trickplay thumbnails simply won't appear (no crash, no error)

The client expects the API response for a media item to include:
```json
{
  "id": "...",
  "stream_url": "...",
  "trickplay_bif_url": "https://server/api/media/{id}/trickplay.bif"
}
```

---

## Required Server API Changes

1. **Add `trickplay_bif_url` to media item response**  
   Modify the media item serialization to include `trickplay_bif_url` when trickplay data exists.

2. **Implement BIF generation endpoint**  
   `GET /api/media/{id}/trickplay.bif` → returns binary BIF file

3. **Update API documentation**  
   Document the new `trickplay_bif_url` field and `/api/media/{id}/trickplay.bif` endpoint

---

## Timeline

Once the server team implements the BIF endpoint and returns `trickplay_bif_url` in media item responses, trickplay thumbnails will work automatically on Roku — no client code changes needed.

---

## References

- [Roku Developer Documentation — Trickplay Thumbnails](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes.md#bifdisplay)
- [Roku BIF Format Specification](https://developer.roku.com/docs/developer-program/media-playback/mjpeg-bif.md)
---

## Server-side review — corrections (2026-08-07)

Reviewed against `phlix-server` at `0ce70c02`+ and this repo at `aaf7cfc` before filing the server
work as **plan step S275**. The intent of this document is right and the request is now queued. But
**five of its factual claims do not hold**, and one of them would produce a file Roku cannot read.
Each correction below cites what was checked.

### 1. 🔴 The BIF binary layout above is wrong

The spec in "BIF File Format" describes a 4-byte magic `0x42494600`, a 32-byte header, and **raw RGB
frame data** (`width × height × 3`). The real Roku/`biftool` format is:

```
[8 bytes]   Magic: 0x89 'B' 'I' 'F' 0x0d 0x0a 0x1a 0x0a     (not 4 bytes, not 0x42494600)
[4 bytes]   Version
[4 bytes]   Number of images
[4 bytes]   Timestamp multiplier (ms per timestamp unit)
[44 bytes]  Reserved                                          → 64-byte header, not 32
[8×(N+1)]   Index: (timestamp uint32, absolute offset uint32) pairs,
            terminated by an entry whose timestamp is 0xFFFFFFFF and whose
            offset is the end-of-file offset
[...]       Image data — JPEG files, concatenated             (not raw RGB)
```

⚠ **The document contradicts itself here:** the Python snippet writes `frame.tobytes()` (raw RGB),
while the ffmpeg example immediately below pipes `-c:v mjpeg`. The ffmpeg line is the one closer to
correct. Anyone implementing from the Python snippet as written will emit a file that Roku silently
ignores — and "no crash, no error" (your own §Client Integration point 3) means the failure will look
identical to the current state.

**Please verify the layout against Roku's published spec and correct §"BIF File Format" in place**,
since this doc is the artifact the server work will be implemented from.

### 2. 🔴 "Client Integration (Already Done)" is not accurate — this is the item that needs your action

§Client Integration says PlayerScene already sets `m.videoPlayer.bifDisplay` and that "no client code
changes needed". In this repo today:

- `grep -rn "bifDisplay" --include=*.brs --include=*.xml .` returns **zero matches**.
- `components/DetailScene.brs:701-704` — *"P2-S5: trickplay BIF previews are not wired on Roku … The
  dead `m.trickplay` plumbing was **removed** to avoid leaving write-only state"*.
- `components/PlayerScene.brs:272-273` — *"P2-S5: trickplay was **removed** — `m.trickplay` was
  write-only dead plumbing"*.

So the plumbing was deliberately deleted, not left in place awaiting data. **The client work is real
work and it is on your side**: re-add the request, read `trickplay_bif_url` from the response, and set
`bifDisplay`. Worth noting for whoever does it — `bsc` will not catch a wrong `Video` node field name,
so a typo'd `bifDisplay` fails silently exactly like a missing BIF.

### 3. The endpoint path is missing `/v1`

Document says `GET /api/media/{id}/trickplay`. The registered route is
**`GET /api/v1/media/{id}/trickplay`** → `MediaItemController::getTrickplay`
(`ApplicationRouterWirePathGuardTest::ROUTE_MANIFEST:343`). Same for the proposed `.bif` route.

### 4. The sprite is a grid, not a horizontal strip

§"What the Server Currently Provides" describes `sprite.jpg` as "a horizontally-stitched strip".
`MediaAssetGenerationJob.php:35` documents `DEFAULT_TRICKPLAY_COUNT = 60` as a **10×6 grid** at
160×90. ⚠ Note the server disagrees with *itself*: `config/trickplay.php` declares
`grid_columns => 8, grid_rows => 4` (32 tiles). That inconsistency is part of S275; do not depend on
either number until it is resolved.

### 5. The "current state" table understates what the server already has

The table lists only `sprite.jpg` + `timeline.json`. There is also an entire
`src/Media/Streaming/Trickplay/` subsystem — `TrickplayGenerator`, `TrickplayController`,
`TrickplayResult` (which carries an `index_xml` property) — and three registered routes:

```
GET /trickplay/{jobId}/index.xml          — described in-code as "BIF index XML"
GET /trickplay/{jobId}/sprite.jpg
GET /trickplay/{jobId}/thumb-{index}.jpg  — serves bif_NN.jpg / bif_NN.png
```

The server is considerably closer to BIF than "❌ GAP" suggests.

### 6. 🚨 The blocker you could not have seen: the producer is unreachable

This is why the assets are missing, and it outranks the format question.

**`StreamManager::setTrickplay()` has no callers.** The server's own test says so —
`tests/Unit/Media/MediaAsset/TrickplayEnabledGateTest.php:29`. Consequences:
`getTrickplayController()` returns null, the generator path throws
`RuntimeException('TrickplayGenerator is not configured. Call setTrickplay() first.')`, and
`TrickplayGenerator` therefore **never runs**. `index.xml` and `bif_NN.jpg` are never written. The
three routes above are live routes over files nothing produces.

`config/trickplay.php` has `'enabled' => true` — so this is not switched off, it is simply not wired.

There also appear to be **two producers**, only one of them reachable: the dead `TrickplayGenerator`,
and `MediaAssetGenerationJob::generateTrickplaySprites()` → `FfmpegRunner::generateTrickplaySprites()`,
which the media-asset worker does reach. S275 resolves which is live before anything is built on top.

### What happens next

- **S275** (phlix-server) covers: resolving the two-producer question, wiring or deleting the dead
  path, emitting a spec-correct `.bif`, serving it, and adding `trickplay_bif_url` to the media-item
  response **only when the artifact exists on disk** — an unconditional field would advertise a
  capability the server will not honour.
- **Your side:** correct §"BIF File Format" and §"Client Integration" above, then re-add the client
  plumbing. Once the server emits `trickplay_bif_url`, nothing else is needed from the server.
- ⚠ One design note for S275 that affects you: on-demand generation is being treated with suspicion
  because the server is a resident Workerman worker and shelling ffmpeg across a whole video during a
  scrub would block the event loop. If the answer ends up being pre-generation, the BIF may not exist
  for an item until its asset job has run — so the client must keep tolerating an absent
  `trickplay_bif_url` rather than assuming it appears once the feature "ships".
