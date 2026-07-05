import SwiftUI

struct HomeView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer().frame(height: 34)

            Text("SIGNED IN")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FuseColor.accent)
            Text(session.email ?? "your account")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(FuseColor.ink)
                .padding(.top, 6)

            Spacer().frame(height: 26)

            deviceCard
            Spacer().frame(height: 16)
            Text("Next: pair with your phone to connect the two devices.")
                .font(.system(size: 14))
                .foregroundStyle(FuseColor.muted)

            Spacer()

            SecondaryButton(title: "Sign out") { session.clear() }
        }
        .padding(32)
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FuseColor.bg)
    }

    private var deviceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FuseColor.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 20))
                    .foregroundStyle(FuseColor.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("This device").font(.system(size: 15, weight: .semibold)).foregroundStyle(FuseColor.ink)
                Text("macOS · ready to connect")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(FuseColor.outline.opacity(0.6), lineWidth: 1),
        )
    }
}
