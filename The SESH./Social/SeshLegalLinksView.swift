import SwiftUI

struct SeshLegalLinksView: View {
    private let links: [(String, String, String)] = [
        ("Privacy Policy", "hand.raised.fill", "https://sahmoee.github.io/The-Sesh/privacy.html"),
        ("License", "doc.text.fill", "https://sahmoee.github.io/The-Sesh/license.html"),
        ("Support", "questionmark.circle.fill", "https://sahmoee.github.io/The-Sesh/support.html"),
        ("Apple Standard EULA", "checkmark.seal.fill", "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Policies & Support")
                    ForEach(links, id: \.0) { title, symbol, address in
                        if let url = URL(string: address) {
                            Link(destination: url) {
                                HStack(spacing: 12) {
                                    Image(systemName: symbol)
                                        .foregroundStyle(Palette.greenBright)
                                        .frame(width: 28)
                                    Text(title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Palette.text)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Palette.field))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(Palette.stroke, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Policies & Support")
    }
}
