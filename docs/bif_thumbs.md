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