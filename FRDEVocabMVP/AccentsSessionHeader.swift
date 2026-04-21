import SwiftUI

/// Einheitlicher Header für Lernen / Üben / Speed Round im Akzent-Modul.
///
/// Layout: Back-Chevron links (AppBackButton), „Akzente"-Titel mittig,
/// optionaler trailing-Content rechts (z. B. „3/10" Progress-Zähler).
/// Damit haben alle drei Session-Modi oben exakt dieselbe Kopfzeile —
/// identisch zur Setup-Logik in `ScreenHeaderCard(centeredTitle: true)`.
struct AccentsSessionHeader<Trailing: View>: View {
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text("Akzente")
                .font(AppTheme.Typography.screenTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                AppBackButton(action: onBack, tint: AppTheme.Colors.moduleAccents)
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }
}

extension AccentsSessionHeader where Trailing == EmptyView {
    /// Convenience: Header ohne trailing-Content (z. B. Lernen-Modus).
    init(onBack: @escaping () -> Void, trailing: Void? = nil) {
        self.onBack = onBack
        self.trailing = { EmptyView() }
    }
}
