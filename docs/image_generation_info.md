# Channel Art Image Generation Guide

**For**: Art Team / Brand Team  
**Purpose**: Provide correct specifications for all Roku channel art assets  
**Last updated**: 2026-08-07

---

## ⚠️ R6.2 — Required for Roku Store Certification

All images in this guide are **required for Roku Store certification**. Incorrect dimensions are a **submission blocker** — the Roku Developer Relations team will reject the channel package if any art asset is off by even 1 pixel.

Current status — **all assets regenerated 2026-08-07, every dimension now matches spec**:
- ✅ `icon-focus-hd.png` — 290×218 px — **CORRECT** (was 540×405)
- ✅ `icon-focus-sd.png` — 246×140 px — **CORRECT** (was 214×144)
- ✅ `icon-side-hd.png` — 176×110 px — **CORRECT** (was 175×29)
- ✅ `splash-sd.png` — 720×480 px — **CORRECT** (was 960×540)
- ✅ `splash-hd.png` — 1280×720 px — **CORRECT**
- ✅ `splash-fhd.png` — 1920×1080 px — **CORRECT** (added to manifest 2026-08-07)
- ✅ `placeholder.png` — 280×380 px — **CORRECT**

No dimension blockers remain for Roku Store submission.

> ⚠️ **Worth a second look before submitting:** the *previous* `icon-focus-hd.png` was
> 540×405, which is exactly Roku's **Channel Poster (HD)** size. If 540×405 was in fact the
> intended asset and this guide's 290×218 is the legacy `mm_icon_focus_hd` figure, confirm
> against current Roku Developer docs before submission — this repo now follows the numbers
> written in this guide.

---


## Overview

The Phlix Roku channel requires correctly-sized artwork in 5 categories. All images must be PNG format with no alpha transparency issues on any background.

---

## Required Images

### 1. App Icons (Focus/Hover State)

These icons appear when the user navigates to the channel on the Roku home screen and hovers over it.

| File                  | Required Dimensions | Notes                                |
| --------------------- | ------------------- | ------------------------------------ |
| `icon-focus-hd.png`  | **290 × 218 px**    | HDTV (1280×720) home screen icon     |
| `icon-focus-sd.png`  | **246 × 140 px**    | SDTV (720×480) home screen icon      |
| `icon-side-hd.png`   | **176 × 110 px**    | Side panel / Leanback player icon    |

**Design notes**:
- Must be readable at small sizes
- Transparent background (Roku applies rounded corners + drop shadow automatically)
- Leave ~10px padding inside the bounds
- Use the channel's primary color scheme and logo

---

### 2. Splash Screens (Launch Screens)

These appear during channel startup while the app initializes.

| File                  | Required Dimensions | Notes                                      |
| --------------------- | ------------------- | ------------------------------------------ |
| `splash-sd.png`       | **720 × 480 px**    | SD launch screen                           |
| `splash-hd.png`       | **1280 × 720 px**   | HD launch screen                           |
| `splash-fhd.png`      | **1920 × 1080 px**  | Full HD launch screen (new — REQUIRED)     |

**Design notes**:
- Solid or gradient background (`#1a1a2e` dark blue-black recommended as brand color)
- Centered logo or app name
- Must NOT contain animated elements
- `splash_min_time=2000` in manifest means display for at least 2 seconds
- Keep text minimal — users stare at this during load

---

### 3. Placeholder / Missing Art

Used when real artwork hasn't loaded or isn't available.

| File               | Required Dimensions | Notes                                 |
| ------------------ | ------------------- | ------------------------------------- |
| `placeholder.png`  | Any reasonable size | Currently: 280 × 380 px (5:7 portrait ratio) |

**Design notes**:
- Simple branded placeholder with channel logo or icon
- Should look intentional, not broken

---

## Current State (as of 2026-08-07, post-regeneration)

Every asset was regenerated on 2026-08-07 from a single design system, so the icon set and
the splash set now share one lockup:

| File                  | Size           | Status |
| --------------------- | -------------- | ------ |
| `icon-focus-hd.png`   | 290 × 218 px   | ✅ OK  |
| `icon-focus-sd.png`   | 246 × 140 px   | ✅ OK  |
| `icon-side-hd.png`    | 176 × 110 px   | ✅ OK  |
| `splash-sd.png`       | 720 × 480 px   | ✅ OK  |
| `splash-hd.png`       | 1280 × 720 px  | ✅ OK  |
| `splash-fhd.png`      | 1920 × 1080 px | ✅ OK  |
| `placeholder.png`     | 280 × 380 px   | ✅ OK  |

`splash-hd.png`, `splash-fhd.png`, and `placeholder.png` already had correct dimensions but
were regenerated anyway: the previous files were featureless noise with no logo, so leaving
them would have shipped a splash set that changed appearance between resolutions.

---

## The brand lockup

There was no logo asset in the repo, so the mark is derived from the colors already used in
`components/*.xml`:

- **Mark** — a disc with a `#ff6b35 → #ffd700` diagonal gradient and a white rounded-corner
  play triangle, optically centered (nudged right of true center).
- **Wordmark** — "PHLIX" in Lato Black, white, ~9% letterspacing.
- **Lockup** — mark above wordmark, centered. The same lockup scales across all six assets.
- **Ground** — `#1a1a2e → #0d0d1a`, with a warm radial glow behind the mark and a light grain
  pass that prevents gradient banding on 8-bit TV panels.

### Icon backgrounds are opaque, not transparent

The "Design notes" below call for transparent icon backgrounds. The generated icons are
**opaque full-bleed** instead, because Roku composites home-screen icons as solid tiles — a
transparent icon shows the user's wallpaper through it, and the guide's own Overview asks for
"no alpha transparency issues on any background". Opaque also satisfies "must work on both
light and dark Roku themes" without a second art pass. Rounded corners and drop shadows are
**not** baked in, per the design notes — Roku still applies those.

---

## Regeneration

All seven assets are produced by one script, checked in at `tools/gen_channel_art.py`:

```sh
python3 tools/gen_channel_art.py     # requires Pillow + numpy; writes to images/
```

**Output location**: `/home/sites/phlix/phlix-roku-client/images/`

**After regeneration**: verify with `file images/*.png` that dimensions match the table above.

---

## Notes for Designers

- Roku automatically applies rounded corners and a subtle drop shadow to icons — do NOT include these in the artwork
- All icons should work on both light and dark Roku themes
- The Phlix brand color is `#1a1a2e` (dark blue-black) for backgrounds
- PNG-24 preferred for icons with gradients or complex shading
- PNG-8 acceptable for simple solid-color splash screens
