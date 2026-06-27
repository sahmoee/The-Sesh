//
//  AppChangelog.swift
//  The SESH
//
//  Sole source of truth for the in-app "What's New" and the About screen's
//  changelog list.
//
//  ── UPDATE THIS ON EVERY DELIVERY ──────────────────────────────────────────
//  Each fix or new build MUST add (or extend) the top entry here. Checklist:
//    1. Add a new ChangelogVersion at the TOP of `versions` (newest first).
//    2. Set its isLatest: true, and set the PREVIOUS top entry's isLatest: false.
//       Exactly one version may have isLatest: true at any time.
//    3. Keep entries user-facing: what changed and why it matters, not the code.
//    4. The displayed app version/build come from the bundle via BuildConfig —
//       no need to hand-edit those; the `version` strings here are the readable
//       history shown in About.
//  ───────────────────────────────────────────────────────────────────────────
//

import SwiftUI

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

struct ChangelogVersion: Identifiable {
    let id = UUID()
    let version: String        // "1.0.0"
    let buildLabel: String     // "Build 250 · June 2026"
    let headline: String       // short banner line
    let isLatest: Bool
    let entries: [ChangelogEntry]
}

enum AppChangelog {
    // Versioning — "The Sesh (Build) vX.Y.Z":
    //   X (major)  → feature additions / alterations
    //   Y (minor)  → big changes or big fixes
    //   Z (patch)  → small fixes
    // The displayed version/build come from the bundle (see BuildConfig);
    // these entries are the human-readable history. Newest first, exactly one
    // `isLatest: true`.
    static let versions: [ChangelogVersion] = [
        ChangelogVersion(
            version: "25.24.1",
            buildLabel: "June 2026",
            headline: "Smoother screens.",
            isLatest: true,
            entries: [
                ChangelogEntry(icon: "rectangle.stack.fill", tint: Palette.greenBright,
                               title: "Reliability",
                               detail: "Quick Action screens now open more reliably, with no chance of two getting in each other's way."),
            ]),
        ChangelogVersion(
            version: "25.24.0",
            buildLabel: "June 2026",
            headline: "Music that remembers.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "music.note.list", tint: Palette.greenBright,
                               title: "Music + strains",
                               detail: "Songs you play during a sesh are now saved with the strain. See your history and top songs under Track, and your strain pairings and vibes under Me."),
            ]),
        ChangelogVersion(
            version: "25.23.0",
            buildLabel: "June 2026",
            headline: "Status that knows what you're doing.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "circle.circle.fill", tint: Palette.greenBright,
                               title: "Automatic status",
                               detail: "Your status now moves itself: ready when you open the app, rolling up and smoking during a sesh, then vibing and away after. Tap it to set your own, including a custom one."),
            ]),
        ChangelogVersion(
            version: "25.22.0",
            buildLabel: "June 2026",
            headline: "Tools for the sesh.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "slider.horizontal.3", tint: Palette.purple,
                               title: "Session Tools",
                               detail: "While seshing, Home now shows personalizable Session Tools. Tap Edit to choose which tools appear and reorder them, separate from your Quick Actions."),
            ]),
        ChangelogVersion(
            version: "25.21.0",
            buildLabel: "June 2026",
            headline: "Your Home, your shortcuts.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "slider.horizontal.3", tint: Palette.greenBright,
                               title: "Quick Actions",
                               detail: "Home now has personalizable Quick Actions. Tap Edit to choose which actions appear, reorder them, and add as many as you want."),
            ]),
        ChangelogVersion(
            version: "25.20.0",
            buildLabel: "June 2026",
            headline: "Make it yours.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "paintbrush.fill", tint: Palette.greenBright,
                               title: "Appearance",
                               detail: "Theme and icon style now live on one Appearance page. Each theme has a personality, and the Symbols style is now called Minimal."),
            ]),
        ChangelogVersion(
            version: "25.19.0",
            buildLabel: "June 2026",
            headline: "A clearer way to get around.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "square.grid.2x2.fill", tint: Palette.greenBright,
                               title: "New navigation",
                               detail: "The tabs are now Home, Community, Explore, Track, and Me. Each is a hub for a part of the app. Cyphs lives in Community and your sessions live in Track."),
            ]),
        ChangelogVersion(
            version: "25.18.0",
            buildLabel: "June 2026",
            headline: "A bigger icon library.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "square.grid.3x3.fill", tint: Palette.greenBright,
                               title: "New icon art",
                               detail: "Added vintage, midnight, and symbols art for ten more actions like Compare Strains, Friends, Badges, and Scan Product."),
            ]),
        ChangelogVersion(
            version: "25.17.0",
            buildLabel: "June 2026",
            headline: "Blunts join the lineup.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "smoke.fill", tint: Palette.greenBright,
                               title: "Blunt method",
                               detail: "Blunt is now a consumption method, listed first ahead of Joint. The placeholder Other option is gone."),
            ]),
        ChangelogVersion(
            version: "25.16.0",
            buildLabel: "June 2026",
            headline: "Every strain gets a look.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "photo.stack", tint: Palette.greenBright,
                               title: "Strain photos",
                               detail: "Strains now show a real bud photo until you add your own. Each strain keeps the same photo every time."),
            ]),
        ChangelogVersion(
            version: "25.15.0",
            buildLabel: "June 2026",
            headline: "Goals, prompts, jokes, and quicker seshes.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "target", tint: Palette.greenBright,
                               title: "Goals",
                               detail: "Set goals like smoke less or spend less and track them against your real data."),
                ChangelogEntry(icon: "text.bubble.fill", tint: Palette.purple,
                               title: "Story Time",
                               detail: "Answer randomized community prompts across many categories."),
                ChangelogEntry(icon: "bolt.fill", tint: Palette.gold,
                               title: "Live quick actions",
                               detail: "While seshing, the home tiles become Add Song, Update Mood, and End Session. A collapsible feed and one-tap Smoke Again round it out."),
            ]),
        ChangelogVersion(
            version: "25.14.0",
            buildLabel: "June 2026",
            headline: "One sesh at a time, fully in your control.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "play.circle", tint: Palette.greenBright,
                               title: "Apple Music controls",
                               detail: "Play, pause, and skip right from the active session screen."),
                ChangelogEntry(icon: "record.circle", tint: Palette.gold,
                               title: "Cleaner sessions",
                               detail: "Only one sesh runs at a time, and it is ended only from the active screen."),
                ChangelogEntry(icon: "paintbrush", tint: Palette.purple,
                               title: "Live appearance",
                               detail: "Theme and icon changes apply instantly, no need to leave the screen."),
            ]),
        ChangelogVersion(
            version: "25.13.0",
            buildLabel: "June 2026",
            headline: "Soundtracks for every strain.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "music.note.list", tint: Palette.greenBright,
                               title: "Strain soundtracks",
                               detail: "Each strain has a Listen section with mood playlists for the songs you play with it."),
                ChangelogEntry(icon: "play.circle", tint: Palette.gold,
                               title: "Redesigned playlists",
                               detail: "A bigger, cleaner playlist screen with Play on Spotify and Apple Music."),
            ]),
        ChangelogVersion(
            version: "25.12.0",
            buildLabel: "June 2026",
            headline: "A cleaner sesh, start to finish.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "play.circle", tint: Palette.greenBright,
                               title: "Start a Session",
                               detail: "Pick a strain, method, and mood on one clean screen."),
                ChangelogEntry(icon: "music.note", tint: Palette.purple,
                               title: "Add a Song",
                               detail: "Search, recent, and trending songs while you sesh."),
                ChangelogEntry(icon: "doc.text", tint: Palette.gold,
                               title: "Session Summary",
                               detail: "A polished recap with method, duration, song, mood, and notes."),
            ]),
        ChangelogVersion(
            version: "25.11.0",
            buildLabel: "June 2026",
            headline: "A new shape, and a Listen tab.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "music.note", tint: Palette.greenBright,
                               title: "Listen tab",
                               detail: "Your Vibes and playlists now live in their own tab."),
                ChangelogEntry(icon: "rectangle.3.group", tint: Palette.gold,
                               title: "Refreshed tabs",
                               detail: "Sessions replaces Log, Listen takes the place of Strains, and Strains opens from Home."),
                ChangelogEntry(icon: "link", tint: Palette.purple,
                               title: "Connected Apps and How It Works",
                               detail: "Manage your music connections, and see how The Sesh learns your vibe."),
            ]),
        ChangelogVersion(
            version: "25.10.0",
            buildLabel: "June 2026",
            headline: "Build your sesh soundtrack.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "music.note.list", tint: Palette.greenBright,
                               title: "Playlists",
                               detail: "Build playlists in the app, collect the songs you play automatically, and add tracks by hand."),
                ChangelogEntry(icon: "square.and.arrow.up", tint: Palette.gold,
                               title: "Export anywhere",
                               detail: "Send your playlists to Spotify or Apple Music in a tap."),
            ]),
        ChangelogVersion(
            version: "25.9.0",
            buildLabel: "June 2026",
            headline: "Share your soundtrack.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "waveform", tint: Palette.greenBright,
                               title: "Now Playing",
                               detail: "Share the song you are listening to from Apple Music or Spotify. See what your friends are playing too."),
                ChangelogEntry(icon: "slider.horizontal.3", tint: Palette.gold,
                               title: "You are in control",
                               detail: "Choose your sources and when to share in Settings: always, only during a sesh, or manually."),
            ]),
        ChangelogVersion(
            version: "25.8.0",
            buildLabel: "June 2026",
            headline: "A whole new look.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "paintbrush.fill", tint: Palette.gold,
                               title: "The Apothecary redesign",
                               detail: "A warm, hand-illustrated vintage look is now the default. The home screen has rich new artwork for every action."),
                ChangelogEntry(icon: "leaf.fill", tint: Palette.greenBright,
                               title: "More themes",
                               detail: "Prefer the old style? Olive, Navy, Elevated, and Rasta are all still there in Settings."),
            ]),
        ChangelogVersion(
            version: "25.7.0",
            buildLabel: "June 2026",
            headline: "Navigation that remembers you.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "house.fill", tint: Palette.green,
                               title: "Tabs remember your place",
                               detail: "Switch tabs and come back where you left off. Tap a tab again to jump to the top."),
                ChangelogEntry(icon: "person.text.rectangle", tint: Palette.gold,
                               title: "Your name, done right",
                               detail: "Your status shows your name, and signing in with Apple uses just your first name."),
            ]),
        ChangelogVersion(
            version: "25.6.0",
            buildLabel: "June 2026",
            headline: "Notifications, fully wired.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "bell.badge.fill", tint: Palette.greenBright,
                               title: "Friend notifications now live",
                               detail: "Status changes, invites, and messages from friends now reach you reliably, with sensible limits so nothing spams you."),
                ChangelogEntry(icon: "person.crop.circle.badge.plus", tint: Palette.green,
                               title: "Sesh invites",
                               detail: "Inviting friends when you start a sesh now lets them know."),
            ]),
        ChangelogVersion(
            version: "25.5.0",
            buildLabel: "June 2026",
            headline: "Strains get a face.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "photo.on.rectangle.angled", tint: Palette.green,
                               title: "Strain images",
                               detail: "Strains now show a photo where one's available, with distinct artwork for the rest."),
                ChangelogEntry(icon: "camera.fill", tint: Palette.gold,
                               title: "Add your own",
                               detail: "Tap a strain's image to attach your own photo — it becomes that strain's picture for you."),
                ChangelogEntry(icon: "bell.badge", tint: Palette.greenBright,
                               title: "Notification control",
                               detail: "Turn friend notifications on or off anytime in Settings."),
            ]),
        ChangelogVersion(
            version: "25.0.0",
            buildLabel: "June 2026",
            headline: "A cleaner home, faster everywhere.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "square.grid.2x2.fill", tint: Palette.green,
                               title: "Redesigned Home",
                               detail: "Four big buttons — Roll Up, Smoking, High Thoughts, and End Session — with your live feed right below."),
                ChangelogEntry(icon: "brain", tint: Palette.purple,
                               title: "High Thoughts",
                               detail: "Capture a thought or start a rant in one tap from the Home screen."),
                ChangelogEntry(icon: "bolt.fill", tint: Palette.gold,
                               title: "Faster launches & smoother lists",
                               detail: "Behind-the-scenes work makes the app build and open quicker, with snappier strain search."),
                ChangelogEntry(icon: "info.circle.fill", tint: Palette.greenBright,
                               title: "Fixed About scrolling",
                               detail: "About The Sesh now scrolls cleanly with the header pinned and the last entry fully visible."),
            ]),
        ChangelogVersion(
            version: "24.0.0",
            buildLabel: "June 2026",
            headline: "Smarter sesh controls.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "square.grid.2x2.fill", tint: Palette.green,
                               title: "Start a sesh from your Home Screen",
                               detail: "Tap Roll up to pick a strain, Smoke to jump straight into it, or End to wrap up — right from the widget."),
                ChangelogEntry(icon: "exclamationmark.triangle.fill", tint: Palette.gold,
                               title: "No more lost seshes",
                               detail: "Starting a new sesh while one is running now asks whether to save or discard the one in progress."),
                ChangelogEntry(icon: "flame.fill", tint: Palette.greenBright,
                               title: "Simpler flow",
                               detail: "Sparked Up and Smoking are now a single step."),
            ]),
        ChangelogVersion(
            version: "23.0.0",
            buildLabel: "June 2026",
            headline: "A bolder sesh flow.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "smoke.fill", tint: Palette.greenBright,
                               title: "Pick your vibe to start",
                               detail: "Tap Start sesh and choose what you're doing — Smoking, Hitting the bong, or Rolling up — and we'll track it from there."),
                ChangelogEntry(icon: "rectangle.fill.badge.checkmark", tint: Palette.gold,
                               title: "A clearer live status",
                               detail: "A bold, color-coded Current Status card on Home shows what you're up to, when you started, and a live timer."),
                ChangelogEntry(icon: "party.popper.fill", tint: Palette.gold,
                               title: "Roll celebrations",
                               detail: "Finish a roll and get a celebration with your time — and a callout when you beat your record."),
            ]),
        ChangelogVersion(
            version: "22.0.0",
            buildLabel: "Build 30 · June 2026",
            headline: "Live on your lock screen.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "bolt.horizontal.circle.fill", tint: Palette.greenBright,
                               title: "Live sesh on the Dynamic Island",
                               detail: "Start a sesh and a live timer rides along on your lock screen and Dynamic Island, updating as you move from rolling to sparked up to smoking."),
                ChangelogEntry(icon: "square.grid.2x2.fill", tint: Palette.gold,
                               title: "Home Screen widget",
                               detail: "Add a widget to see your streak, last strain, and stash at a glance — or your live sesh when one's running."),
            ]),
        ChangelogVersion(
            version: "21.0.0",
            buildLabel: "Build 29 · June 2026",
            headline: "Status, photos, and the little things.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "dot.radiowaves.left.and.right", tint: Palette.greenBright,
                               title: "Live status with a timer",
                               detail: "Your Home status now shows what you're up to and how long — \"You're smoking · 12m\" — and updates itself as you log and sesh. Set Available, Busy, or a vibe."),
                ChangelogEntry(icon: "camera.fill", tint: Palette.gold,
                               title: "Photos when you finish a sesh",
                               detail: "The live Start sesh save screen now lets you add a photo."),
                ChangelogEntry(icon: "eye.fill", tint: Palette.green,
                               title: "Thought privacy",
                               detail: "Choose who sees each thought — Private, Close Friends, Friends, or Public."),
                ChangelogEntry(icon: "lightbulb.fill", tint: Palette.gold,
                               title: "Little things",
                               detail: "A daily strain fun fact at the top of Strains, tap your latest sesh on Home to see its details, and a friend-code fix so your code stays the same every time."),
            ]),
        ChangelogVersion(
            version: "20.0.0",
            buildLabel: "Build 28 · June 2026",
            headline: "A smarter way to save strains.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "trophy.fill", tint: Palette.gold,
                               title: "Vault, Tags, Effects — rebuilt",
                               detail: "Logging a sesh now has the full set: a Vault (Favorites/Reliable/Situational/Never Again), multi-select Session Tags, an Effects picker with custom options, and a clearer Definitely/Maybe/No."),
                ChangelogEntry(icon: "crown.fill", tint: Palette.gold,
                               title: "Champions",
                               detail: "When you save a strain to Favorites, tell us why — Best Sleep, Best Creativity, Funniest High, and more. Me → Stats shows your current champion for each."),
            ]),
        ChangelogVersion(
            version: "19.0.0",
            buildLabel: "Build 27 · June 2026",
            headline: "One Log for everything.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "doc.text.fill", tint: Palette.green,
                               title: "Journal + Thoughts = Log",
                               detail: "Your sessions and thoughts now live together in one Log feed, sorted by date. Filter to just thoughts, just sessions, or a vault category. Swipe to delete either one."),
                ChangelogEntry(icon: "rectangle.3.group.fill", tint: Palette.gold,
                               title: "Cleaner tab bar",
                               detail: "Reordered to Home, Log, Cyphs, Strains, Me — and content no longer slips behind the bar."),
                ChangelogEntry(icon: "bubble.left.fill", tint: Palette.greenBright,
                               title: "Rants retired",
                               detail: "The separate Rants feature has been removed to keep the app focused on sessions and thoughts."),
            ]),
        ChangelogVersion(
            version: "18.0.0",
            buildLabel: "Build 26 · June 2026",
            headline: "Resume sessions, custom lists, multi-strain.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "arrow.clockwise.circle.fill", tint: Palette.green,
                               title: "Pick up where you left off",
                               detail: "A live sesh now survives leaving the Cyph tab. Wander off, come back, and tap Resume sesh to keep going — your stage, strain, timer, and roll all carry over."),
                ChangelogEntry(icon: "tag.fill", tint: Palette.gold,
                               title: "Custom categories",
                               detail: "Make your own journal categories — add, rename, and delete them from the Journal tab, assign them when logging, and filter by them. The original four are still there."),
                ChangelogEntry(icon: "leaf.fill", tint: Palette.greenBright,
                               title: "Multiple strains per sesh",
                               detail: "Mixing it up? Add more than one strain to a single sesh when you log it."),
            ]),
        ChangelogVersion(
            version: "17.0.0",
            buildLabel: "Build 25 · June 2026",
            headline: "Cleaner start, smarter rolls.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "timer", tint: Palette.gold,
                               title: "Time your roll",
                               detail: "The live sesh now has a roll timer — hit Start when you begin rolling and Stop when you spark up. Your best blunt and joint times become Personal Records."),
                ChangelogEntry(icon: "list.bullet.below.rectangle", tint: Palette.green,
                               title: "Step-by-step sesh",
                               detail: "The live sesh walks through each step one at a time, with the current step expanded for guidance. Removed the Vibing and Munchies steps."),
                ChangelogEntry(icon: "leaf.fill", tint: Palette.moodAngry,
                               title: "Rastafarian theme",
                               detail: "A new red, gold, and green theme. Find it under Settings → Appearance."),
                ChangelogEntry(icon: "sparkles", tint: Palette.greenBright,
                               title: "A fresh start",
                               detail: "Removed the placeholder demo content so you start with a clean slate, and took price out of the per-sesh log."),
            ]),
        ChangelogVersion(
            version: "16.0.0",
            buildLabel: "Build 24 · June 2026",
            headline: "Secret badges and your smoking style.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "lock.fill", tint: Palette.gold,
                               title: "Secret Badges",
                               detail: "Hidden achievements to discover by accident (Me → Secret Badges). Night Owl, Early Bird, Solo Traveler, Loyalist, and more — you won't know what they are until you earn them."),
                ChangelogEntry(icon: "person.fill.viewfinder", tint: Palette.greenBright,
                               title: "Your Smoking Style",
                               detail: "The Sesh now reads your patterns and generates your personality profile (Me → Smoking Style) — Night Owl, Creative Smoker, Relaxation Seeker, and more, with a strength breakdown."),
            ]),
        ChangelogVersion(
            version: "15.0.0",
            buildLabel: "Build 23 · June 2026",
            headline: "Your sesh Year, wrapped.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "calendar.badge.clock", tint: Palette.greenBright,
                               title: "Yearly Recap",
                               detail: "A shareable \"Your Sesh Year\" card (Me → Yearly Recap) — sessions, favorite strain and effect, most active month, money spent, unique strains, and your thought of the year. Share it as an image."),
            ]),
        ChangelogVersion(
            version: "14.0.0",
            buildLabel: "Build 22 · June 2026",
            headline: "Beat your own bests.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "medal.fill", tint: Palette.gold,
                               title: "Personal Records",
                               detail: "A new Personal Records screen (Me → Personal Records) tracks your bests — longest sesh, highest-rated strain, most-logged strain, most improved opinion, spending records, and more. Built to be beaten."),
            ]),
        ChangelogVersion(
            version: "13.0.0",
            buildLabel: "Build 21 · June 2026",
            headline: "Your Journey begins.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "trophy.fill", tint: Palette.gold,
                               title: "Journey milestones",
                               detail: "A new Journey screen (Me → Journey) tracks permanent milestones — your firsts, strains explored, entries written, thoughts collected, Cyphs, and tracking streaks."),
            ]),
        ChangelogVersion(
            version: "12.0.2",
            buildLabel: "Build 20 · June 2026",
            headline: "Smoother strain browsing.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "arrow.uturn.backward", tint: Palette.green,
                               title: "Better back behavior",
                               detail: "Tapping through similar strains no longer stacks up — Back now takes you straight back to the library instead of retracing every strain you viewed."),
            ]),
        ChangelogVersion(
            version: "12.0.0",
            buildLabel: "Build 19 · June 2026",
            headline: "Tolerance, mood shifts, and deeper strain info.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "gauge.medium", tint: Palette.green,
                               title: "Tolerance & T-breaks",
                               detail: "Track your tolerance based on recent use, and start a tolerance break with a goal and progress tracking. Find it in Stats."),
                ChangelogEntry(icon: "face.smiling", tint: Palette.gold,
                               title: "Mood shift tracking",
                               detail: "Optionally log how you felt before and after a sesh — and see how a strain actually moved your mood. You can also record amount."),
                ChangelogEntry(icon: "arrow.triangle.branch", tint: Palette.greenBright,
                               title: "Genetics tree",
                               detail: "Strain pages now show a visual family tree of parent strains."),
                ChangelogEntry(icon: "leaf.circle.fill", tint: Palette.green,
                               title: "Terpene guide",
                               detail: "Tap any terpene to learn its aroma, effects, and where else it's found."),
                ChangelogEntry(icon: "sparkles", tint: Palette.gold,
                               title: "Friend activity feed",
                               detail: "A new Activity screen (Cyph → Activity) shows what your friends are up to."),
            ]),
        ChangelogVersion(
            version: "11.0.1",
            buildLabel: "Build 18 · June 2026",
            headline: "Back button fix.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "chevron.backward.circle.fill", tint: Palette.green,
                               title: "One back button everywhere",
                               detail: "Fixed a duplicate back button that appeared on strain detail pages and a few other screens."),
            ]),
        ChangelogVersion(
            version: "11.0.0",
            buildLabel: "Build 17 · June 2026",
            headline: "Rebuilt for speed and reliability.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "internaldrive.fill", tint: Palette.green,
                               title: "New database engine",
                               detail: "Your journal now runs on SwiftData — faster, more reliable, and ready to scale. Existing data migrates automatically."),
                ChangelogEntry(icon: "magnifyingglass", tint: Palette.gold,
                               title: "Faster strain search",
                               detail: "Searching the 627-strain library is now instant, and you can search your friends list too."),
                ChangelogEntry(icon: "chart.bar.doc.horizontal.fill", tint: Palette.greenBright,
                               title: "Richer strain details",
                               detail: "Strain pages now show THC/CBD potency bars and similar strains to discover."),
                ChangelogEntry(icon: "wifi", tint: Palette.gold,
                               title: "Connection status",
                               detail: "Clear offline indicators with tap-to-retry, pull-to-refresh, and a smoother first-run that lands you where you want to be."),
            ]),
        ChangelogVersion(
            version: "10.0.0",
            buildLabel: "Build 16 · June 2026",
            headline: "An achievement for every milestone.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "rosette", tint: Palette.gold,
                               title: "39 badges, 8 categories",
                               detail: "A big badge expansion — Explorer, Strains, Journal, Session, Social, Spending, Dedication, and more. Each category has its own icon and color, with progress counts."),
                ChangelogEntry(icon: "wand.and.stars", tint: Palette.green,
                               title: "Richer effect icons",
                               detail: "Every effect now has its own icon and color throughout the app."),
            ]),
        ChangelogVersion(
            version: "9.0.0",
            buildLabel: "Build 15 · June 2026",
            headline: "Bigger, richer strain library.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "books.vertical.fill", tint: Palette.green,
                               title: "37 new strains",
                               detail: "The library grew from 590 to 627 strains, with classics like Sour Diesel, White Russian, Tahoe OG, and Super Lemon Haze."),
                ChangelogEntry(icon: "arrow.triangle.branch", tint: Palette.gold,
                               title: "Genetics & origins",
                               detail: "Strain detail pages now show lineage, breeder, and flowering time where we have it — sourced from SeedFinder."),
            ]),
        ChangelogVersion(
            version: "8.0.0",
            buildLabel: "Build 14 · June 2026",
            headline: "Safer, smarter, more reliable.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "hand.raised.fill", tint: Palette.green,
                               title: "Block & report",
                               detail: "Block anyone to hide their activity, cyphers, and messages, or report them for moderation — right from their profile."),
                ChangelogEntry(icon: "clock.arrow.circlepath", tint: Palette.gold,
                               title: "Full chat history",
                               detail: "Chat rooms now keep more history and let you load earlier messages."),
                ChangelogEntry(icon: "arrow.triangle.merge", tint: Palette.greenBright,
                               title: "Smarter iCloud sync",
                               detail: "Edits made on two devices now merge instead of overwriting, plus new spam protection."),
            ]),
        ChangelogVersion(
            version: "7.1.0",
            buildLabel: "Build 13 · June 2026",
            headline: "Compare any strain.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "rectangle.split.3x1.fill", tint: Palette.green,
                               title: "Compare anything",
                               detail: "Compare any strains in the catalog — even ones you've never tried. See type, THC, and effects side by side, plus your own history when you have it."),
            ]),
        ChangelogVersion(
            version: "7.0.0",
            buildLabel: "Build 12 · June 2026",
            headline: "Friends, trends, and a whole lot more.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "person.2.fill", tint: Palette.green,
                               title: "Friends by code",
                               detail: "Share your friend code and add others by theirs. See who's around in the new Friends screen (Cyph → Friends)."),
                ChangelogEntry(icon: "chart.line.uptrend.xyaxis", tint: Palette.gold,
                               title: "Trends",
                               detail: "A new Trends tab in Stats shows your rating over time and sessions per week."),
                ChangelogEntry(icon: "sparkles", tint: Palette.green,
                               title: "For You strains & more",
                               detail: "Personalized strain picks, a welcome tour, better journal filters, more badges, and polish throughout."),
            ]),
        ChangelogVersion(
            version: "6.0.2",
            buildLabel: "Build 11 · June 2026",
            headline: "iCloud sync fixed.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "icloud.fill", tint: Palette.gold,
                               title: "iCloud now works",
                               detail: "Fixed the missing iCloud entitlement that prevented syncing. Your data backs up and restores across devices again — and the app falls back to on-device storage gracefully if iCloud isn't available."),
            ]),
        ChangelogVersion(
            version: "6.0.1",
            buildLabel: "Build 10 · June 2026",
            headline: "Navy theme polish.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "textformat", tint: Palette.gold,
                               title: "Readable wordmark",
                               detail: "\"The Sesh\" on Home is now clearly visible in every theme, including Navy."),
                ChangelogEntry(icon: "chevron.backward.circle.fill", tint: Palette.green,
                               title: "One back button",
                               detail: "Fixed a duplicate back button that appeared on Edit Profile and other pushed screens."),
            ]),
        ChangelogVersion(
            version: "6.0.0",
            buildLabel: "Build 9 · June 2026",
            headline: "Snap a photo of your strain.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "camera.fill", tint: Palette.green,
                               title: "Strain photos",
                               detail: "Add a photo to any custom strain — take one with your camera or pick from your library. It shows on the strain card and detail."),
                ChangelogEntry(icon: "photo.on.rectangle.angled", tint: Palette.gold,
                               title: "Camera everywhere it fits",
                               detail: "Snap pics in your sesh log, rants, and now strains. Your photos stay on your device."),
            ]),
        ChangelogVersion(
            version: "5.2.0",
            buildLabel: "Build 8 · June 2026",
            headline: "Live Chat replaces live video.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "bubble.left.and.bubble.right.fill", tint: Palette.green,
                               title: "Live Chat room",
                               detail: "The Cyph tab now has a single always-on Live Chat room — hop in and talk in real time with everyone who's around."),
                ChangelogEntry(icon: "checkmark.circle.fill", tint: Palette.gold,
                               title: "Simpler & focused",
                               detail: "Live video streaming has been removed. Cyphers are shared chat sessions, and Live Chat is text in real time — no camera or mic needed."),
            ]),
        ChangelogVersion(
            version: "5.1.1",
            buildLabel: "Build 7 · June 2026",
            headline: "Layout fixes for every screen size.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "iphone.gen3", tint: Palette.green,
                               title: "Fits your screen",
                               detail: "The tab bar and floating buttons now respect every device's safe area, so nothing is clipped behind the home indicator."),
            ]),
        ChangelogVersion(
            version: "5.1.0",
            buildLabel: "Build 6 · June 2026",
            headline: "Cypher & live chat now sync for everyone.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "bubble.left.and.bubble.right.fill", tint: Palette.green,
                               title: "Cypher chat is shared",
                               detail: "Messages in a Cypher now send to everyone in the session and refresh live — no more chat that only you could see."),
                ChangelogEntry(icon: "video.bubble.left.fill", tint: Palette.gold,
                               title: "Live chat synced",
                               detail: "Chat while watching a live session is now shared across all viewers in real time."),
            ]),
        ChangelogVersion(
            version: "5.0.0",
            buildLabel: "Build 5 · June 2026",
            headline: "Go live — the social layer is real.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "dot.radiowaves.left.and.right", tint: Palette.green,
                               title: "Live presence & broadcasting",
                               detail: "When you start a sesh, host a Cypher, or go live, friends see it in real time — and you see theirs. Presence updates on a short refresh."),
                ChangelogEntry(icon: "person.2.fill", tint: Palette.gold,
                               title: "It's really you now",
                               detail: "Everything you broadcast is tied to your signed-in identity, so cyphers, live, and chat show your name and handle."),
                ChangelogEntry(icon: "bubble.left.and.bubble.right.fill", tint: Palette.greenBright,
                               title: "Live chat rooms",
                               detail: "Messages in community rooms now send and refresh against the server, so conversations stay in sync."),
            ]),
        ChangelogVersion(
            version: "4.0.0",
            buildLabel: "Build 4 · June 2026",
            headline: "Sign in & sync across your devices.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "apple.logo", tint: Palette.text,
                               title: "Sign in with Apple",
                               detail: "Sign in securely with your Apple ID. Your name carries over and your account follows you across devices."),
                ChangelogEntry(icon: "icloud.fill", tint: Palette.gold,
                               title: "iCloud sync",
                               detail: "Your sessions, thoughts, rants, profile, and theme back up to iCloud and restore automatically on a new device. Toggle it in Me → Edit Profile → iCloud."),
                ChangelogEntry(icon: "sparkles", tint: Palette.greenBright,
                               title: "Changelog in About",
                               detail: "About The Sesh now shows the full version history."),
            ]),
        ChangelogVersion(
            version: "3.0.0",
            buildLabel: "Build 3 · June 2026",
            headline: "A new vibe — the Elevated theme.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "leaf.fill", tint: Palette.greenBright,
                               title: "Elevated theme",
                               detail: "A warm, calming cream palette with sage greens, lavender, gold, and terracotta. \"Calming. Personal. Elevated.\" Pick it in Me → Edit Profile → Appearance."),
                ChangelogEntry(icon: "paintpalette.fill", tint: Palette.gold,
                               title: "Three themes to choose from",
                               detail: "Olive, Navy, and now Elevated — each re-tints the whole app, with light or dark styling to match."),
            ]),
        ChangelogVersion(
            version: "2.0.0",
            buildLabel: "Build 2 · June 2026",
            headline: "Pick your vibe — now with themes.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "paintpalette.fill", tint: Palette.gold,
                               title: "Themes — Olive & Navy",
                               detail: "Switch the whole app between the classic Olive look and a deep Navy theme in Me → Edit Profile → Appearance."),
                ChangelogEntry(icon: "star.fill", tint: Palette.gold,
                               title: "Featured & Popular strains",
                               detail: "The Strains tab now leads with a Featured Strain and a Popular This Week ranking."),
                ChangelogEntry(icon: "leaf.fill", tint: Palette.greenBright,
                               title: "Refined navigation",
                               detail: "Cleaner tab bar labels and icons across Home, Journal, Strains, Cyph, and Me."),
            ]),
        ChangelogVersion(
            version: "1.5.0",
            buildLabel: "Build 1 · June 2026",
            headline: "The Sesh is here — your cannabis companion.",
            isLatest: false,
            entries: [
                ChangelogEntry(icon: "play.circle.fill", tint: Palette.green,
                               title: "Start sesh — live sessions",
                               detail: "Run a session in real time through the stages (Rolling Up → Sparked Up → Smoking → Vibing → Munchies → Finished). Finishing saves it straight to your Journal."),
                ChangelogEntry(icon: "dot.radiowaves.left.and.right", tint: Palette.gold,
                               title: "Cyphers",
                               detail: "Host or join shared sessions. Set a strain, visibility, and go live so friends can pull up."),
                ChangelogEntry(icon: "person.2.fill", tint: Palette.greenBright,
                               title: "Friends & live presence",
                               detail: "See what friends are up to in the moment — rolling up, hitting the bong, vibing — on Home and in the activity feed."),
                ChangelogEntry(icon: "video.fill", tint: Palette.moodAngry,
                               title: "Live & chat rooms",
                               detail: "Go live with viewer chat, and drop into community chat rooms — General, Strain Talk, Growers, and the sesh Lounge."),
                ChangelogEntry(icon: "rectangle.split.3x1.fill", tint: Palette.gold,
                               title: "Strain intelligence",
                               detail: "Compare strains across your own history, Find My Vibe by desired effects, and What Should I Buy from a dealer's list — plus a Wishlist."),
                ChangelogEntry(icon: "globe.americas.fill", tint: Palette.green,
                               title: "The Lounge",
                               detail: "A public community space: trending strains, discussions, polls, strain rooms, and community reviews."),
                ChangelogEntry(icon: "books.vertical.fill", tint: Palette.greenBright,
                               title: "590-strain library",
                               detail: "Search, filter, and log from a built-in catalog of ~590 strains, with your personal experience tracked per strain."),
            ]),
    ]

    static var latest: ChangelogVersion { versions.first { $0.isLatest } ?? versions[0] }

    /// "What's New" should auto-present once per shipped version.
    private static let seenKey = "sesh.changelog.seenVersion"
    static var shouldShowWhatsNew: Bool {
        UserDefaults.standard.string(forKey: seenKey) != latest.version
    }
    static func markWhatsNewSeen() {
        UserDefaults.standard.set(latest.version, forKey: seenKey)
    }
}

// MARK: - What's New sheet

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var version: ChangelogVersion = AppChangelog.latest

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("What's New").font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(Palette.text)
                    Text(version.headline).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(BuildConfig.displayLabel).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22).padding(.horizontal, 24).padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(version.entries) { entry in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(entry.tint)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(entry.tint.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text(entry.detail).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                }

                PrimaryButton(title: "Let's go", icon: "checkmark") {
                    AppChangelog.markWhatsNewSeen(); Haptics.success(); dismiss()
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
    }
}

// MARK: - Full changelog history (from Settings → About)

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Changelog", onBack: { dismiss() })
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(AppChangelog.versions) { version in
                            DarkCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Text("v\(version.version)").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                                        if version.isLatest {
                                            Text("LATEST").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onGreen)
                                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Palette.green))
                                        }
                                        Spacer()
                                        Text(version.buildLabel).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                    }
                                    ForEach(version.entries) { entry in
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: entry.icon).font(.system(size: 14)).foregroundStyle(entry.tint)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                                                Text(entry.detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
