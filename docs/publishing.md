# Publishing to the Roku Store

This guide covers the end-to-end workflow for submitting Phlix to the Roku Channel Store.

---

## Overview

| Artifact | How it's made | Where it runs | Cert required? |
|---|---|---|---|
| `phlix.zip` (unsigned) | `make package` | Sideloaded to any dev-enabled Roku | No |
| `phlix-X.X.X.pkg` (signed) | `make package-signed` | Roku Channel Store | **Yes — real cert from Roku** |
| `phlix-X.X.X-dev-signed.pkg` | `make package-signed` with a self-signed cert | **Nowhere — a signing-chain smoke artifact**: the portal rejects it and devices install the unsigned zip | Self-signed (dev) |

- **Sideloading** (`make install` + `phlix.zip`): Fast iteration, any dev-enabled device, does not require store certification.
- **Store submission** (`make package-signed` + `.pkg`): Requires a signed `.pkg` built with a real Roku code signing certificate.

---

## Version Discipline (read this before any store submission)

The version triple a build ships is **derived, never hand-edited**:

```
package.json "version" = MAJOR.MINOR.PATCH
   └─ scripts/derive-version.sh  (--major / --minor / --build)
        └─ build/manifest: major_version=MAJOR  minor_version=MINOR  build_version=PATCH
```

- `make package` rewrites the version fields in the **build** copy of the
  manifest from `package.json` every run; the checked-in root `manifest`
  carries the same triple for human readers and verify-runtime **Check 18**
  reddens CI when the two drift. Editing `major_version`/`minor_version`/
  `build_version` in the root manifest directly changes nothing that ships.
- **Roku store law:** every submission must carry a strictly greater
  `(major, minor, build)` triple than the last accepted one. Since
  `build_version` is only the package.json patch component, the real flow is:
  **bump `package.json` "version" in its own commit before building the
  submission `.pkg`** — e.g. `npm version patch --no-git-tag-version` (or edit
  the field), then `make package-signed`. The `1.0.1` triple has never been
  bumped in this repo's history; a second store submission without a bump
  cannot succeed.
- The CI-build-number machinery the version script once carried
  (`CI_BUILD_NUMBER`/`GITHUB_RUN_NUMBER`-derived builds) was dead code and was
  **deleted under M-ROKU-09**. No shipped path derives `build_version` from
  git or CI. If CI-derived versions are ever wanted, they must land together
  with their consumer and this section's rewrite (see CHECK40).

---

## Release Vehicles and Rollback

What exists **today** (pinned against drift by verify-runtime Check 40):

- **Sideload/QA channel — a single rolling `latest`.** The `Package` workflow
  publishes a GitHub **prerelease** named `latest` on every `master` push.
  Before publishing, the job deletes the previous `latest` release *and its
  tag* (`gh release delete latest --yes --cleanup-tag`), then recreates it
  from the freshly built `phlix.zip`. Consequence, stated honestly: **the
  previous sideload build is destroyed by the next push.** `git ls-remote
  --tags origin` shows exactly one tag (`latest`) — there are no per-build
  versioned tags or releases.
- **There is no GitHub-side rollback.** A QA-verified "known good" build can
  only survive to the next push if someone downloads its `phlix.zip` in time
  (Actions artifacts from the run are re-zipped on download; the Release
  asset is the bare sideload zip). Keep any build you may need to return to.
- **Store-side version management lives at the Roku Developer Portal**, not
  in this repo — which approved build is live is portal state. Nothing here
  automates or documents a portal-side revert procedure.
- **Planned / owner decision pending:** versioned per-build tags + versioned
  GitHub Releases (with or without keeping the rolling `latest`) and a
  written rollback procedure were proposed in the 2026-10 estate review
  (M-ROKU-09) and are **not yet shipped**. Do not "fix" the workflow toward
  them without the owner decision; changing the vehicle reddens CHECK40 on
  purpose — rotate the workflow, this document, and the pin together.

---

## Prerequisites

1. **Roku Developer Account**
   - Sign up at https://developer.roku.com
   - Pay the one-time $50 registration fee (required to publish to the store)

2. **rokudev CLI**
   ```bash
   npm install -g rokudev
   ```

3. **Roku account credentials**
   - You type them when `rokudev auth` prompts (item 5). There is **no
     password environment variable to export** — nothing in the build or
     signing chain reads one. (An earlier revision of this document claimed
     the signing script required such a variable; no component ever read
     it. The false claim was deleted under M-ROKU-10, and verify-runtime
     Check 41 R1 keeps claim and behavior consistent.)

4. **Roku Device in Developer Mode**
   - Enable developer mode on your Roku: https://developer.roku.com/docs/developer-program/getting-started.md

5. **Authentication**
   ```bash
   rokudev auth
   ```
   This stores a session token so you don't need to retype credentials.

---

## Full Publishing Flow

### Step 1 — Authenticate with rokudev (one-time)

