# The Sesh

A private cannabis journal for reflective, responsible use — session tools, mood and
strain tracking, insights, music memories, and optional adult community spaces.

iOS app. Requires legal-age confirmation on launch.

## Features

- Private session and mood journaling
- Strain and stash tracking with insights over time
- Music memories tied to sessions
- Optional, opt-in adult community spaces
- Home-screen widget

## Requirements

- Xcode 16 or later
- iOS 26 SDK

## Getting started

```bash
git clone https://github.com/sahmoee/The-Sesh.git
cd The-Sesh
open "The SESH..xcodeproj"
```

Select the **The SESH.** scheme and run. If the project ships a
`Secrets.example.xcconfig`, copy it to `Secrets.xcconfig` and fill in your values first.

## Project structure

- `The SESH./` — app sources (Journal, Lounge, Profile, shared UI)
- `SeshWidget/` — home-screen widget extension
- `SeshTests/` — unit tests

## License

See [LICENSE.md](LICENSE.md). Third-party components in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); privacy in [PRIVACY.md](PRIVACY.md).
