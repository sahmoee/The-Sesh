//
//  StorageHealthBanner.swift
//  The SESH
//
//  Surfaces the SwiftData fallback states that were previously silent.
//  When the on-disk store failed to open, SeshDataStore runs memory-only
//  (`isEphemeral`) — everything looks normal but nothing survives a relaunch.
//  This banner makes that visible instead of letting data vanish silently.
//
//  Drop-in like ConnectivityBanner: renders nothing while storage is healthy,
//  so it can stay mounted (e.g. at the top of the root view).
//

import SwiftUI

struct StorageHealthBanner: View {
    private var showsBanner: Bool {
        SeshDataStore.shared.isEphemeral || SeshDataStore.shared.isUnavailable
    }

    private var message: String {
        if SeshDataStore.shared.isUnavailable {
            return "Storage unavailable — data won't be saved"
        }
        return "Storage unavailable — data won't be saved after you close the app"
    }

    var body: some View {
        if showsBanner {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
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
            .accessibilityLabel(message)
        }
    }
}
