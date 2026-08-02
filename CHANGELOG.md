# Changelog

All notable changes to **phlix-roku-client** are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — Screen navigation stack (R0.3)

- **`PushScreen(nodeType, params)`** — creates a child scene, appends it to `m.top`,
  sets focus, records it on the screen stack, and returns the node. The caller drives
  post-push setup (e.g. `scene.LoadLibrary(id, name)`).
- **`PopScreen() as Boolean`** — removes the top scene from the stack, removes it from
  `m.top`, calls `SetFocus(true)` on the newly-exposed node (fixing the pre-stack bug where
  the remote went dead after one Back press), and returns `true`. Returns `false` when the
  stack is empty — the caller must return `false` from `OnKeyEvent` so the Roku OS handles
  the back press and exits the channel (certification item 6).
- **`requestClose` contract** — every pushed child scene declares
  `<field id="requestClose" type="boolean" alwaysNotify="true" />` in its `<interface>`.
  When a scene sets `m.top.requestClose = true` (e.g. an internal Back handler), `PhlixApp`
  automatically calls `PopScreen()` via a registered observer. This lets a child close itself
  without knowing its parent or having a reference to `PhlixApp`.
- **`m.top.Close()` removed** — `Close()` exists on `roSGScreen`, not on `Scene` or `Group`
  nodes. All 22 pushed component XMLs had a `requestClose` field added; no component calls
  `m.top.Close()`.
- **Certification item 6 fixed** — the previous `OnKeyEvent` swallowed Back at the root
  (returned `true` unconditionally) so the channel never exited. `PopScreen()` returning
  `false` from an empty stack now correctly defers to the Roku OS.

### Fixed — `m.top.Close()` replaced with `m.top.requestClose = true` (R0.4)

- **34 call sites migrated** across 29 `.brs` component files in `components/`
- **13 missing XML field declarations added** (`<field id="requestClose" type="boolean" alwaysNotify="true" />`)
- **8 parent scenes wired** with `ObserveField("requestClose", "OnChildRequestClose")` + handler:
  HomeScene, FavoritesScene, MusicScene, AdminScene, CollectionsScene, DetailScene,
  LibraryAdminScene, LiveTvScene

> ⚠️ **Known limitation:** ~13 more parent scenes (~21 `m.top.Append` calls) are **not yet wired**
> with observers. Child scenes in those branches (SearchScene→Series/Season/Detail,
> WatchHistoryScene→…, etc.) that call `m.top.requestClose = true` will have the signal
> silently ignored. This is a pre-existing gap — not a regression introduced by R0.4.

### Fixed — Storage factory misuse causes runtime error `&hEC` on launch

- **`Storage()` can no longer be called directly as an object.** The `source/lib/Storage.brs`
  factory was being used directly at approximately 40 call sites (e.g. `Storage().get(key)`),
  which fails at runtime with error `&hEC` ("Dot operator attempted with invalid left-hand side")
  because `Storage` is a factory function — calling `.get()` on the function value itself is
  invalid BrightScript. A new `GetStorage()` function wraps the factory call and returns the
  object; all 43 call sites across `AppContext`, `ApiClient`, `SyncPlayManager`, `PlayerScene`,
  `PhlixApp`, `LoginScene`, `ServerPickerScene`, and `ConnectScene` have been migrated to use
  `GetStorage()`.
- **User-visible effect:** the channel now boots to the home screen without erroring out on the
  first frame of `PhlixApp.Init`. Before this fix the channel crashed immediately with `&hEC`
  because every code path during init called into Storage before the registry was usable.

### Fixed — Play button for audio/track/audiobook/video items

- **`DetailScene` no longer gates playback on a hardcoded `movie`/`episode`
  pair.** Both the Play-button visibility check and `OnPlayPressed` now call the
  new shared `IsPlayableItem()` / `IsPlayableType()` helpers in
  `source/lib/Utilities.brs`, whose allowlist (`PlayableTypes()`) is the set of
  playable **leaf** members of the server's `media_items.type` ENUM: `movie`,
  `episode`, `video`, `audio`, `track`, `audiobook`. Containers (`series`,
  `season`, `album`, `artist`, `music`) and stream-less types (`book`, `photo`)
  stay non-playable.
- Previously an `audio`/`track`/`audiobook`/`video` item opened a detail page
  with **no Play button**, and pressing Play was a **silent no-op**. This was
  latent: before phlix-server#527 the server's `MediaItemShaper` coerced every
  unlisted type to `"movie"`, so these items reached the client disguised as
  movies and got a Play button by accident. Not user-visible on current
  production data (episode/movie/season/series rows only) — it matters once
  music/audiobook libraries populate.
- Unknown types are treated as **not** playable, so a future ENUM member loses
  its Play button rather than presenting a dead one.

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
