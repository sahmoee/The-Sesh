//
//  StartSeshView.swift
//  The SESH
//
//  The live, in-the-moment session experience. Pick who's joining and the
//  vibe, then move through the stages (Picking Strain → Rolling Up → Sparked Up
//  → Smoking → Vibing → Munchies → Finished). Each stage broadcasts to friends.
//  Finishing opens a Save sheet that writes a completed entry to the Journal —
//  an abandoned sesh is never auto-saved.
//

import SwiftUI

/// Formats an elapsed interval as m:ss (or h:mm:ss past an hour) for the live timer.
func seshDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}


/// Formats an elapsed interval as m:ss (or h:mm:ss past an hour) for the live timer.
struct StartSeshView: View {
    /// When set (from the "What are you doing?" chooser or a widget), the sesh
    /// starts live immediately in this activity instead of showing setup.
    var initialActivity: StartActivity? = nil
    /// When true (from the widget's Cigar/end button), end the live sesh on
    /// appear and go straight to the save screen.
    var endImmediately: Bool = false
    @Environment(SocialStore.self) private var social
    @Environment(StrainStore.self) private var strains
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    enum Phase { case setup, live, save }
    @State private var phase: Phase = .setup

    // Setup
    @State private var whoJoining = "Just Me"
    @State private var sessionType: SessionType = .relaxing
    @State private var privacy: CypherVisibility = .friends
    @State private var invited: Set<String> = []

    // Live
    @State private var stage: SeshStage = .pickingStrain
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var strainName = ""
    @State private var attachedThought = ""        // current draft input
    @State private var capturedThoughts: [String] = []  // thoughts added this sesh (#multi-thought)
    @State private var showThoughtField = false
    @FocusState private var thoughtFieldFocused: Bool
    // Roll timer (ties to Personal Records — Fastest Blunt/Joint Rolled)
    @State private var rollStartedAt: Date? = nil
    @State private var rollElapsed: TimeInterval = 0
    @State private var rollFinalSeconds: Int? = nil
    @State private var showRollComplete = false
    @State private var rollWasRecord = false
    @State private var rollMethod = "Joint"   // Joint or Blunt — which record to set

    var body: some View {
        ZStack {
            AppBackground()
            switch phase {
            case .setup: setupView
            case .live:  liveView
            case .save:  saveView
            }
        }
        .onAppear(perform: restoreIfNeeded)
        .fullScreenCover(isPresented: $showRollComplete) { rollCompleteCover }
    }

    /// The save screen, extracted so its multi-argument initializer type-checks
    /// on its own instead of inside the switch (keeps `body` fast to type-check).
    private var saveView: some View {
        SaveSeshView(
            strainName: strainName,
            sessionType: sessionType,
            durationMinutes: max(1, Int(elapsed / 60)),
            companions: Array(invited),
            attachedThought: attachedThought,
            capturedThoughts: capturedThoughts,
            onDone: { finishSave() })
    }

    /// The roll-complete cover, extracted from the fullScreenCover closure for
    /// the same type-check reason.
    private var rollCompleteCover: some View {
        RollCompleteView(
            seconds: rollFinalSeconds ?? 0,
            isRecord: rollWasRecord,
            onStartSmoking: {
                showRollComplete = false
                stage = .smoking
                social.setMyActivity(.smoking)
                persistLive()
            },
            onLogSession: {
                showRollComplete = false
                phase = .save
            })
        .environment(session).environment(strains).environment(social)
    }

    private func finishSave() {
        session.clearLiveSesh()
        LiveSeshActivityController.end()
        SeshWidgetBridge.update(streak: session.currentStreak,
                                lastStrain: session.entries.first?.strain ?? "—",
                                stashCount: session.stashRemaining.count,
                                isLive: false, liveStrain: "")
        dismiss()
    }

    /// If a sesh was left running, drop straight back into it.
    private func restoreIfNeeded() {
        // Widget "end" action: end the live sesh (stop timer + Live Activity),
        // then jump to the skippable save screen.
        if phase == .setup, endImmediately {
            if let s = session.liveSesh {
                startedAt = s.startedAt; stage = s.stage; sessionType = s.sessionType
                strainName = s.strainName; attachedThought = s.attachedThought
                rollFinalSeconds = s.rollFinalSeconds; rollMethod = s.rollMethod
                invited = Set(s.invited); elapsed = s.elapsed
            }
            // Actually END it: clear the resumable live state, stop the Live
            // Activity, and drop the broadcast status so Home no longer shows it.
            session.clearLiveSesh()
            LiveSeshActivityController.end()
            social.setMyActivity(.idle)
            phase = .save
            return
        }
        // If launched from the chooser/widget with an activity, start live now in
        // the chosen activity (skip setup). initialActivity wins over a stale
        // live sesh because RootView already cleared liveSesh for fresh starts.
        if phase == .setup, let a = initialActivity {
            startedAt = Date(); elapsed = 0
            stage = a.stage
            phase = .live
            social.setMyActivity(a.activity)
            LiveSeshActivityController.start(strain: strainName, stageRaw: stage.rawValue, startedAt: startedAt)
            persistLive()
            return
        }
        guard phase == .setup, let s = session.liveSesh else { return }
        startedAt = s.startedAt
        stage = s.stage
        sessionType = s.sessionType
        strainName = s.strainName
        attachedThought = s.attachedThought
        rollFinalSeconds = s.rollFinalSeconds
        rollMethod = s.rollMethod
        invited = Set(s.invited)
        elapsed = s.elapsed
        phase = .live
        // Resume the Live Activity for the restored sesh.
        LiveSeshActivityController.start(strain: strainName, stageRaw: stage.rawValue, startedAt: startedAt)
    }