```bash
rokudev auth
# Enter your Roku developer email and password when prompted
```

### Step 2 — Build the signed package

```bash
make package-signed
```

The script:

1. Runs `make package` to produce `phlix.zip` (self-verified layout)
2. Uses the certificate at `~/.phlix/phlix-signing.pem`, generating a
   self-signed development certificate only if none exists (and, in a
   terminal, only with your consent)
3. Determines the certificate's nature (self-signed vs Roku-issued) and
   names the output to that truth: `phlix-X.X.X-dev-signed.pkg` for a
   self-signed cert (a signing-chain smoke artifact — the summary explicitly
   marks it NOT uploadable, and nothing installs a `.pkg` on a device:
   device testing runs on the unsigned `phlix.zip`), `phlix-X.X.X.pkg` for
   a Roku-issued cert (the store submission artifact)
4. Fails loud — minting nothing — when no signer CLI is installed, when
   signing itself fails (there is no fallback that renames the unsigned zip
   into a `.pkg`; that mislabel was the M-ROKU-10 defect), or when the
   certificate cannot be read

### Step 3 — Submit to the Roku Developer Portal

1. Log in to https://developer.roku.com
2. Go to **Dashboard → Channels → Phlix**
3. Click **Upload Version** and select your `.pkg` file
4. Fill in the required fields:
   - Version notes
   - Certification checklist (all items must be answered)
   - Screenshot requirements
5. Submit for review

Review times are typically 3–5 business days.

---

## Certificate Details

### Development Certificate (self-signed)

If you generated a self-signed certificate at `~/.phlix/phlix-signing.pem`
— or let `scripts/package-signed.sh` auto-mint one when it runs
non-interactively — the `phlix-X.X.X-dev-signed.pkg` it signs is a
**signing-chain smoke test**, nothing more. Packages from a self-signed
certificate:

- ✅ Exercise the whole chain end to end — `make package`, certificate
  inspection, signer invocation — with no store credentials
- ❌ Cannot be published to the Roku Channel Store (the portal requires a
  Roku-issued code signing certificate)
- ❌ Cannot be installed on a device either: Roku's dev-mode installer
  accepts the unsigned `phlix.zip` and nothing else — no `.pkg`, self-signed
  or genuine, is device-installable. To test on a device, run `make install`

### Production Certificate (Roku-issued)

To get a real code signing certificate for store submission:

1. In the Roku Developer Portal, go to **Dashboard → Certificates**
2. Click **Request a Code Signing Certificate**
3. Roku will email you a CSR (Certificate Signing Request) workflow
4. After verification, Roku issues a real `.pem` certificate
5. Replace `~/.phlix/phlix-signing.pem` with the Roku-issued cert before running `make package-signed`

**Important:** The certificate is tied to your developer account. Don't share it.

---

## CI/CD Integration

**CI does not sign packages, by design of the credentials involved.** The
`Package` workflow builds and publishes only the sideload `phlix.zip` (the
rolling `latest` prerelease described above). Store packaging is a manual
workstation step: `rokudev auth` once, the Roku-issued certificate at
`~/.phlix/phlix-signing.pem`, then `make package-signed`.

An earlier revision showed a CI snippet exporting a password secret into
`make package-signed` and promised the script would "fail if it is not
set" — no component ever read that secret, and a workflow job that cannot
install a signer is worse than no job: it lies green while skipped and
blocks everything downstream the day its gate secret is armed. That stub
job was deleted under M-ROKU-10. If CI signing is ever wanted, it must land
with real signer provisioning (`npm ci`, `rokudev`, certificate handling)
in the same job — verify-runtime Check 41 R4 reddens any workflow that runs
`make package-signed` without one.

What the script genuinely fails loud about (each enforced in
`scripts/package-signed.sh`): no signer CLI installed, signing command
failure (no fallback artifact), unreadable or refused certificate, and an
undeterminable package version.

---

## Troubleshooting

### "Authentication failed" / "Invalid credentials"

Run `rokudev auth` again to refresh your session token.

### "Certificate is not valid for signing"

Your certificate is not a Roku-issued code signing certificate. For store submission, you must obtain one from the Roku developer portal (see Certificate Details above).

### "Package validation failed"

Roku has strict requirements for channel packages. Common issues:

- required trees missing from the archive root — a channel package is the
  `manifest` at the root plus `source/`, `components/`, `images/` and
  `locale/`, those entries and only those; `make package` assembles exactly
  that and `scripts/verify-package.sh` fails loud on any other layout
- Manifest fields (`title`, `major_version`, etc.) invalid
- Icon images not meeting size/format requirements

Run `make validate` before packaging to catch manifest issues early.

---

## Useful Links

- [Roku Developer Program](https://developer.roku.com)
- [Channel Certification Requirements](https://developer.roku.com/docs/developer-program/store-certification.md)
- [rokudev CLI Reference](https://developer.roku.com/docs/developer-program/tools/rokudev.md)
