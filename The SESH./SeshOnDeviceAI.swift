//
//  SeshOnDeviceAI.swift
//  The SESH.
//
//  On-device intelligence via Apple's Foundation Models framework
//  (Apple Intelligence, iOS 26+, eligible hardware).
//
//  ─────────────────────────────────────────────────────────────────────────
//  Why The SESH. is the app where on-device isn't just nicer — it's the only
//  acceptable design
//  ─────────────────────────────────────────────────────────────────────────
//  The SESH. has no AI today, and it is the only one of the four apps where
//  adding cloud AI would make the product *worse*.
//
//  Look at what the app holds that never leaves the device:
//
//    • High Thoughts        (HighThought.text, ComposeThoughtView)
//    • Session notes        (JournalEntry.notes — "How was it?")
//    • Goals and reflection (GoalsAndExtras: "Why does this matter to you?")
//    • Custom strain notes  (StrainProfile.summary)
//
//  That is a private journal about someone's cannabis use. There is no route to
//  the Worker for any of it, by design. Bolting a cloud LLM onto these features
//  would mean newly exfiltrating the most sensitive data in the app to a third
//  party — to auto-title a journal entry. Foundation Models is the only way to
//  make these features intelligent without breaking the promise the current
//  architecture quietly makes.
//
//  And the second-most sensitive stream — chat and Cypher messages — is a
//  similar story. Messages already go to the Worker because they have to (they
//  go to other people), but *composing* assistance doesn't need to: a tone check
//  before you send something at 1am is exactly the kind of help that should
//  never itself become a network request.
//
//  ─────────────────────────────────────────────────────────────────────────
//  What is here
//  ─────────────────────────────────────────────────────────────────────────
//    1. Journal intelligence — auto-title and tag a High Thought or session note
//    2. Recap narrative      — replace the hand-templated headline strings in
//                              RecapCardsView / JourneyRecordsViews with real
//                              sentences, from local aggregates
//    3. Local search filter  — turn "long sessions last winter that went well"
//                              into a structured filter over local data
//    4. Pre-send check       — optional, opt-in tone/clarity check before a
//                              message or lounge comment is posted
//
//  What stays server-side, unchanged: lounge feed ranking and moderation state
//  (needs global state and must not be client-trustable), /api/snapshot,
//  presence, cyphers, rooms, Spotify (the Worker holds the refresh token), APNs
//  copy (the server owns the recipient graph), auth and DeviceCheck.
//
//  Note on (4): a local check is a *courtesy to the sender*, never a
//  substitute for server-side moderation. Anything that decides what other
//  people see has to stay where it can't be bypassed by a patched client.
//
//  Self-contained: Foundation + FoundationModels only. See "Wiring".
//
//  NOT COMPILED HERE — see the Verification note.
//

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public value types

struct OnDeviceThoughtSummary: Sendable {
    /// Six words or fewer, in the writer's own register.
    let title: String
    /// Suggested tags, lowercase. Map onto the app's `ThoughtTag` cases;
    /// anything unrecognised is dropped by the adapter.
    let tags: [String]
    /// One-line gist, for collapsed rows in the journal list.
    let gist: String
}

struct OnDeviceRecap: Sendable {
    let headline: String
    let body: String
    /// Optional gentle observation. Never advice, never a health claim.
    let note: String?
}

struct OnDeviceJournalQuery: Sendable, Equatable {
    var textContains: String?
    /// "morning" | "afternoon" | "evening" | "night"
    var timeOfDay: String?
    var minDurationMinutes: Int?
    var maxDurationMinutes: Int?
    var strain: String?
    /// "positive" | "negative" | "mixed"
    var mood: String?
    var withinLastDays: Int?

    static let empty = OnDeviceJournalQuery(
        textContains: nil, timeOfDay: nil, minDurationMinutes: nil,
        maxDurationMinutes: nil, strain: nil, mood: nil, withinLastDays: nil
    )
}

struct OnDeviceSendCheck: Sendable {
    /// True when nothing stood out. The overwhelming majority of messages.
    let looksFine: Bool
    /// Present only when something did. One short, non-judgemental sentence.
    let note: String?
    /// An optional softer rewrite the user can take or ignore. Never applied
    /// automatically.
    let suggestion: String?
}

enum SeshOnDeviceError: LocalizedError {
    case unavailable(String)
    case emptyInput
    case guardrail
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .emptyInput: return "Nothing to read yet."
        case .guardrail: return "Apple Intelligence declined that."
        case .failed(let message): return message
        }
    }
}

// MARK: - Entry point

enum SeshOnDeviceAI {

