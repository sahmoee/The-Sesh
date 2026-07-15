//
//  BuildConfig.swift
//  The SESH
//
//  Build metadata + the social backend URL. Version and build number are read
//  automatically from the app bundle's Info.plist (CFBundleShortVersionString /
//  CFBundleVersion), so they always match whatever Xcode is shipping — there's
//  nothing to hand-edit here on each build. Set the version in the target's
//  General tab (Marketing Version / Current Project Version), or let Xcode
//  auto-increment the build number, and this reflects it.
//

import Foundation

enum BuildConfig {
    /// Marketing version, e.g. "1.0.0" — from CFBundleShortVersionString.
    static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()

    /// Build number, e.g. "250" — from CFBundleVersion.
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()

    /// Numeric build, when needed for comparisons.
    static var buildNumber: Int { Int(build) ?? 0 }

    /// The app's display name from the bundle (falls back to "The Sesh").
    static let appName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "The Sesh"
    }()

    /// e.g. "The Sesh (250) v1.0.0" — composed, never hand-edited.
    static var displayLabel: String { "\(appName) (\(build)) v\(version)" }

    /// Codename for this line of builds (cosmetic; update if you like).
    static let buildName = "Cypher"

    /// (#C10) SESH social Worker, per environment. Debug builds can point at a
    /// dev/staging Worker without touching code: set the override once via
    ///   UserDefaults.standard.set("https://sesh-worker-dev.stocked.workers.dev",
    ///                             forKey: "sesh.dev.workerURL")
    /// (or an Xcode scheme launch argument). Release always uses production.
    static let workerURL: String = {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "sesh.dev.workerURL"),
           !override.isEmpty {
            return override
        }
        #endif
        return "https://sesh-worker.stocked.workers.dev"
    }()
}
