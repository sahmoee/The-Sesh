# High Thoughts — App Icon

A fully **opaque** icon (no transparency / no alpha channel) matching the app's
identity: a glowing gold candle flame rising into a stylized cannabis leaf, over
the dark-olive vertical gradient with a subtle gold ring — the same motif as the
Home-screen hero.

## What's included

- `MoodWeedJournal/MoodWeedJournal/Assets.xcassets/AppIcon.appiconset/` — a
  ready-to-use Xcode asset catalog with `Contents.json` and every required iOS
  size (iPhone + iPad + 1024 marketing). **Drop-in.**
- `MoodWeedJournal/Icons/` — standalone copies of each PNG plus the
  `AppIcon-1024-master.png` master, in case you want them outside the catalog.

## Install (Xcode)

The `AppIcon.appiconset` is already in `Assets.xcassets`. Just make sure the
target uses it:

1. Open the project, select the target → **General → App Icons and Launch
   Screen**.
2. Set **App Icon Source** to `AppIcon` (it will find the catalog automatically).
3. Build. The icon appears on the home screen and in the App Store build.

If you use a different asset catalog, drag `AppIcon.appiconset` into it.

## No transparency

Every exported PNG is saved as **RGB with no alpha channel**. This satisfies the
App Store requirement that the 1024×1024 marketing icon contain no alpha /
transparency, and it's the correct choice for this opaque design. iOS applies
its own rounded-corner mask at display time — do not pre-round the corners.

## Sizes exported

20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, and 1024 px (the set covers
@1x/@2x/@3x for iPhone and iPad).

## Regenerating

`make_icon.py` renders the 1024 master; `export_icons.py` slices it into the
catalog and writes `Contents.json`. Tweak the palette constants at the top of
`make_icon.py` (they mirror `Theme.swift`) to restyle.