    private static let log = Logger(subsystem: "com.sowens.The-SESH-", category: "OnDeviceAI")

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This iPhone doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
        #else
        return "This build wasn't compiled with Apple Intelligence support."
        #endif
    }

    // MARK: 1. Journal intelligence

    /// Title, tag and summarise a High Thought or session note — on this iPhone,
    /// and nowhere else. This text has never had a network path and must not
    /// gain one.
    static func summariseThought(_ text: String, knownTags: [String]) async throws -> OnDeviceThoughtSummary {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 8 else { throw SeshOnDeviceError.emptyInput }
        try requireAvailable()

        #if canImport(FoundationModels)
        return try await FoundationModelsSesh.summariseThought(clean, knownTags: knownTags)
        #else
        throw SeshOnDeviceError.unavailable("Apple Intelligence isn't available in this build.")
        #endif
    }

    // MARK: 2. Recap narrative

    /// Turn local aggregates into a sentence a person would actually write.
    ///
    /// - Parameter facts: pre-computed lines like "12 sessions this month",
    ///   "most common strain: Blue Dream", "average 42 minutes". Compute these
    ///   in Swift — the model narrates, it does not do arithmetic, because a
    ///   small model doing arithmetic on a user's own data is a bug generator.
    static func recap(facts: [String], period: String) async throws -> OnDeviceRecap {
        guard !facts.isEmpty else { throw SeshOnDeviceError.emptyInput }
        try requireAvailable()

        #if canImport(FoundationModels)
        return try await FoundationModelsSesh.recap(facts: facts, period: period)
        #else
        throw SeshOnDeviceError.unavailable("Apple Intelligence isn't available in this build.")
        #endif
    }

    // MARK: 3. Search

    /// Natural language → a structured filter the existing journal/strain
    /// queries can apply. The corpus is entirely local, so a round trip would be
    /// pure overhead; the model only has to emit a filter.
    static func parseJournalQuery(_ phrase: String) async -> OnDeviceJournalQuery? {
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, isAvailable else { return nil }

        #if canImport(FoundationModels)
        do {
            return try await FoundationModelsSesh.parseQuery(clean)
        } catch {
            log.debug("on-device query parse failed: \(error.localizedDescription, privacy: .public)")
            return nil      // caller falls back to plain substring search
        }
        #else
        return nil
        #endif
    }

    // MARK: 4. Pre-send check

    /// An optional, opt-in second look before a message goes out.
    ///
    /// Design rules, deliberately conservative:
    ///   • Never blocks sending. It returns a note; the user decides.
    ///   • Silent by default — `looksFine` for anything ordinary. A composer
    ///     that comments on every message is a composer people turn off.
    ///   • Never replaces server-side moderation, which is the only check that
    ///     cannot be bypassed by a modified client.
    static func checkBeforeSending(_ text: String) async -> OnDeviceSendCheck {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 12, isAvailable else {
            return OnDeviceSendCheck(looksFine: true, note: nil, suggestion: nil)
        }

        #if canImport(FoundationModels)
        do {
            return try await FoundationModelsSesh.preSend(clean)
        } catch {
            // Failing open is correct here: a broken check must never stop
            // someone from sending a message.
            log.debug("on-device pre-send check failed: \(error.localizedDescription, privacy: .public)")
            return OnDeviceSendCheck(looksFine: true, note: nil, suggestion: nil)
        }
        #else
        return OnDeviceSendCheck(looksFine: true, note: nil, suggestion: nil)
        #endif
    }

    private static func requireAvailable() throws {
        guard isAvailable else {
            throw SeshOnDeviceError.unavailable(unavailableReason ?? "Apple Intelligence is unavailable.")
        }
    }
}

// MARK: - Foundation Models

#if canImport(FoundationModels)

private enum FoundationModelsSesh {

    // MARK: Thought

    @Generable
    struct Thought {
        @Guide(description: "A title of six words or fewer, in the same voice the writer used.")
        var title: String
        @Guide(description: "Up to three lowercase tags. Prefer tags from the KNOWN TAGS list when one fits.")
        var tags: [String]
        @Guide(description: "One sentence saying what this entry is about.")
        var gist: String
    }

