# Sparkle Release Setup

## GitHub Actions packaging

`.github/workflows/release-packages.yml` is the available release-packaging path in this repository.

- It runs on `macos-15`, builds `灵动岛.app` with ad-hoc signing (`CODE_SIGN_IDENTITY=-`), and packages a styled DMG.
- It does not use an Apple Developer certificate or perform Apple notarization. Gatekeeper may prevent the resulting app from opening normally.
- Ordinary branch pushes do not trigger packaging. Pushing a `v*` tag builds and publishes the matching release. Manual dispatch defaults to a draft release, which can be reviewed before publication.
- It verifies that the tag matches `MARKETING_VERSION`. Increment `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` before creating a new release tag.
- It can rerun after a partially failed asset upload. Reruns replace assets with the same names.
- In-app Sparkle updates are optional. With no Sparkle keys configured, the DMG is for manual installation and the built app leaves its updater unconfigured.

## Optional Sparkle configuration

Use a key pair controlled by this repository's owner. Do not reuse an upstream project's public key unless you also own the matching private key and intentionally share its update channel.

Set the following in **Settings → Secrets and variables → Actions**:

| Type | Name | Purpose |
| --- | --- | --- |
| Repository variable | `SPARKLE_PUBLIC_ED_KEY` | Public EdDSA key embedded in the app |
| Repository secret | `SPARKLE_PRIVATE_ED_KEY` | Matching private key used to sign update assets |

The workflow requires both values together, or neither. This check verifies that configuration is complete; the operator must supply a matching key pair. With both configured, the workflow generates and uploads `appcast.xml`. The feed URL is derived from `github.repository`:

```text
https://github.com/OWNER/REPO/releases/latest/download/appcast.xml
```

That URL resolves only after a non-prerelease release containing `appcast.xml` is published. Keep future builds on the same key pair so existing installations can verify their updates.

### Generate and export keys

Use Sparkle's `generate_keys` tool from the Sparkle package downloaded by Xcode or an official Sparkle tools distribution. Generate the key pair, then export the private key to a protected local file:

```bash
/path/to/Sparkle/bin/generate_keys
umask 077
mkdir -p .sparkle-keys
/path/to/Sparkle/bin/generate_keys -x .sparkle-keys/eddsa_private_key
```

Copy the displayed public key to the repository variable and the exported file's contents to the repository secret. Never commit the private key. `.sparkle-keys/` is gitignored. Do not regenerate an existing release key pair without planning update-key migration.

## Trigger packaging

Update the app's version and build number and commit the changes first. The workflow accepts a tag matching the app version, such as `v1.2.2` for `MARKETING_VERSION = 1.2.2`.

- **Tag push:** pushing a new `v*` tag automatically builds and publishes its release.
- **Manual dispatch:** select **Release Packages → Run workflow**, enter an existing version tag, and keep `draft` enabled to leave the created or updated release as a draft. Review the DMG and notes before publishing it. This does not suppress a separate automatic run caused by pushing that tag.

A normal source-code upload does not create a tag or release.

## Local build configuration

For a local build that uses your own Sparkle feed, copy `Config/LocalSecrets.example.xcconfig` to the gitignored `Config/LocalSecrets.xcconfig` and configure:

```xcconfig
_XC_SLASH = /
SPARKLE_APPCAST_URL = https:$(_XC_SLASH)/github.com/OWNER/REPO/releases/latest/download/appcast.xml
SPARKLE_PUBLIC_ED_KEY = YOUR_PUBLIC_ED_KEY
```

`xcconfig` treats `//` as a comment, so compose URLs with the slash helper. Leave both values empty for a build without automatic updates. GitHub Actions supplies its configuration directly to `xcodebuild`; it does not depend on your local secrets file.

## Local release tooling status

`scripts/create-release.sh` is a legacy entrypoint that calls `scripts/package-release.sh`. That dependency and `scripts/package-unsigned.sh` are absent from this repository, so the full local signed/notarized release flow is unavailable. Do not use `create-release.sh` as a working one-command release path.

`scripts/build.sh`, `scripts/create-styled-dmg.sh`, and `scripts/generate-keys.sh` remain in the tree, but the latter's legacy release-step hints do not restore the missing packager. `create-styled-dmg.sh` accepts `TRAE_FLOW_DMG_BACKGROUND_SOURCE` to override the tracked installer artwork. GitHub Actions packages the DMG directly and does not call the missing scripts.
