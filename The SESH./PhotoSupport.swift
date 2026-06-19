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
    nonisolated private static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SeshPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

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
    func downscaled(to maxDimension: CGFloat) -> UIImage {
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

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                BudThumb(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: name) { await load() }
    }

    private func load() async {
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
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let saved = PhotoStore.save(img) {
                    PhotoStore.delete(photoName)
                    await MainActor.run { photoName = saved }
                }
            }
        }
    }
}
