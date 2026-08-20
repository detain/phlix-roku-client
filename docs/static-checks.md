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

## CI enforcement

`scripts/verify-runtime.sh` is a hard gate (fails the run on any issue) in two workflows:

- `.github/workflows/lint.yml` — job `lint`, step `verify-runtime (hard gate - fails on any issue)`.
- `.github/workflows/package.yml` — job `lint-verify-runtime`, on which the `package` job's `needs:` depends (so a violation blocks `package`, and by extension `package-signed` and `release-latest`).

Previously the script hardcoded 8 `/home/sites/phlix/...` absolute paths. In CI it crashed at Check 11 with FileNotFoundError, so checks 11-19 had never executed in CI, and downstream `package` / `package-signed` / `release-latest` jobs were skipped (a skipped job counts as success). The script now derives `REPO` from its own location and `SERVER_DIR="${PHLIX_SERVER_DIR:-$(dirname "$REPO")/phlix-server}"`, exports both to its python heredocs, and contains zero hardcoded host paths. `lint.yml` previously ran it with `|| true`, so it could never fail the run.

All 19 checks now contribute to the exit code: checks 1-7 and 12-13 previously printed violations but never set `VIOLATIONS` (so the build stayed green); they now set `VIOLATIONS=1`. Per-check python failures no longer abort the whole run (`PYRET`/`PYOUT` accumulation) — all checks execute and print, and the script exits `$((VIOLATIONS))`.

## Cross-repo reference (Check 14)

Check 14 is the S115 type-drift check: it compares the `media_items.type` ENUM documented in `source/lib/Utilities.brs` (lines 853-855, 13 members) against the authoritative server schema in `phlix-server/migrations/*.sql`. The reference is scoped by the regex `ALTER TABLE media_items MODIFY COLUMN type ENUM(...)`; the member-richest matching migration wins — today `034_media_items_type_audiobook.sql` with 13 members.

In CI the reference crosses the repo boundary: the workflow clones the public `detain/phlix-server` repo (`git clone --depth 1 --branch master https://github.com/detain/phlix-server.git ../phlix-server`) as a sibling directory before running the script, so `$(dirname "$REPO")/phlix-server` resolves identically to the local sandbox layout. Locally the sibling checkout is the default; `PHLIX_SERVER_DIR` overrides it.

## Regression test

`tests/scripts/verify-runtime-portable.sh` is a standalone regression test (run with `bash tests/scripts/verify-runtime-portable.sh`). It builds a scratch CI layout in /tmp, proves the script runs from an arbitrary location with a sibling phlix-server, asserts checks 11-19 all execute, and asserts a deliberately-broken input (audiobook removed from the ENUM comment) makes the script exit non-zero.
