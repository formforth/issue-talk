# Contributing

## 1. Development Environment

Use Apple Silicon macOS, Xcode 26 or newer, the iOS Simulator, and Nix with
flakes enabled. Xcode provides the Apple compiler, SDK, device support, and
signing. Nix provides the developer tools and generated pre-commit hooks.

```sh
git clone https://github.com/formforth/issue-talk.git
cd issue-talk
nix develop
open IssueTalk.xcodeproj
```

After installing or updating Xcode, launch it once, accept its license, and
install the iOS components it offers. Select that installation in Xcode's
Settings > Locations > Command Line Tools. Use the shared `IssueTalk` scheme.

## 2. Install on Your iPhone

You can install a development build directly; TestFlight and an App Store
release are not required. A free Apple Account can use a Personal Team, subject
to Apple's provisioning limits. Free provisioning expires and requires periodic
rebuilding/reinstalling; a paid membership has different signing capabilities.

1. Update the phone to iOS 17 or newer. Its OS must also be supported by the
   selected Xcode installation; update Xcode if the device is listed as
   unavailable. Unlock the phone and connect it to the Mac with a data-capable
   cable. Accept **Trust This Computer** on the phone and the pairing prompts.
2. Add your Apple Account in Xcode > Settings > Accounts. Open
   `IssueTalk.xcodeproj`, choose the **IssueTalk app target**, and open
   **Signing & Capabilities**. Enable **Automatically manage signing** and
   select your own Team or Personal Team.
3. Choose a unique bundle identifier for your account, such as
   `com.yourname.issuetalk`. For repeatable local configuration, copy
   `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`
   and set `DEVELOPMENT_TEAM` and `ISSUE_TALK_BUNDLE_ID`. The local file is
   ignored. If using Xcode's UI instead, keep its personal signing changes out
   of commits. Do not edit the shared scheme to select a personal device.
4. On the phone, enable **Settings > Privacy & Security > Developer Mode**
   when prompted, restart, and confirm. If the setting is absent, pair the
   device with Xcode first. In Xcode > Window > Devices and Simulators, wait
   for pairing and developer support preparation to finish.
5. Select the connected iPhone as the run destination, keep the **Debug**
   configuration, and press **Run** (Command-R). Xcode builds, signs, installs,
   and launches the app. If iOS requests developer trust, follow the displayed
   instructions under Settings > General > VPN & Device Management.
6. The initial screen is the Issue Talk inbox. Open Settings > Diagnostics >
   Audio feasibility to run the debug-only audio probe. Microphone access is
   requested only when you start a recording. No GitHub credential is needed
   for this probe.

After the first cable installation, Xcode's device window can enable connection
via network if the Mac and phone support it. Keep the cable for initial
troubleshooting. To reinstall after provisioning expires, connect and Run again.
Deleting the app removes its local data; back up anything you need first.

Common failures:

| Symptom                                   | Action                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| Bundle identifier cannot be registered    | Pick a unique `ISSUE_TALK_BUNDLE_ID` for your Team.                                         |
| Signing requires a development team       | Select a Team in Signing & Capabilities or fill the ignored local xcconfig.                 |
| Device OS is unsupported                  | Install compatible Xcode and its iOS device support; select it in Locations.                |
| Developer Mode or trust error             | Unlock, pair, enable Developer Mode, restart, and follow the phone's trust prompt.          |
| Build works in Simulator but not on phone | Check device signing and provisioning; CI deliberately builds unsigned Simulator apps.      |
| Microphone permission denied              | Enable Issue Talk under Settings > Privacy & Security > Microphone, then restart the probe. |

Never commit certificates, provisioning profiles, tokens, recordings, or private
Issue content. Review `git diff` before committing, especially after changing
signing in Xcode. The project has an audio background capability for active
audio feasibility testing; it does not grant unrestricted background execution.

For GitHub sign-in, deploy/configure the token broker and OAuth App using
[docs/OAUTH.md](docs/OAUTH.md). The microphone probe works without that setup.

## 3. Local Checks

Follow the same Nix/pre-commit conventions as `i9wa4/dotfiles` and
`i9wa4/tmux-a2a-postman`. Stage new files before Nix checks: flakes only see
files tracked by git.

```sh
git add <changed-files>
nix fmt
nix flake check --print-build-logs
nix develop --command pre-commit run --all-files
cd Packages/IssueTalkCore
swift test
```

On macOS, also run the shared Xcode scheme's tests on an iPhone Simulator
(Command-U). The GitHub Actions `ci` workflow repeats these checks and runs the
history secret scan. All lint/formatting definitions live in the generated
pre-commit configuration in `flake.nix`; do not add independent GHA lint rules.
Keep exactly `flake.nix` and `flake.lock` as Nix configuration files.
`nix build` is not an iOS app build: Xcode owns the app build and signing.

Commit SwiftPM resolution files when adding remote dependencies. Tests use
synthetic fixtures and injected transports, never a personal token or private
repository. API tests must not post to real GitHub Issues.

## 4. Markdown and Pull Requests

`nix fmt` runs the shared formatter configuration. Pre-commit applies
`mdfmt --write` to tracked Markdown, including default heading numbering;
rumdl checks the same files. There are no special root-document exceptions.

Use English PR titles, descriptions, and commit messages. Prefer focused PRs
linked to the relevant Issues. Describe the resulting behavior, validation,
and unverified device requirements. Mark `Closes #N` only when the entire Issue
is implemented; real-device evidence must not be replaced by Simulator claims.
Do not merge your own work without the repository owner's review.

## 5. Physical-Device Measurements

Follow [the feasibility protocol](docs/DEVICE-FEASIBILITY.md) for locked-screen
audio, lifecycle, inference, battery, and interruptions. Store only synthetic,
non-identifying measurements in public PRs. Hardware-dependent results remain
pending until somebody actually performs and records the measurement.

## 6. Share Extension Signing

The app embeds IssueTalkShare. On first use, enable Issue Talk in the iOS share
sheet's More list. Share a GitHub Issue URL from Safari or the GitHub app, then
open Issue Talk. When connected, it imports queued URLs; Import shared Issues
retries explicitly. Invalid URLs are rejected, existing monitored Issues are not
duplicated, and failed imports stay queued. Sharing never posts a comment.

Automatic transfer between the extension and app uses an App Group. Register a
unique group for your Apple Developer team and enable it for **both** the app
bundle ID and its `.share` extension ID. In the ignored Local.xcconfig set:

```text
ISSUE_TALK_APP_GROUP = group.com.yourname.issuetalk
ISSUE_TALK_SHARED_ENTITLEMENTS = Configuration/Shared.entitlements
```

Both targets inherit the same Team and group. Regenerate provisioning profiles
if Xcode cannot enable the capability. Personal Team provisioning does not
provide the App Groups capability: leave these two settings empty to install
without it. The share sheet then offers Copy Issue URL; paste that canonical URL
in the app. The main inbox and manual workflow do not require an App Group.
Simulator CI builds the extension but cannot establish that your team is
entitled to a physical-device App Group. Verify the configured handoff on your
phone.
