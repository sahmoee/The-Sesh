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

    var body: some View {
        let state = monitor.state
        if state.showsBanner {
            HStack(spacing: 10) {
                Image(systemName: state == .offline ? "wifi.slash" : "exclamationmark.icloud")
                    .font(.system(size: 14, weight: .semibold))
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let retry {
                    Button {
                        guard !retrying else { return }
                        retrying = true
                        Task {
                            defer { retrying = false }
                            await retry()
                        }
                    } label: {
                        if retrying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Retry").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry")
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.label)
        }
    }
}
