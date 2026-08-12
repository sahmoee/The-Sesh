# The SESH.

The SESH. is a privacy-minded cannabis companion for adults. It brings reflective session journaling, mood and strain tracking, insights, music memories, and optional community features into a native SwiftUI application.

The app is designed for responsible use where cannabis is legal. It does not provide medical advice, facilitate sales, or replace local laws and professional guidance.

## Highlights

- Session and mood journaling with reusable routines
- Strain, stash, wishlist, and comparison tools
- Personal insights and journey history
- Spotify-connected music memories
- Optional social graph, rooms, lounge, and push notifications
- Home-screen widget and deep links
- Internal QA tickets with screenshots, offline retry, synchronized reports, fix explanations, verification, and refiling

## Requirements

- macOS with [Xcode](https://developer.apple.com/xcode/) and the iOS 26 SDK
- An Apple development team for device signing
- Optional backend features use the [Unified Worker](https://github.com/sahmoee/UnifiedWorker) at `https://api.sowensstudios.com/sesh`

## Setup and build

```bash
git clone https://github.com/sahmoee/The-Sesh.git
cd The-Sesh
open "The SESH..xcodeproj"
```

Select the **The SESH.** scheme, configure signing, and run on a connected iPhone or iPad. If an example secrets file is present, copy it to its ignored local counterpart and populate only the integrations you use.

Generic physical-device build:

```bash
xcodebuild -project "The SESH..xcodeproj" \
  -scheme "The SESH." \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Repository map

| Path | Purpose |
| --- | --- |
| [`The SESH./`](The%20SESH./) | Main application sources |
| [`SeshWidget/`](SeshWidget/) | Widget extension |
| [`SeshTests/`](SeshTests/) | Tests |
| [`AGENTS.md`](AGENTS.md) | Mandatory coding-agent and ticket workflow |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## QA workflow

The in-app QA button opens the project ticket queue. New and edited tickets are persisted locally first, then uploaded automatically with screenshot and device/build context. A fixed ticket must explain **What was fixed**. Testers can select **Verify Fix** or **Refile — still broken**; refiling retains the ticket identity and history while capturing current evidence.

Synced artifacts are materialized under `Documents/Reports/Sesh` in the shared development workspace. Coding agents must follow [`AGENTS.md`](AGENTS.md) before planning or building.

## Safety, privacy, and security

- Age confirmation and responsible-use messaging are product requirements.
- Never commit tokens, Apple keys, personal journals, social exports, or QA screenshots.
- See [`PRIVACY.md`](PRIVACY.md), [`SECURITY.md`](SECURITY.md), and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- Apple distribution requirements are documented in the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Contributing

Inspect the shared QA inbox first, keep Worker contracts backward compatible, add regression coverage, verify a generic device build, and update the changelog and cross-project documentation when behavior changes.

## License

See [`LICENSE.md`](LICENSE.md).