    /// Snapshot the current live state so leaving the tab doesn't lose the sesh.
    private func persistLive() {
        guard phase == .live else { return }
        session.saveLiveSesh(LiveSeshState(
            startedAt: startedAt,
            stageRaw: stage.rawValue,
            sessionTypeRaw: sessionType.rawValue,
            strainName: strainName,
            attachedThought: attachedThought,
            rollFinalSeconds: rollFinalSeconds,
            rollMethod: rollMethod,
            invited: Array(invited)))
        // Keep the Live Activity (Dynamic Island / lock screen) in sync.
        // Keep the Live Activity (Dynamic Island / lock screen) in sync, with
        // strain, companions, and thought count.
        LiveSeshActivityController.update(
            stageRaw: stage.rawValue, startedAt: startedAt, rollSeconds: rollFinalSeconds,
            strainName: strainName, companionCount: invited.count, thoughtCount: capturedThoughts.count)
        // Reflect the in-progress sesh on the Home Screen widget.
        SeshWidgetBridge.update(streak: session.currentStreak,
                                lastStrain: session.entries.first?.strain ?? "—",
                                stashCount: session.stashRemaining.count,
                                isLive: true, liveStrain: strainName)
    }

    // MARK: Setup

    private var setupView: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Start sesh", onBack: { dismiss() })
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pickerSection("Who's Joining?", ["Just Me", "Invite Friends", "Existing Cyph"], $whoJoining)
                    inviteSection
                    sessionTypeSection
                    pickerSection2("Privacy",
                                   [("Private", CypherVisibility.privateCypher), ("Friends", .friends), ("Public", .publicCypher)],
                                   $privacy)
                    PrimaryButton(title: "Begin sesh", icon: "play.fill") { beginSesh() }
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18).padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder private var inviteSection: some View {
        if whoJoining == "Invite Friends" {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Invite")
                FlowLayout(spacing: 8) {
                    ForEach(social.friends) { f in
                        Button {
                            if invited.contains(f.displayName) { invited.remove(f.displayName) }
                            else { invited.insert(f.displayName) }
                            Haptics.selection()
                        } label: {
                            Text(f.displayName).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(invited.contains(f.displayName) ? Palette.onGreen : Palette.text)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(Capsule().fill(invited.contains(f.displayName) ? Palette.green : Palette.field))
                                .overlay(Capsule().stroke(Palette.stroke, lineWidth: invited.contains(f.displayName) ? 0 : 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var sessionTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Session Type")
            FlowLayout(spacing: 8) {
                ForEach(SessionType.allCases) { t in
                    Button { sessionType = t; Haptics.selection() } label: {
                        HStack(spacing: 5) {
                            Text(t.emoji)
                            Text(t.rawValue).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(sessionType == t ? Palette.onGreen : Palette.text)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Capsule().fill(sessionType == t ? Palette.green : Palette.field))
                        .overlay(Capsule().stroke(Palette.stroke, lineWidth: sessionType == t ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func beginSesh() {
        startedAt = Date(); elapsed = 0; stage = .pickingStrain
        phase = .live; Haptics.success()
        // Notify any invited friends (Worker pushes them).
        if !invited.isEmpty {
            social.inviteFriends(named: Array(invited),
                                 detail: strainName.isEmpty ? nil : strainName)
        }
        LiveSeshActivityController.start(strain: strainName, stageRaw: stage.rawValue, startedAt: startedAt)
        persistLive()
    }

    private func pickerSection(_ title: String, _ options: [String], _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button { binding.wrappedValue = opt; Haptics.selection() } label: {
                        Text(opt).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(binding.wrappedValue == opt ? Palette.onGreen : Palette.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(binding.wrappedValue == opt ? Palette.green : Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(Palette.stroke, lineWidth: binding.wrappedValue == opt ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func pickerSection2(_ title: String, _ options: [(String, CypherVisibility)], _ binding: Binding<CypherVisibility>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { label, value in
                    Button { binding.wrappedValue = value; Haptics.selection() } label: {
                        Text(label).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(binding.wrappedValue == value ? Palette.onGreen : Palette.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(binding.wrappedValue == value ? Palette.green : Palette.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(Palette.stroke, lineWidth: binding.wrappedValue == value ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Live

    private var liveView: some View {
        VStack(spacing: 0) {
            // Header with timer
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer()
                VStack(spacing: 1) {
                    Text(sessionType.emoji + " " + sessionType.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(seshDuration(elapsed)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.gold).monospacedDigit()
                }
                Spacer()
                Image(systemName: "xmark").font(.system(size: 16)).foregroundStyle(.clear)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 20) {
                    if !invited.isEmpty {
                        Text("Seshing with " + invited.joined(separator: ", "))
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            .padding(.top, 6)
                    }

                    // Accordion stepper: completed steps stay above, the current
                    // step expands with its detail + controls, incomplete steps
                    // sit below. Content lives between current and incomplete.
                    accordionStepper.padding(.horizontal, 18)

                    Color.clear.frame(height: 30)
                }
            }
        }
        .onAppear { startTimer() }
    }

    private var orderedStages: [SeshStage] { SeshStage.allCases }
    private func isDone(_ s: SeshStage) -> Bool {
        orderedStages.firstIndex(of: s)! < orderedStages.firstIndex(of: stage)!
    }

    private var accordionStepper: some View {
        VStack(spacing: 10) {
            ForEach(orderedStages) { s in
                if isDone(s) {
                    completedRow(s)
                } else if s == stage {
                    currentStepCard(s)
                } else {
                    incompleteRow(s)
                }
            }
        }
    }

    /// A finished step — compact, stays in place above the current step.
    private func completedRow(_ s: SeshStage) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Palette.green).frame(width: 28, height: 28)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.onGreen)
            }
            Text(s.rawValue).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field.opacity(0.5)))
    }

    /// The current step — expanded with its detail and step-specific controls.
    private func currentStepCard(_ s: SeshStage) -> some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Palette.gold).frame(width: 32, height: 32)
                        Text(s.emoji).font(.system(size: 15))
                    }
                    Text(s.rawValue).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                    Spacer()
                }
                Text(s.detail).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Step-specific content (between current step and incomplete steps).
                stepContent(s)

                // Advance control (the rolling step is gated by the roll timer).
                advanceControl(s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An upcoming step — compact, muted, below the current step.
    private func incompleteRow(_ s: SeshStage) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Palette.field).frame(width: 28, height: 28)
                Text(s.emoji).font(.system(size: 13)).opacity(0.5)
            }
            Text(s.rawValue).font(.system(size: 14)).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Per-step content

    @ViewBuilder private func stepContent(_ s: SeshStage) -> some View {
        switch s {
        case .pickingStrain:
            VStack(alignment: .leading, spacing: 8) {
                InputField(label: "", placeholder: "Strain name…", value: $strainName)
                if !strainName.isEmpty {
                    let matches = strains.strains.filter { $0.name.lowercased().contains(strainName.lowercased()) }.prefix(4)
                    ForEach(Array(matches)) { m in
                        Button { strainName = m.name; Haptics.selection(); persistLive() } label: {
                            HStack { Text(m.name).font(.system(size: 14)).foregroundStyle(Palette.text); Spacer() }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .rollingUp:
            rollTimerContent
        case .smoking:
            thoughtContent
        default:
            EmptyView()
        }
    }

    /// The roll timer — play/stop, ties into Personal Records.
    private var rollTimerContent: some View {
        VStack(spacing: 12) {
            // Joint vs Blunt picker (which record it sets)
            HStack(spacing: 8) {
                ForEach(["Joint", "Blunt"], id: \.self) { m in
                    Button { rollMethod = m; Haptics.selection() } label: {
                        Text(m).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(rollMethod == m ? Palette.onGreen : Palette.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(rollMethod == m ? Palette.green : Palette.field))
                    }.buttonStyle(.plain)
                }
            }

            // Big timer readout
            Text(seshDuration(rollStartedAt != nil ? rollElapsed : Double(rollFinalSeconds ?? 0)))
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(rollStartedAt != nil ? Palette.gold : Palette.text)

            if rollStartedAt == nil && rollFinalSeconds == nil {
                // Not started yet
                Button { startRoll() } label: {
                    Label("Start your roll", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                }.buttonStyle(.plain)
            } else if rollStartedAt != nil {
                // Rolling — stop button
                Button { stopRoll() } label: {
                    Label("Stop — done rolling", systemImage: "stop.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.moodAngry))
                }.buttonStyle(.plain)
            } else {
                // Finished — show result + allow redo
                VStack(spacing: 8) {
                    Text("Rolled in \(seshDuration(Double(rollFinalSeconds ?? 0)))")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.greenBright)
                    Button { rollFinalSeconds = nil; rollElapsed = 0 } label: {
                        Text("Roll again").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var thoughtContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { showThoughtField.toggle() } } label: {
                HStack {
                    Image(systemName: "lightbulb").foregroundStyle(Palette.gold)
                    Text(capturedThoughts.isEmpty ? "Add thoughts to this sesh" : "\(capturedThoughts.count) thought\(capturedThoughts.count == 1 ? "" : "s") added")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                    Spacer()
                    Image(systemName: showThoughtField ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            }.buttonStyle(.plain)

            if showThoughtField {
                // Already-captured thoughts
                ForEach(Array(capturedThoughts.enumerated()), id: \.offset) { idx, t in
                    HStack(spacing: 8) {
                        Image(systemName: "quote.opening").font(.system(size: 11)).foregroundStyle(Palette.gold)
                        Text(t).font(.system(size: 13)).foregroundStyle(Palette.text).lineLimit(2)
                        Spacer()
                        Button { capturedThoughts.remove(at: idx); persistLive(); Haptics.selection() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.textTertiary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.field))
                }

                // Input — press return to capture and start another immediately
                HStack(spacing: 8) {
                    TextField("", text: $attachedThought,
                              prompt: Text("What's on your mind?…").foregroundStyle(Palette.textTertiary))
                        .foregroundStyle(Palette.text)
                        .focused($thoughtFieldFocused)
                        .submitLabel(.next)
                        .onSubmit { captureThought() }
                    Button { captureThought() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(attachedThought.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(attachedThought.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))

                Text("Press return to add another.").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// Capture the current draft as a thought and keep the field ready for the next.
    private func captureThought() {
        let t = attachedThought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        capturedThoughts.append(t)
        attachedThought = ""
        thoughtFieldFocused = true   // keep focus for an immediate next thought
        persistLive()
        Haptics.selection()
    }

    /// The advance / finish control for the current step.
    @ViewBuilder private func advanceControl(_ s: SeshStage) -> some View {
        if s == .finished {
            PrimaryButton(title: "Save to Journal", icon: "checkmark") { phase = .save; Haptics.success() }
        } else if s == .rollingUp {
            // Can only move on once the roll has been timed (or skipped).
            let rolled = rollFinalSeconds != nil
            PrimaryButton(title: rolled ? "Sparked up — next" : "Skip roll timer", icon: "arrow.right") {
                if !rolled { rollFinalSeconds = 0 }  // skipped, no record
                advance()
            }
            .opacity(rollStartedAt != nil ? 0.4 : 1)
            .disabled(rollStartedAt != nil)   // can't advance mid-roll
        } else {
            PrimaryButton(title: nextLabel, icon: "arrow.right") { advance() }
                .disabled(s == .pickingStrain && strainName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var nextLabel: String {
        let all = orderedStages
        let idx = all.firstIndex(of: stage)!
        return idx + 1 < all.count ? "Next: \(all[idx + 1].rawValue)" : "Finish"
    }

    private func startRoll() {
        rollStartedAt = Date(); rollElapsed = 0; rollFinalSeconds = nil
        Haptics.tap()
        Task {
            while rollStartedAt != nil {
                try? await Task.sleep(for: .seconds(1))
                if let start = rollStartedAt { rollElapsed = Date().timeIntervalSince(start) }
            }
        }
    }

    private func stopRoll() {
        guard let start = rollStartedAt else { return }
        let secs = Int(Date().timeIntervalSince(start))
        rollFinalSeconds = secs
        rollStartedAt = nil
        let isRecord = session.submitRollTime(seconds: secs, method: rollMethod)
        rollWasRecord = isRecord
        showRollComplete = true
        if isRecord {
            Haptics.success()
            // Tell friends about the new record (push + feed).
            let t = String(format: "%d:%02d", secs / 60, secs % 60)
            social.broadcastMilestone(kind: "roll_record",
                                      detail: "\(rollMethod) rolled in \(t)")
        } else { Haptics.tap() }
        persistLive()
    }

    private func advance() {
        let all = orderedStages
        guard let idx = all.firstIndex(of: stage), idx + 1 < all.count else { return }
        stage = all[idx + 1]
        Haptics.tap()
        social.setMyActivity(stage.activity, detail: strainName.isEmpty ? nil : strainName)
        persistLive()
    }

    private func startTimer() {
        Task {
            while phase == .live && stage != .finished {
                try? await Task.sleep(for: .seconds(1))
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }
}

// MARK: - Save sheet (Finish → Save to Journal)

