# Static Checks — R0.7

Static runtime-defect checker for phlix-roku-client.
Source: `scripts/verify-runtime.sh`

| # | Check Name | Defect Class | Audit Source | Description |
|---|-----------|--------------|-------------|-------------|
| 1 | Storage.factory misuse | Boot-fatal &hEC | §5.1/R0.2 | Direct `Storage.get/set/delete/clear` calls |
| 2 | m.top.Close() | Boot-fatal &hF4 | §5.2/R0.4 | `m.top.Close()` on Scene nodes |
| 3 | ContentEmitter XML | Invalid node | R0.5 | `<ContentEmitter />` stub element |
| 4 | caption1Icon/handle:// | Invalid field/URI | R0.5 | Non-existent PosterGrid field/invalid URI |
| 5 | halign= XML attr | Wrong attribute | R0.6 | `halign=` should be `horizAlign=` |
| 6 | ObserveField callback missing | Runtime silent failure | §5.5 | `ObserveField("x","Y")` callback Y undefined |
| 7 | FindNode target missing | Runtime error | §5.5 | `FindNode("x")` target id absent from XML |
| 8 | Invalid Video field | Runtime silent drop | §5.6 | `m.videoPlayer.FIELD` non-existent field |
| 9 | Invalid Roku key | Logic bug | §3.6 | `OnKeyEvent` invalid remote key comparison |
| 10 | Render-thread network | Performance/crash | §5.3 | `ApiClient.wait/sync` outside ApiTask |
| 14 | media_items.type ENUM drift | Logic bug / silent UI loss | S115 | Server ENUM vs client comment + PlayableTypes subset |
| 19 | hardcoded i18n strings | Translation gaps | R7.12 | Hardcoded user-facing strings in SettingsScene/DetailScene/Utilities |
