import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("OpenType")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.top, 12)

            Text(L("about.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("v0.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Text(L("about.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .frame(maxWidth: 320)

            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com/IchenDEV/opentype")!)
                Link(L("about.feedback"), destination: URL(string: "https://github.com/IchenDEV/opentype/issues")!)
            }
            .font(.caption)
            .padding(.top, 20)

            Spacer()

            Text("© 2026 OpenType")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
