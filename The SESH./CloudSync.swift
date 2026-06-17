//
//  CloudSync.swift
//  The SESH
//
//  Lightweight iCloud sync via NSUbiquitousKeyValueStore (key-value store).
//  We mirror the app's JSON blobs (sessions, thoughts, rants, name, theme,
//  profile) to iCloud so they restore automatically on a new device signed
//  into the same Apple ID. KVS is ideal here: no CloudKit schema, syncs in the
//  background, and our data is well under the 1MB total budget.
//
//  Design: every local write also writes to iCloud (CloudSync.set). On launch
//  and on external-change notifications, we pull iCloud values into
//  UserDefaults when iCloud is the source of truth, then tell the app to reload.
//
//  Requires the iCloud > Key-value storage capability enabled on the app target.
//

import Foundation

enum CloudSync {
    /// The iCloud key-value store, or nil if it can't be used on this build
    /// (e.g. the entitlement isn't present, or the user has no iCloud account).
    /// Accessing it lazily and defensively means a misconfigured entitlement
    /// degrades to local-only storage instead of crashing the app.
    private static let kv: NSUbiquitousKeyValueStore? = {
        // If iCloud isn't available at all, don't touch the store.
        guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
        return NSUbiquitousKeyValueStore.default
    }()

    /// True only when iCloud KVS is actually usable.
    static var isAvailable: Bool { kv != nil }

    /// Master switch — users can disable iCloud sync in Settings. Off whenever
    /// the store isn't available, regardless of the saved preference.
    static var isEnabled: Bool {
        get {
            guard isAvailable else { return false }
            return UserDefaults.standard.object(forKey: "sesh.icloud.enabled") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "sesh.icloud.enabled") }
    }

    // MARK: Mirrored writes (UserDefaults + iCloud)

    static func set(_ data: Data, forKey key: String) {
        UserDefaults.standard.set(data, forKey: key)
        guard isEnabled, let kv else { return }
        kv.set(data, forKey: key)
        kv.synchronize()
    }

    static func set(_ string: String, forKey key: String) {
        UserDefaults.standard.set(string, forKey: key)
        guard isEnabled, let kv else { return }
        kv.set(string, forKey: key)
        kv.synchronize()
    }

    static func set(_ flag: Bool, forKey key: String) {
        UserDefaults.standard.set(flag, forKey: key)
        guard isEnabled, let kv else { return }
        kv.set(flag, forKey: key)
        kv.synchronize()
    }

    // MARK: Pull iCloud → local

    /// Copy any iCloud values into UserDefaults for the given keys. Returns true
    /// if anything was newer in iCloud (so the caller can reload).
    @discardableResult
    static func pullIntoDefaults(keys: [String]) -> Bool {
        guard isEnabled, let kv else { return false }
        kv.synchronize()
        var changed = false
        let d = UserDefaults.standard
        for key in keys {
            if let data = kv.data(forKey: key) {
                let localData = d.data(forKey: key)
                if localData != data { d.set(data, forKey: key); changed = true }
            } else if let str = kv.string(forKey: key) {
                if d.string(forKey: key) != str { d.set(str, forKey: key); changed = true }
            }
        }
        return changed
    }

    /// Begin observing external iCloud changes (e.g. another device wrote new
    /// data). Calls `onChange` on the main actor when relevant keys update.
    static func startObserving(keys: [String], onChange: @escaping () -> Void) {
        guard let kv else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv, queue: .main
        ) { note in
            guard isEnabled else { return }
            let changedKeys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            guard changedKeys.contains(where: { keys.contains($0) }) else { return }
            if pullIntoDefaults(keys: keys) { onChange() }
        }
        kv.synchronize()
    }
}
