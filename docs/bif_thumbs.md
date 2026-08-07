# Trickplay Thumbnail Specification (BIF Format)

**For**: Phlix Media Server Development Team  
**Purpose**: Document the Roku trickplay thumbnail requirement and current server gap  
**Last updated**: 2026-08-07 (revised after a server-side review — see [Revision notes](#revision-notes))

---

## Overview

Roku's Video node supports **trickplay thumbnails** — a strip of preview images that appear during rewind/fast-forward scrubbing, giving users visual feedback of their position in the video. This is separate from and in addition to the standard seek bar.

**Trickplay thumbnails on Roku require the binary BIF (BIF Image Format)** format, not the sprite-sheet format that the current Phlix server provides.

---

## Current State (as of 2026-08-07)

| Component       | Status | Detail |
| --------------- | ------ | ------ |
| **Server — routes** | ⚠️ PARTIAL | Beyond `sprite.jpg` + `timeline.json` there is a whole `src/Media/Streaming/Trickplay/` subsystem (`TrickplayGenerator`, `TrickplayController`, `TrickplayResult.index_xml`) and three registered routes, one of which the code itself calls *"BIF index XML"*. Closer to BIF than a bare gap. |
| **Server — producer** | 🚨 DEAD | **`StreamManager::setTrickplay()` has no callers**, so `TrickplayGenerator` never runs and those routes serve files nothing writes. This is the real blocker — see [The producer is unreachable](#-the-real-blocker-the-producer-is-unreachable). |
| **Server — `.bif`** | ❌ GAP | No binary BIF is produced or served anywhere. |
| **Roku client** | ❌ NOT WIRED | `bifDisplay` appears **nowhere** in this repo. P2-S5 **deliberately removed** the trickplay plumbing — see [Client integration](#client-integration-not-done-work-required-here). |

### What the Server Currently Provides

The server provides a sprite-sheet JPEG + JSON timeline:

```
GET /api/v1/media/{id}/trickplay          → MediaItemController::getTrickplay
Response: {
  "sprite_url": "https://server/media/items/{id}/sprite.jpg",
  "timeline_url": "https://server/media/items/{id}/timeline.json",
  "frame_count": 120,
  "interval_ms": 5000
}
```

⚠️ Note the `/v1`. Every Phlix media route is under `/api/v1`; the manifest entry is
`GET /api/v1/media/{id}/trickplay` (`ApplicationRouterWirePathGuardTest::ROUTE_MANIFEST:343`).

- `sprite.jpg` — a **grid** of thumbnail frames, not a horizontal strip. `MediaAssetGenerationJob.php:35`
  documents `DEFAULT_TRICKPLAY_COUNT = 60` as a **10×6 grid** at 160×90.
  🔴 **The server disagrees with itself here:** `config/trickplay.php` declares
  `grid_columns => 8, grid_rows => 4` (= 32 tiles), `interval_seconds => 10`, `thumb_width => 160`,
  `thumb_height => 90`, `jpeg_quality => 72`. Do not depend on either figure until the server work
  resolves which one is live.
- `timeline.json` — maps timestamps to positions in the sprite image.

**Also already registered**, and closer to BIF than the sprite pair:

```
GET /trickplay/{jobId}/index.xml          — described in-code as "BIF index XML"
GET /trickplay/{jobId}/sprite.jpg
GET /trickplay/{jobId}/thumb-{index}.jpg  — serves bif_NN.jpg / bif_NN.png
```

### 🚨 The real blocker: the producer is unreachable

**`StreamManager::setTrickplay()` has no callers.** The server's own test states it —
`tests/Unit/Media/MediaAsset/TrickplayEnabledGateTest.php:29`. As a result
`getTrickplayController()` returns null, the generator path throws
`RuntimeException('TrickplayGenerator is not configured. Call setTrickplay() first.')`, and
**`TrickplayGenerator` never runs**. `index.xml` and `bif_NN.jpg` are never written, so the three
routes above are live routes over files nothing produces.

`config/trickplay.php` has `'enabled' => true` — this is not switched off, it is simply not wired.

There are also **two producers, only one reachable**: the dead `TrickplayGenerator`, and
`MediaAssetGenerationJob::generateTrickplaySprites()` → `FfmpegRunner::generateTrickplaySprites()`,
which the media-asset worker does reach. Server step **S275** resolves which is live before building
anything on top of either.

### What Roku Requires

Roku's `Video` node has a `bifDisplay` field that accepts a **BIF file URL**. The BIF file is a binary format with a specific header structure.

**Roku expects**: A remote URL (or `pkg://` local path) to a `.bif` file that gets downloaded to the device.

**The `Video` node field**: `m.videoPlayer.bifDisplay = "https://server/api/v1/media/{id}/trickplay.bif"`

---

## BIF File Format

BIF is a 64-byte header, followed by an **index**, followed by concatenated **JPEG** images. All
integers are little-endian `uint32`.

```
Header (64 bytes)
  [8 bytes]   Magic: 0x89 'B' 'I' 'F' 0x0d 0x0a 0x1a 0x0a
  [4 bytes]   Version
  [4 bytes]   Number of images (N)
  [4 bytes]   Timestamp multiplier — milliseconds per timestamp unit
  [44 bytes]  Reserved (zero)

Index ((N + 1) × 8 bytes)
  [4 bytes]   Timestamp (in multiplier units)
  [4 bytes]   Absolute byte offset of that image from the start of the file
  … one pair per image, then a final terminating entry:
  [4 bytes]   0xFFFFFFFF
  [4 bytes]   End-of-file offset

Image data
  JPEG files, concatenated, each at the offset its index entry declares.
```

🔴 **Three things an earlier draft of this document got wrong**, kept here because getting any of
them wrong produces a file Roku *silently ignores* — and per "Client integration" below, a bad BIF
and no BIF look identical on the device:

- The magic is **8 bytes**, not the 4-byte `0x42494600`.
- The header is **64 bytes**, not 32 — and it does **not** carry frame width/height. Dimensions are
  whatever the embedded JPEGs are.
- The frames are **JPEG images**, not raw `width × height × 3` RGB. There is also an **index**
  between the header and the data; without it Roku cannot seek to a frame.

**Total file size**: 64 + 8 × (N + 1) + the sum of the JPEG sizes.

### Example BIF Generation (Python)

The offsets are the whole difficulty: each index entry holds an **absolute** offset, so the index
must be sized before any image is written. Compute the data start as
`64 + 8 × (N + 1)` and accumulate from there.

```python
import struct

BIF_MAGIC = b'\x89BIF\x0d\x0a\x1a\x0a'   # 8 bytes
HEADER_LEN = 64
INDEX_ENTRY = 8

def create_bif(jpeg_blobs, interval_ms, output_path, version=0):
    """
    jpeg_blobs:  list of encoded JPEG byte strings, in playback order.
                 NOT PIL images and NOT raw RGB — BIF embeds JPEG files verbatim.
    interval_ms: milliseconds represented by one timestamp unit.
    """
    n = len(jpeg_blobs)

    # Every offset is absolute, so the index must be laid out before the data.
    data_start = HEADER_LEN + INDEX_ENTRY * (n + 1)

    index, offset = bytearray(), data_start
    for i, blob in enumerate(jpeg_blobs):
        index += struct.pack('<II', i, offset)   # (timestamp unit, absolute offset)
        offset += len(blob)
    # Terminator: sentinel timestamp + end-of-file offset.
    index += struct.pack('<II', 0xFFFFFFFF, offset)

    with open(output_path, 'wb') as f:
        f.write(BIF_MAGIC)
        f.write(struct.pack('<I', version))
        f.write(struct.pack('<I', n))
        f.write(struct.pack('<I', interval_ms))
        f.write(b'\x00' * 44)                    # reserved → 64-byte header
        f.write(index)
        for blob in jpeg_blobs:
            f.write(blob)
```

Timestamps here are index units multiplied by `interval_ms`. If frames are not evenly spaced, write
the real unit value per frame instead of `i`.

Generating the JPEGs with ffmpeg — note these are **separate files**, one per frame, not a grid:

```bash
# One 160x90 JPEG every 10s, matching config/trickplay.php's interval_seconds.
ffmpeg -i input.mkv -vf "fps=1/10,scale=160:90" -q:v 4 frames/bif_%05d.jpg
# then feed sorted(frames/*.jpg) to create_bif(..., interval_ms=10000)
```

⚠️ If the server instead reuses its existing **grid** sprite, the tiles must be cut back out into
individual JPEGs first — a grid cannot be embedded as BIF frames.

---

## Server Changes Required

⚠️ **Before any of these: the producer gap above has to close.** All three options assume something
generates thumbnails today. Nothing on the `TrickplayGenerator` path does.

### Option A: Generate BIF on-demand

Add a new endpoint that generates a BIF file from the video file:

```
GET /api/v1/media/{id}/trickplay.bif

Response: Binary BIF file
Content-Type: application/octet-stream
```

**Pros**: No storage overhead, always matches current video  
**Cons**: CPU-intensive for large videos, adds latency on first scrub

🔴 **No longer the recommendation.** phlix-server is a **resident Workerman worker**, so shelling
ffmpeg across a whole video during a scrub blocks the event loop for every other request on that
worker. If on-demand is chosen anyway it must run off-loop with a timeout and a stated worst-case
first-scrub latency. **Option B is the current recommendation.**

### Option B: Pre-generate and cache BIF files  ← recommended

Generate BIF files during media import/encoding and store alongside the sprite assets:

```
/storage/trickplay/{id}/trickplay.bif
```

**Pros**: Fast lookup, can use CDN caching  
**Cons**: Storage cost, requires re-generation on re-encode

### Option C: Convert existing sprite to BIF on ingest

When a new item is added, convert the sprite.jpg + timeline.json into a BIF file automatically.

---

## Client integration — NOT done, work required here

🔴 **An earlier draft of this document claimed the client was "already wired" and that no client
changes would be needed. That is not the case**, and it matters, because it means shipping the server
half alone will change nothing on the device.

Measured in this repo:

- `grep -rn "bifDisplay" --include=*.brs --include=*.xml .` → **zero matches**.
- `components/DetailScene.brs:701-704` — *"P2-S5: trickplay BIF previews are not wired on Roku … The
  dead `m.trickplay` plumbing was **removed** to avoid leaving write-only state (server gap: no BIF
  URL is currently exposed)."*
- `components/PlayerScene.brs:272-273` — *"P2-S5: trickplay was **removed** — `m.trickplay` was
  write-only dead plumbing."*

So the plumbing was deliberately deleted, not left waiting for data.

### What has to be re-added

1. **PlayerScene.brs** — request trickplay data during playback initialisation.
2. **PlayerScene.brs** — when the response carries a non-empty `trickplay_bif_url`, set
   `m.videoPlayer.bifDisplay = url`.
3. **Absent URL stays a no-op** — no thumbnails, no crash, no error. Keep this tolerant permanently:
   under Option B the BIF does not exist until the item's asset job has run, so an absent field is a
   normal steady state, not a transitional one.

⚠️ **`bsc` will not catch a misspelled `bifDisplay`.** Per this repo's own quality-gates note, the
compiler does not validate that a field exists on the declared node type — a typo produces silence,
which is indistinguishable from a missing BIF *and* from a malformed one. Verify on a device.

The client expects the API response for a media item to include:
```json
{
  "id": "...",
  "stream_url": "...",
  "trickplay_bif_url": "https://server/api/v1/media/{id}/trickplay.bif"
}
```

---

## Required Server API Changes

0. **Close the producer gap first** — wire `StreamManager::setTrickplay()` or delete the dead path,
   and settle which of the two producers actually writes to disk. Everything below is inert until
   thumbnails exist.

1. **Add `trickplay_bif_url` to media item response**  
   Include it **only when the artifact is present on disk**. An unconditional field advertises a
   capability the server will not honour — the same mistake as returning an MCP scope for a tool that
   is switched off.

2. **Implement BIF generation endpoint**  
   `GET /api/v1/media/{id}/trickplay.bif` → returns binary BIF file.  
   ⚠️ New routes must be added to `ApplicationRouterWirePathGuardTest::ROUTE_MANIFEST` with an exact
   compare. `/trickplay/` already has three sibling routes and a prefix-ordering comment at
   `Application.php:835`, so a new one can be absorbed by an existing pattern if registered carelessly.

3. **Update API documentation**  
   Document the new `trickplay_bif_url` field and the `/api/v1/media/{id}/trickplay.bif` endpoint.

---

## Timeline

Two halves, and **both are required** — the earlier claim that the client needed no changes was wrong.

1. **Server (plan step S275):** close the producer gap, emit a spec-correct `.bif`, serve it, and add
   `trickplay_bif_url` when the file exists.
2. **Roku client (this repo):** re-add the plumbing P2-S5 removed and set `bifDisplay`.

Trickplay thumbnails appear once both have landed. Shipping only the server half changes nothing
visible on the device.

---

## References

- [Roku Developer Documentation — Trickplay Thumbnails](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes.md#bifdisplay)
- [Roku BIF Format Specification](https://developer.roku.com/docs/developer-program/media-playback/mjpeg-bif.md)

---

## Revision notes

**2026-08-07 — revised after a server-side review** against `phlix-server` (`0ce70c02`+) and this repo
(`aaf7cfc`), carried out while filing the server work as plan step **S275**. The request and its intent
were right; five factual claims were not, and have been corrected **in place** above rather than
annotated at the end:

| # | Was | Now |
|---|---|---|
| 1 | BIF = 4-byte magic `0x42494600`, 32-byte header, raw RGB frames | 8-byte magic, 64-byte header, `(timestamp, offset)` index terminated by `0xFFFFFFFF`, **JPEG** images. The old spec would produce a file Roku silently ignores — and the doc contradicted itself, since its own ffmpeg line piped `-c:v mjpeg`. |
| 2 | "Client integration (Already Done)"; "no client code changes needed" | **Not wired.** `bifDisplay` has zero matches in this repo; P2-S5 deliberately *removed* the plumbing. Client work is required and is tracked here. |
| 3 | `GET /api/media/{id}/trickplay` | `GET /api/v1/media/{id}/trickplay` |
| 4 | `sprite.jpg` is a horizontally-stitched strip | It is a **grid** — and the server disagrees with itself about its size (`10×6 = 60` in code vs `8×4 = 32` in `config/trickplay.php`). |
| 5 | Current state = sprite + timeline only | Also an entire `src/Media/Streaming/Trickplay/` subsystem and three registered routes, one called "BIF index XML" in-code. |

Plus one finding not visible from this repo: **`StreamManager::setTrickplay()` has no callers**
(`TrickplayEnabledGateTest.php:29`), so the generator never runs and those routes serve files nothing
writes. That is the actual blocker, and it is why "Server Changes Required" now opens with step 0.

Option A (on-demand generation) was demoted from "recommended" because phlix-server is a resident
Workerman worker and an in-request ffmpeg pass would block the event loop.
