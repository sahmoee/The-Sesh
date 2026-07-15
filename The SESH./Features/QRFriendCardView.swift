//
//  QRFriendCardView.swift
//  The SESH
//
//  (Feature 8) QR friend card. Your friend code as a scannable QR
//  (sesh://friend/SESH-XXXX) plus the plain code, shareable as an image.
//  Scanning a friend's card with the iPhone camera deep-links into the app.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRFriendCardView: View {
    @Environment(SocialStore.self) private var social

    private var code: String { social.friendCode }
    private var payload: String { "sesh://friend/\(code)" }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    card
                    ShareLink(item: renderCard(),
                              preview: SharePreview("Add me on The SESH", image: renderCard())) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share my card").font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.green))
                        .foregroundStyle(.white)
                    }
                    Text("Friends scan this with their camera — it opens The SESH with your code filled in. Turn off \"Discoverable by friend code\" in Privacy & Safety to pause new adds.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
        }
        .navigationTitle("QR Friend Card")
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text(social.me.displayName)
                .font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(.white)
            if let qr = Self.qrImage(payload) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 190, height: 190)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .accessibilityLabel("QR code for friend code \(code)")
            }
            Text(code)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            Text("The SESH").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(26)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.18),
                                              Color(red: 0.04, green: 0.12, blue: 0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    static func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    @MainActor
    private func renderCard() -> Image {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "qrcode")
    }
}
