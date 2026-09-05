//
//  ConnectivityBanner.swift
//  The SESH
//
//  (#App14, #App15) A drop-in banner that shows the real connectivity state
//  with a recovery action. Attach beneath a screen's title (or above the tab
//  bar) on any view that shows server data:
//
//      ConnectivityBanner { await social.refresh() }
//
//  It renders nothing while data is current, so it can stay mounted.
//

import SwiftUI

struct ConnectivityBanner: View {
    var retry: (() async -> Void)? = nil

    @State private var retrying = false
    private var monitor: ConnectivityMonitor { .shared }
    private var outbox: OfflineOutbox { .shared }

    var body: some View {
        let state = monitor.state
        if state.showsBanner || outbox.statusMessage != nil {
            VStack(alignment: .leading, spacing: 8) {
                if state.showsBanner {
                    Label(state.label, systemImage: state == .offline ? "wifi.slash" : "exclamationmark.icloud")
                        .font(.seshScaled(13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
                if let status = outbox.statusMessage {
                    Label(status, systemImage: "tray.and.arrow.up")
                        .font(.seshScaled(13)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("outbox.recoveryStatus")
                }
                Text("Private journal saves remain available without a connection.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                if retry != nil || outbox.canRetry {
                    Button {
                        guard !retrying else { return }
                        retrying = true
                        Task {
                            defer { retrying = false }
                            if outbox.canRetry { outbox.retryHeldOperations() }
                            if let retry { await retry() }
                        }
                    } label: {
                        HStack {
                            if retrying { ProgressView().controlSize(.small) }
                            Text(retrying ? "Retrying…" : "Retry connection and saved actions")
                                .font(.seshScaled(13, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }.minimumTapTarget()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.green)
                    .disabled(retrying || state == .offline)
                    .accessibilityHint(state == .offline ? "Reconnect to retry. Unsent actions are retained." : "Retries eligible saved actions for the signed-in account")
                }
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.field)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 1))
            )
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}
