# Changelog

All notable changes to **phlix-roku-client** are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — in-player quality selection (G4)

- **Quality picker overlay** in the player — press **Up** during playback to open a
  right-side panel listing **Auto** (the server-driven multi-variant `master.m3u8`,
  native ABR — the existing default behaviour, byte-unchanged) plus every ABR rung
  the active transcode advertises (e.g. 1080p, 720p, 480p…), highest first, sourced
  from the server's Stream-Quality/ABR **A7** `variants[]` ladder on the transcode
  start/status response (`source/lib/ApiClient.brs` `parseVariants()`). The
  currently-selected row is marked `(current)`. `Back` or `Up` again closes the
  panel without disturbing playback; the video keeps playing behind the overlay.
- **Picking a rung** swaps playback to that variant's own signed HLS media
  playlist (`PlayHls(variant.url)`) and preserves the current playback position
  by seeding the existing resume machinery, so playback picks up where it left
  off rather than restarting. **Picking Auto** returns playback to the
  multi-variant master (native ABR resumes deciding the rung). The choice is
  persisted (`Storage` key `preferred_quality`, value `"auto"` or a rung id) and
  re-applied automatically the next time a transcode becomes ready; if the
  persisted rung isn't present in a later job's (possibly lower) clamped ladder,
  playback falls back to Auto rather than erroring.
- **Graceful no-op** for direct-play (mp4) and legacy/single-variant transcodes:
  since there is no ladder, the picker shows Auto only, with a status line
  explaining there's no fixed-quality ladder for this stream — no crash, no dead
  end.
- Server-A7-dependent: the picker only ever has rungs to offer when talking to a
  server build that populates `variants[]` on the transcode start/status
  response; against an older server (or a legacy job) it degrades to Auto-only,
  matching pre-G4 behaviour exactly.

  **⚠️ Known residual risk — needs an on-device smoke test before this is
  considered fully verified in production.** Reassigning `content` on a *live*
  (playing) `Video` node to switch quality is a scenario this codebase has never
  exercised before; on some Roku firmware/models that reassignment is known to
  emit a transient `state="stopped"` event before `"buffering"`/`"playing"`,
  which — without protection — would be misread as a real stop and tear the
  whole player down instead of switching quality. A one-shot `m.switchingQuality`
  guard in `components/PlayerScene.brs` (`OnQualitySelected` /
  `OnPlayerStateChange`) suppresses exactly that transient stop, and the guard's
  logic was traced and static-analysis-verified sound end-to-end during review,
  but **BrightScript has no host test runner** — `npx bsc` and `make test-unit`
  cannot execute SceneGraph/Video-node state transitions, only device firmware
  can produce them. **Before shipping to real hardware, smoke-test on a real
  Roku:** open the picker (Up) mid-playback, pick a different rung and then
  re-pick Auto, and confirm playback SWITCHES (does not exit to the previous
  screen) and resumes at the prior position — ideally on one model that emits
  the transient stop and one that doesn't, if more than one is available.
