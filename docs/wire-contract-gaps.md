# Wire-contract gaps (client-side ledger)

Gaps where the Roku client needs a server/contract field that does not exist
yet. The client renders only what the wire carries; it never fabricates state.

## WC-1 (ROK-24 / ROK-S23): per-user watched/progress on children lists — CLOSED 2026-11-13

- **Need:** season and episode lists (`SeriesScene`, `SeasonScene`, loaded by
  `components/EpisodeListTask.brs` via `GET /api/v1/libraries/{id}/items`
  with `parentId`) should show a watched mark and a progress indicator.
- **Finding at dispatch (phlix-server tip):** `WebPortalRouter::getLibraryItems`
  returns `MediaItemShaper`-shaped rows with NO `user_data` block. The
  add-only `user_data` block (`favorite`, `rating`, `like_level`, `watched`)
  exists only on the item-detail response and the favorites list
  (`MediaUserDataController`). No per-item resume position is on the list rows.
- **Decision:** per the plan's risk gate, the client does not render watched
  or progress marks blind. The per-user state source it already uses is the
  detail fetch (`DetailScene.brs`, `m.userData.watched`) plus the
  continue-watching rows for resume offsets; per-row N+1 detail fetches for a
  list are rejected (memory/latency on 512 MB devices).
- **Ticket (to phlix-server / phlix-contracts):** add an ADD-ONLY
  `user_data: { watched: bool, position_ticks?: int }` to rows of
  `GET /api/v1/libraries/{id}/items` (at minimum when `parentId` is set),
  mirroring the detail endpoint's shape. Once present, the client adds the
  mark in `EpisodeListTask.brs` where the ContentNode is built.

- **Resolution (2026-11-13, owner ruling: build end to end):** phlix-server
  `553e56f` adds the add-only per-row `user_data`
  (`{watched, position_ticks, duration_ticks, progress_percent}`) to
  `GET /api/v1/media?parentId=` rows (the endpoint `getLibraryItems` actually
  calls in drill-down mode), and `@phlix/contracts` `2d87e75` types it. The
  client renders it in `EpisodeListTask.brs` via `WatchStateCaption`
  (`source/lib/Utilities.brs`): the localized `common.watched` word for a watched
  row, a whole-percent string for a started row, nothing when the block is
  absent (older server). Both grids set `caption1NumLines`/`caption2NumLines`
  so the second description line renders.
