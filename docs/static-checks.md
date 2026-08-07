# Static Checks — R0.7

Static runtime-defect checker for phlix-roku-client.
Source: `scripts/verify-runtime.sh`

| # | Check Name | Defect Class | Audit Source | Description |
|---|-----------|--------------|-------------|-------------|
|  1 | Storage.factory misuse | Boot-fatal &hEC | §5.1/R0.2 | Direct `Storage.get/set/delete/clear` calls |
|  2 | m.top.Close() | Boot-fatal &hF4 | §5.2/R0.4 | `m.top.Close()` on Scene nodes |
|  3 | ContentEmitter XML | Invalid node | R0.5 | `<ContentEmitter />` stub element |
|  4 | caption1Icon/handle:// | Invalid field/URI | R0.5 | Non-existent PosterGrid field/invalid URI |
|  5 | halign= XML attr | Wrong attribute | R0.6 | `halign=` should be `horizAlign=` |
|  6 | ObserveField callback missing | Runtime silent failure | §5.5 | `ObserveField("x","Y")` callback Y undefined |
|  7 | FindNode target missing | Runtime error | §5.5 | `FindNode("x")` target id absent from XML |
|  8 | Invalid Video field | Runtime silent drop | §5.6 | `m.videoPlayer.FIELD` non-existent field |
|  9 | Invalid Roku key | Logic bug | §3.6 | `OnKeyEvent` invalid remote key comparison |
| 10 | Render-thread network | Performance/crash | §5.3 | `ApiClient.wait/sync` outside ApiTask |
| 11 | Unguarded Task control=run | Boot-fatal &hEC | R1.4 | `control="run"` without busy/state guard in same function |
| 12 | syncplay/rooms vs /groups | Logic bug | R4.1 | SyncPlay uses /groups endpoint, not /rooms |
| 13 | DELETE on syncplay leave | Logic bug | R4.1 | syncplay leave uses POST, not DELETE |
| 14 | media_items.type ENUM drift | Logic bug / silent UI loss | S115 | Server ENUM vs client comment + PlayableTypes subset |
| 15 | hardcoded localhost URL | Connection failure | R4.10 | No localhost fallback in production code |
| 16 | placeholder channel art | UX / invalid asset | R6.2 | Image file size too small for declared dimensions |
| 17 | echo ERROR pairing | Self-audit / CI reliability | R0.x | echo ERROR commands must set FOUND=1/VIOLATIONS=1/exit 1 |
| 18 | package.json vs manifest drift | Version mismatch | R8.8 | package.json version must match manifest major/minor_version |
| 19 | hardcoded i18n strings | Translation gaps | R7.12 | Hardcoded user-facing strings in SettingsScene/DetailScene/Utilities |