    static func summariseThought(_ text: String, knownTags: [String]) async throws -> OnDeviceThoughtSummary {
        let session = LanguageModelSession(instructions: """
        You help someone organise their own private journal.

        This is their writing, kept on their phone. Your job is to label it, not \
        to interpret them.

        Rules:
        - Match their voice and register. Do not make a scrappy note sound formal.
        - Never comment on their choices, habits or wellbeing.
        - Never give advice, and never make a health claim.
        - Use only what they wrote. Do not infer a mood they did not express.
        """)

        var prompt = "ENTRY:\n\(text)"
        if !knownTags.isEmpty { prompt += "\n\nKNOWN TAGS:\n" + knownTags.joined(separator: ", ") }

        do {
            let response = try await session.respond(to: prompt, generating: Thought.self)
            let content = response.content
            return OnDeviceThoughtSummary(
                title: content.title.trimmingCharacters(in: .whitespaces),
                tags: content.tags
                    .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
                gist: content.gist.trimmingCharacters(in: .whitespaces)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error)
        } catch {
            throw SeshOnDeviceError.failed(error.localizedDescription)
        }
    }

    // MARK: Recap

    @Generable
    struct Recap {
        @Guide(description: "One short sentence that captures the period. No exclamation marks.")
        var headline: String
        @Guide(description: "Two or three sentences expanding on it, using only the facts given.")
        var body: String
        @Guide(description: "One optional neutral observation, or an empty string. Never advice.")
        var note: String
    }

    static func recap(facts: [String], period: String) async throws -> OnDeviceRecap {
        let session = LanguageModelSession(instructions: """
        You write a short, plain recap of someone's own logged activity.

        Rules:
        - Use ONLY the facts given. Never calculate, estimate or extrapolate.
        - Neutral and factual. No congratulating, no concern, no encouragement.
        - Never give health, medical or lifestyle advice, and never imply a \
        pattern is good or bad.
        - No hype, no emoji, no exclamation marks.
        """)

        let prompt = "PERIOD: \(period)\n\nFACTS:\n" + facts.map { "- \($0)" }.joined(separator: "\n")

        do {
            let response = try await session.respond(to: prompt, generating: Recap.self)
            let content = response.content
            let note = content.note.trimmingCharacters(in: .whitespaces)
            return OnDeviceRecap(
                headline: content.headline.trimmingCharacters(in: .whitespaces),
                body: content.body.trimmingCharacters(in: .whitespaces),
                note: note.isEmpty ? nil : note
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error)
        } catch {
            throw SeshOnDeviceError.failed(error.localizedDescription)
        }
    }

    // MARK: Query

    @Generable
    struct Query {
        @Guide(description: "Words to look for in the entry text. Empty string if the phrase is only about filters.")
        var textContains: String
        @Guide(description: "One of: morning, afternoon, evening, night. Empty string if not mentioned.")
        var timeOfDay: String
        @Guide(description: "Shortest session length in minutes. 0 if not mentioned.", .range(0...1440))
        var minDurationMinutes: Int
        @Guide(description: "Longest session length in minutes. 0 if not mentioned.", .range(0...1440))
        var maxDurationMinutes: Int
        @Guide(description: "A strain name if one is mentioned, otherwise an empty string.")
        var strain: String
        @Guide(description: "One of: positive, negative, mixed. Empty string if not mentioned.")
        var mood: String
        @Guide(description: "How many days back to look. 0 if the phrase has no time range.", .range(0...3650))
        var withinLastDays: Int
    }

    static func parseQuery(_ phrase: String) async throws -> OnDeviceJournalQuery {
        let session = LanguageModelSession(instructions: """
        You turn a search phrase into filter settings for someone's own journal.

        Only fill in a field the phrase actually asks for. An invented filter \
        hides entries they wanted to find, so leaving a field empty is always \
        the safer answer.

        "last winter" is a time range. "long" sessions means a minimum duration, \
        not a maximum. "went well" is a positive mood.
        """)

        let response = try await session.respond(to: phrase, generating: Query.self)
        let content = response.content

        let times = ["morning", "afternoon", "evening", "night"]
        let moods = ["positive", "negative", "mixed"]
        let time = content.timeOfDay.lowercased().trimmingCharacters(in: .whitespaces)
        let mood = content.mood.lowercased().trimmingCharacters(in: .whitespaces)
        let text = content.textContains.trimmingCharacters(in: .whitespaces)
        let strain = content.strain.trimmingCharacters(in: .whitespaces)

        return OnDeviceJournalQuery(
            textContains: text.isEmpty ? nil : text,
            timeOfDay: times.contains(time) ? time : nil,
            minDurationMinutes: content.minDurationMinutes > 0 ? content.minDurationMinutes : nil,
            maxDurationMinutes: content.maxDurationMinutes > 0 ? content.maxDurationMinutes : nil,
            strain: strain.isEmpty ? nil : strain,
            mood: moods.contains(mood) ? mood : nil,
            withinLastDays: content.withinLastDays > 0 ? content.withinLastDays : nil
        )
    }

