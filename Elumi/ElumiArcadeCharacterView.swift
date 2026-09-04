import SwiftUI

struct ElumiArcadeCharacter: View {
    let mouthOpen: Bool
    let scale: CGFloat
    let rotation: Double
    let sparkleBurst: Bool

    var body: some View {
        Image("SplashCharacter")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 92, height: 92)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            .overlay(alignment: .bottomTrailing) {
                Capsule()
                    .fill(AppTheme.Colors.elumiNavy.opacity(0.95))
                    .frame(width: mouthOpen ? 18 : 8, height: mouthOpen ? 9 : 3)
                    .offset(x: -23, y: -18)
                    .opacity(mouthOpen ? 0.96 : 0.0)
            }
            .overlay {
                if sparkleBurst {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 5, height: 5)
                            .offset(x: 20, y: -8)
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                            .offset(x: 27, y: -1)
                        Circle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 3, height: 3)
                            .offset(x: 17, y: 5)
                    }
                }
            }
    }
}
