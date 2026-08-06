# Publishing to the Roku Store

This guide covers the end-to-end workflow for submitting Phlix to the Roku Channel Store.

---

## Overview

| Artifact | How it's made | Where it runs | Cert required? |
|---|---|---|---|
| `phlix.zip` (unsigned) | `make package` | Sideloaded to any dev-enabled Roku | No |
| `phlix-X.X.X.pkg` (signed) | `make package-signed` | Roku Channel Store | **Yes — real cert from Roku** |

- **Sideloading** (`make install` + `phlix.zip`): Fast iteration, any dev-enabled device, does not require store certification.
- **Store submission** (`make package-signed` + `.pkg`): Requires a signed `.pkg` built with a real Roku code signing certificate.

---

## Prerequisites

1. **Roku Developer Account**
   - Sign up at https://developer.roku.com
   - Pay the one-time $50 registration fee (required to publish to the store)

2. **rokudev CLI**
   ```bash
   npm install -g rokudev
   ```

3. **ROKU_DEV_PASSWORD** environment variable
   - Set to the password for your Roku dev account
   - Add to your shell profile or CI secrets:
     ```bash
     export ROKU_DEV_PASSWORD="your-password-here"
     ```

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

This script:

1. Runs `make package` to produce `phlix.zip`
2. Uses your code signing certificate (at `~/.phlix/phlix-signing.pem`) to sign the package
3. Outputs `phlix-X.X.X.pkg` (the signed artifact for store submission)

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

If you generated a self-signed certificate at `~/.phlix/phlix-signing.pem` for local testing, **it cannot be used for store submission**. Self-signed certificates produce packages that:

- ✅ Can be sideloaded for testing on your own devices
- ❌ Cannot be published to the Roku Channel Store

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

For automated builds in GitHub Actions or similar:

```yaml
- name: Build signed package
  env:
    ROKU_DEV_PASSWORD: ${{ secrets.ROKU_DEV_PASSWORD }}
  run: make package-signed
```

The script will fail with clear error messages if:
- `ROKU_DEV_PASSWORD` is not set
- rokudev/rokupkg is not installed
- The signing certificate is missing or invalid

---

## Troubleshooting

### "Authentication failed" / "Invalid credentials"

Run `rokudev auth` again to refresh your session token.

### "Certificate is not valid for signing"

Your certificate is not a Roku-issued code signing certificate. For store submission, you must obtain one from the Roku developer portal (see Certificate Details above).

### "Package validation failed"

Roku has strict requirements for channel packages. Common issues:

- `sagas.xml` or required assets missing from the package
- Manifest fields (`title`, `major_version`, etc.) invalid
- Icon images not meeting size/format requirements

Run `make validate` before packaging to catch manifest issues early.

---

## Useful Links

- [Roku Developer Program](https://developer.roku.com)
- [Channel Certification Requirements](https://developer.roku.com/docs/developer-program/store-certification.md)
- [rokudev CLI Reference](https://developer.roku.com/docs/developer-program/tools/rokudev.md)