    // MARK: Pre-send

    @Generable
    struct SendCheck {
        @Guide(description: "True unless there is a specific, concrete reason the sender might regret this message.")
        var looksFine: Bool
        @Guide(description: "If looksFine is false, one short non-judgemental sentence saying what stood out. Otherwise an empty string.")
        var note: String
        @Guide(description: "If looksFine is false, an optional gentler version of the same message. Otherwise an empty string.")
        var suggestion: String
    }

    static func preSend(_ text: String) async throws -> OnDeviceSendCheck {
        let session = LanguageModelSession(instructions: """
        You take one last look at a message before a friend sends it to friends.

        Say it looks fine unless there is a specific, concrete reason they might \
        regret it: it reads much harsher than it probably means to, it shares \
        someone else's private information, or it contains a phone number, \
        address or account detail.

        Do NOT flag: swearing between friends, slang, drug talk, arguing, \
        typos, bluntness, or anything about how they choose to live. This is \
        their conversation.

        Default to fine. Being quiet is almost always right.
        """)

        do {
            let response = try await session.respond(to: "MESSAGE:\n\(text)", generating: SendCheck.self)
            let content = response.content
            let note = content.note.trimmingCharacters(in: .whitespaces)
            let suggestion = content.suggestion.trimmingCharacters(in: .whitespaces)
            // Fail closed toward silence: "not fine" with nothing useful to say
            // is just noise.
            if content.looksFine || note.isEmpty {
                return OnDeviceSendCheck(looksFine: true, note: nil, suggestion: nil)
            }
            return OnDeviceSendCheck(looksFine: false, note: note, suggestion: suggestion.isEmpty ? nil : suggestion)
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error)
        } catch {
            throw SeshOnDeviceError.failed(error.localizedDescription)
        }
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> SeshOnDeviceError {
        switch error {
        case .guardrailViolation: return .guardrail
        case .assetsUnavailable: return .unavailable("Apple Intelligence is still getting ready.")
        default: return .failed(error.localizedDescription)
        }
    }
}

#endif

// MARK: - Wiring
//
// 1. ComposeThoughtView (Journal/ThoughtsView.swift) — on save, if the entry has
//    no title, offer one:
//
//        if SeshOnDeviceAI.isAvailable, thought.title.isEmpty,
//           let s = try? await SeshOnDeviceAI.summariseThought(thought.text, knownTags: ThoughtTag.allCases.map(\.rawValue)) {
//            suggestedTitle = s.title
//            suggestedTags  = s.tags.compactMap(ThoughtTag.init(rawValue:))
//        }
//
//    Suggest, never apply. This is the user's journal.
//
// 2. RecapCardsView / JourneyRecordsViews.swift:749 — `headline` is a two-string
//    join today. Compute the aggregates in Swift as now, pass them as `facts`,
//    and use the narrated version when it comes back. Keep the templated string
//    as the fallback for non-eligible devices — which is most of them.
//
// 3. JournalView.swift:247 and StrainLibraryView.swift:82 — run
//    `parseJournalQuery` alongside the existing substring search and merge, so a
//    phrase that the model can't parse still behaves exactly as it does today.
//
// 4. ChatViews.swift:137 / CypherViews.swift / LoungePostDetailView.swift:267 —
//    `checkBeforeSending` is OFF by default and lives behind a Settings toggle
//    ("Look over my messages before I send them"). When on, it runs after the
//    user taps send and before `SocialStore.send`, and shows a one-tap
//    "Send anyway". It must never delay or block the OfflineOutbox path.
//
// 5. Settings — one line explaining that all of this runs on the iPhone and
//    nothing is sent anywhere. For this app in particular, that sentence is the
//    feature.
//
// Do NOT move lounge ranking, moderation decisions, presence, Spotify or APNs
// copy on-device. Reasons at the top of this file.
//
// MARK: - Verification
//
// Brace/paren balance checked programmatically. Written against Apple's
// published Foundation Models API.
//
// NOT COMPILED and NOT run on hardware. Real tests:
//   1. Clean Xcode build (the app is `SWIFT_STRICT_CONCURRENCY = complete`, so
//      watch for actor-isolation warnings at the call sites, not in this file).
//   2. On an Apple Intelligence-capable iPhone: write a High Thought and confirm
//      a sensible title in under a second with the network off.
//   3. Pre-send check: feed it twenty ordinary messages between friends and
//      confirm it stays silent for all twenty. If it comments on more than one,
//      the instructions need tightening before this ships — a chatty version of
//      this feature is worse than no version.
