# Channel Art Image Generation Guide

**For**: Art Team / Brand Team  
**Purpose**: Provide correct specifications for all Roku channel art assets  
**Last updated**: 2026-08-07

---

## ⚠️ R6.2 — Required for Roku Store Certification

All images in this guide are **required for Roku Store certification**. Incorrect dimensions are a **submission blocker** — the Roku Developer Relations team will reject the channel package if any art asset is off by even 1 pixel.

Current status:
- ❌ `icon-focus-hd.png` — 540×405 px (needs **290×218 px**) — **WRONG**
- ❌ `icon-focus-sd.png` — 214×144 px (needs **246×140 px**) — **WRONG**
- ❌ `icon-side-hd.png` — 175×29 px (needs **176×110 px**) — **WRONG**
- ❌ `splash-sd.png` — 960×540 px (needs **720×480 px**) — **WRONG**
- ✅ `splash-hd.png` — 1280×720 px — **CORRECT**
- ✅ `splash-fhd.png` — 1920×1080 px — **CORRECT** (added to manifest 2026-08-07)

**All four wrong-dimension files must be regenerated before the channel can be submitted to the Roku Store.**

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

## Current State (as of 2026-08-07)

The following images **exist but have incorrect dimensions** — they need to be regenerated:

| File                  | Current Size   | Required Size     | Status    |
| --------------------- | -------------- | ----------------- | --------- |
| `icon-focus-hd.png`   | 540 × 405 px   | **290 × 218 px**  | ❌ WRONG  |
| `icon-focus-sd.png`   | 214 × 144 px   | **246 × 140 px**  | ❌ WRONG  |
| `icon-side-hd.png`    | 175 × 29 px    | **176 × 110 px**  | ❌ WRONG  |
| `splash-sd.png`       | 960 × 540 px   | **720 × 480 px**  | ❌ WRONG  |

The following images **exist and are correct** — no changes needed:

| File                  | Size           | Status |
| --------------------- | -------------- | ------ |
| `splash-hd.png`       | 1280 × 720 px  | ✅ OK  |
| `splash-fhd.png`      | 1920 × 1080 px | ✅ OK (newly added) |
| `placeholder.png`     | 280 × 380 px   | ✅ OK  |

---

## Regeneration Checklist

- [ ] `icon-focus-hd.png` — resize/crop to **290 × 218 px**
- [ ] `icon-focus-sd.png` — resize/crop to **246 × 140 px**
- [ ] `icon-side-hd.png` — recreate at **176 × 110 px** (current is too narrow)
- [ ] `splash-sd.png` — resize to **720 × 480 px**

**Output location**: `/home/sites/phlix/phlix-roku-client/images/`

**After regeneration**: Verify with `file *.png` or image viewer that dimensions match exactly.

---

## Notes for Designers

- Roku automatically applies rounded corners and a subtle drop shadow to icons — do NOT include these in the artwork
- All icons should work on both light and dark Roku themes
- The Phlix brand color is `#1a1a2e` (dark blue-black) for backgrounds
- PNG-24 preferred for icons with gradients or complex shading
- PNG-8 acceptable for simple solid-color splash screens
