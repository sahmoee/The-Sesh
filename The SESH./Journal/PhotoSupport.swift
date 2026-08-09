//
//  PhotoSupport.swift
//  HighThoughts
//
//  Real photo capture + storage. Images are written to the app's Documents
//  directory and referenced by filename in models (JournalEntry.photoName,
//  Rant.photoName). Includes a camera-or-library picker and a disk-backed
//  image view used across the app.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Photo storage

/// Persists captured images to Documents/SeshPhotos and hands back a stable
/// filename to store on the model. Keeps the JSON small (no base64 blobs).
enum PhotoStore {
    /// Cached once — the old computed property hit the filesystem (exists check
    /// + create) on every access.
    nonisolated private static let folder: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SeshPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    nonisolated static func url(for name: String) -> URL { folder.appendingPathComponent(name) }

    /// Downscales to a sane max dimension and saves as JPEG. Returns the filename.
    @discardableResult
    nonisolated static func save(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> String? {
        let scaled = image.downscaled(to: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
        let name = "sesh_\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    nonisolated static func load(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        return UIImage(contentsOfFile: url(for: name).path)
    }

    nonisolated static func delete(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

private extension UIImage {
    nonisolated func downscaled(to maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Disk-backed image view

/// Loads a stored image by filename, off the main actor, with a placeholder.
struct StoredImage: View {
    let name: String?
    var size: CGFloat = 56
    var corner: CGFloat = Radius.sm
    /// When set, resolve through StrainImageStore (user photo -> remote -> art)
    /// instead of only the local PhotoStore. The procedural fallback is seeded
    /// from this id so each strain has a stable look.
    var strainID: String? = nil

    @Environment(StrainImageStore.self) private var strainImages
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                BudThumb(size: size, seed: budSeed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: taskKey) { await load() }
    }

    /// Re-run loading when either the photo name or the strain id changes.
    private var taskKey: String { "\(name ?? "")|\(strainID ?? "")" }

    /// Stable BudThumb seed: prefer the strain id, else the photo name, else 0.
    /// Routed through StrainImageStore.budIndex so it's identical across
    /// launches (String.hashValue is per-launch randomized, and abs() can trap).
    private var budSeed: Int {
        if let strainID, !strainID.isEmpty { return StrainImageStore.budIndex(for: strainID) }
        if let name, !name.isEmpty { return StrainImageStore.budIndex(for: name) }
        return 0
    }

    private func load() async {
        // Strain-aware path: let the store resolve the best image.
        if let strainID, !strainID.isEmpty {
            image = await strainImages.image(strainID: strainID)
            return
        }
        // Legacy path: local PhotoStore only.
        guard let name, !name.isEmpty else { image = nil; return }
        let loaded = await Task.detached(priority: .utility) { PhotoStore.load(name) }.value
        await MainActor.run { image = loaded }
    }
}

// MARK: - Camera picker (UIKit bridge)

/// Wraps UIImagePickerController so we can offer the actual camera (PhotosUI
/// alone can't capture). Library picks go through PhotosPicker elsewhere.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo field (camera + library + preview)

/// A reusable photo control: shows the current photo (or an "add" affordance),
/// offers Camera / Photo Library / Remove via a confirmation dialog, and writes
/// the chosen image to PhotoStore, binding the resulting filename.
struct PhotoField: View {
    @Binding var photoName: String?
    var size: CGFloat = 56

    @State private var showDialog = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadFailed = false

    var body: some View {
        Button { showDialog = true } label: {
            ZStack {
                if let photoName, !photoName.isEmpty {
                    StoredImage(name: photoName, size: size)
                } else {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.field)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                        .overlay(Image(systemName: "camera").font(.system(size: 17)).foregroundStyle(Palette.textSecondary))
                        .frame(width: size, height: size)
                }
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog("Photo", isPresented: $showDialog, titleVisibility: .hidden) {
            Button("Take Photo") { showCamera = true }
            PhotosPicker("Choose from Library", selection: $pickerItem, matching: .images)
            if photoName?.isEmpty == false {
                Button("Remove Photo", role: .destructive) {
                    PhotoStore.delete(photoName)
                    photoName = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                if let saved = PhotoStore.save(img) {
                    PhotoStore.delete(photoName)
                    photoName = saved
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                // Reset the selection when done so re-picking the same photo
                // fires onChange again.
                defer { pickerItem = nil }
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let img = UIImage(data: data),
                          let saved = PhotoStore.save(img) else {
                        loadFailed = true
                        return
                    }
                    PhotoStore.delete(photoName)
                    photoName = saved
                } catch {
                    loadFailed = true
                }
            }
        }
        .alert("Couldn't add photo", isPresented: $loadFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That photo couldn't be loaded. Try picking a different one.")
        }
    }
}

// MARK: - Strain photo (tap to add)

/// A strain's hero image with a "tap to add a photo" affordance. Shows the
/// resolved image (user photo -> remote -> procedural art) and lets the user
/// attach their own real photo, which is stored per-strain in StrainImageStore
/// and always takes priority. If the image is a CC-licensed remote photo, its
/// attribution line is shown beneath.
struct StrainPhotoButton: View {
    let strain: StrainProfile
    var size: CGFloat = 84

    @Environment(StrainImageStore.self) private var strainImages
    @State private var showDialog = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    /// Bumped after a change to force the inner StoredImage to reload.
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showDialog = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    StoredImage(name: strain.photoName, size: size,
                                corner: Radius.md, strainID: strain.id)
                        .id(reloadToken)
                    // Small camera chip so it's clearly tappable.
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.onGreen)
                        .padding(6)
                        .background(Circle().fill(Palette.green))
                        .overlay(Circle().stroke(Palette.card, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)

            if let credit = strainImages.attribution(strainID: strain.id) {
                Text(credit)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: size, alignment: .leading)
            }
        }
        .confirmationDialog("Strain Photo", isPresented: $showDialog, titleVisibility: .hidden) {
            Button("Take Photo") { showCamera = true }
            PhotosPicker("Choose from Library", selection: $pickerItem, matching: .images)
            if strainImages.hasUserPhoto(strainID: strain.id) {
                Button("Remove My Photo", role: .destructive) {
                    strainImages.removeUserPhoto(strainID: strain.id)
                    reloadToken += 1
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                strainImages.setUserPhoto(img, strainID: strain.id)
                reloadToken += 1
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                // Reset so re-picking the same photo fires onChange again.
                defer { pickerItem = nil }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        strainImages.setUserPhoto(img, strainID: strain.id)
                        reloadToken += 1
                    }
                }
            }
        }
    }
}
