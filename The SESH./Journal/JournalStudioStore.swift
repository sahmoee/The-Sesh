import Foundation
import Observation

@MainActor @Observable
final class JournalStudioStore {
    static let shared = JournalStudioStore()
    private(set) var snapshot = JournalStudioSnapshot()
    private(set) var error: String?
    private var isReadable = true
    private let file: URL

    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory.appending(path: "JournalStudio/organization.json")
        load()
    }

    func load() {
        do {
            guard FileManager.default.fileExists(atPath: file.path) else {
                snapshot = JournalStudioSnapshot(); isReadable = true; error = nil
                return
            }
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(JournalStudioSnapshot.self, from: data)
            guard decoded.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            snapshot = decoded
            isReadable = true
            error = nil
        } catch {
            isReadable = false
            self.error = "Journal organization could not be read. Your original file and journal are preserved. Try again after unlocking the device."
        }
    }

    @discardableResult
    func change(_ edit: (inout JournalStudioSnapshot) -> Void) -> Bool {
        guard isReadable else { return false }
        var next = snapshot
        edit(&next)
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            snapshot = next // publish only after the local write succeeds
            error = nil
            return true
        } catch {
            self.error = "Your change could not be saved. Free some storage and try again; your previous organization is intact."
            return false
        }
    }

    func togglePin(_ id: UUID) {
        change { if !$0.pinned.insert(id).inserted { $0.pinned.remove(id) } }
    }

    func toggleMembership(_ id: UUID, notebook: UUID) {
        change {
            guard let index = $0.notebooks.firstIndex(where: { $0.id == notebook }) else { return }
            if !$0.notebooks[index].entryIDs.insert(id).inserted { $0.notebooks[index].entryIDs.remove(id) }
        }
    }

    func saveReflection(_ reflection: JournalReflection) -> Bool {
        change {
            if let index = $0.reflections.firstIndex(where: { $0.id == reflection.id }) {
                $0.reflections[index] = reflection
            } else { $0.reflections.append(reflection) }
        }
    }

    func removeReferences(to id: UUID) {
        change {
            $0.pinned.remove(id)
            $0.reflections.removeAll { $0.id == id }
            for index in $0.notebooks.indices { $0.notebooks[index].entryIDs.remove(id) }
        }
    }

    /// Called only by the existing explicit journal/full-reset actions. A corrupt
    /// organization file must also be erasable without first decoding it.
    func clear() {
        do {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            snapshot = JournalStudioSnapshot(); isReadable = true; error = nil
        } catch {
            self.error = "Private journal organization could not be erased. Try again after unlocking the device."
        }
    }
}
