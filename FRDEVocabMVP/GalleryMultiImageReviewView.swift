import SwiftUI

/// **Galerie-Mehrbild-Review** (User-Spec 2026-04-23 nachmittags).
///
/// Wird präsentiert, wenn der User ≥2 Bilder aus der Foto-Galerie
/// auswählt. Jedes Bild bekommt seinen eigenen Optimierungs-Zustand:
/// Quality-Report, optionale Optimierung, Original-vs-Optimized-Toggle.
///
/// Unterscheidung zu `MultiCaptureReviewView`:
///   • MultiCaptureReviewView (Camera-Multi-Shot): „pick eins zum
///     Reviewen" → einzelnes Bild geht durch den Single-Image-Pfad
///   • GalleryMultiImageReviewView (Galerie-Multi-Select): „review
///     alle, optimiere wahlweise einzelne, dann ALLE in die Pipeline"
///     → Batch-Sequenz-Verarbeitung
///
/// **UI**:
///   • Big-Preview mit TabView (Swipe links/rechts)
///   • Page-Indikator „X von Y"
///   • Filmstrip unten (tappbar; Selection-Marker)
///   • Pro selektiertem Bild: Quality-Banner (wenn Issues) +
///     „Auto optimieren" / „Original verwenden"
///   • Footer-CTA: „Übernehmen und analysieren" → reicht ALLE
///     `finalImage`-Werte an den Caller
struct GalleryMultiImageReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var items: [GalleryReviewItem]
    @Binding var selectedItemID: UUID?

    let sectionStyle: AppSectionStyle
    /// Wird beim Erscheinen je Item aufgerufen (Quality-Analyse läuft).
    let onAnalyzeQuality: (GalleryReviewItem) async -> (report: ImageQualityAnalyzer.Report, recommendedProfile: ImageQualityAnalyzer.EnhancementProfile?)
    /// Wird gerufen, wenn der User „Auto optimieren" tippt.
    let onOptimizeItem: (GalleryReviewItem) async -> UIImage?
    /// Wird gerufen, wenn der User auf „Übernehmen und analysieren" tippt
    /// — Caller bekommt die finalen Bilder in Picker-Reihenfolge.
    let onSubmitAll: ([GalleryReviewItem]) -> Void

    /// **State für „Alle auto-optimieren"** (UX-Update 2026-04-23 nacht).
    /// `isOptimizingAll` ist die Spinner-/Disable-Quelle für den
    /// globalen Button. `optimizeAllProcessedCount` ist der Live-Counter
    /// (1 von 5, 2 von 5, …) für den Button-Text. `lastBatchSummary`
    /// hält die Zusammenfassung nach Abschluss (für 3s sichtbar).
    @State private var isOptimizingAll: Bool = false
    @State private var optimizeAllProcessedCount: Int = 0
    @State private var lastBatchSummary: BatchOptimizationSummary?

    fileprivate struct BatchOptimizationSummary: Equatable {
        let optimized: Int
        let total: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    bigPreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    qualityPanel
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                    if let summary = lastBatchSummary {
                        batchSummaryBanner(summary)
                            .padding(.horizontal, 18)
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                    filmstrip
                        .padding(.vertical, 10)
                    submitFooter
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
            }
            .background(AppTheme.Colors.background)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lastBatchSummary)
        .onAppear(perform: ensureSelection)
        .task(id: selectedItemID) {
            await analyzeIfNeeded()
        }
    }

    /// Kompaktes Banner unter dem Quality-Panel — zeigt das Resultat
    /// von „Alle auto-optimieren" (z. B. „4 von 5 Bildern optimiert").
    /// Wird nach 3s automatisch ausgeblendet (siehe `optimizeAllItems`).
    private func batchSummaryBanner(_ summary: BatchOptimizationSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)
            Text("\(summary.optimized) von \(summary.total) Bildern optimiert")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.success.opacity(0.12))
        )
    }

    // MARK: - Header-Title

    private var navigationTitleText: String {
        guard !items.isEmpty else { return "Bilder prüfen" }
        let pos = (currentIndex ?? 0) + 1
        return "\(pos) von \(items.count)"
    }

    // MARK: - Big-Preview

    private var bigPreview: some View {
        TabView(selection: bindingForSelection) {
            ForEach(items) { item in
                ZStack {
                    Color.black.opacity(0.55)
                    Image(uiImage: item.displayImage)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                    if item.optimizationApplied {
                        statusBadge(text: "Optimiert", color: AppTheme.Colors.success, system: "wand.and.stars")
                    }
                }
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func statusBadge(text: String, color: Color, system: String) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: system)
                        .font(.system(size: 12, weight: .bold))
                    Text(text)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(color))
                .padding(12)
            }
            Spacer()
        }
    }

    private var bindingForSelection: Binding<UUID> {
        Binding(
            get: {
                selectedItemID ?? items.first?.id ?? UUID()
            },
            set: { newID in
                selectedItemID = newID
            }
        )
    }

    // MARK: - Quality-Panel + Per-Item-Aktion

    @ViewBuilder
    private var qualityPanel: some View {
        if let item = currentItem {
            VStack(spacing: 8) {
                qualityHint(for: item)
                actionRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func qualityHint(for item: GalleryReviewItem) -> some View {
        if let report = item.qualityReport, report.level != .good {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.Colors.warning)
                Text(report.issues.first?.hint ?? "Bild könnte verbessert werden")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.Colors.warning.opacity(0.12))
            )
        } else if item.qualityReport == nil {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("Bildqualität wird geprüft …")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func actionRow(for item: GalleryReviewItem) -> some View {
        // **UX-Update 2026-04-23 nacht**: bei mehreren Bildern wird
        // der per-Item „Auto optimieren"-Button durch einen globalen
        // „Alle auto-optimieren" ersetzt. Per-Item „Original verwenden"
        // bleibt erhalten, damit der User für einzelne Bilder zurück
        // auf das Original kann. Die Optimierungs-Logik LÄUFT INTERN
        // PRO BILD — kein globaler Filter wird auf alle übertragen.
        HStack(spacing: 10) {
            if item.optimizationApplied {
                revertOriginalButton
            } else if items.count > 1 {
                // Multi-Image-Modus: globaler Button (gleicher Slot,
                // andere Beschriftung + andere Aktion).
                optimizeAllButton
            } else if item.recommendedProfile != nil
                       || item.qualityReport?.level == .poor
                       || item.qualityReport?.level == .medium {
                // Single-Image-Modus: per-Item Button wie bisher.
                singleOptimizeButton(for: item)
            }
        }
    }

    private var revertOriginalButton: some View {
        Button { revertCurrent() } label: {
            Label("Original verwenden", systemImage: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func singleOptimizeButton(for item: GalleryReviewItem) -> some View {
        Button { optimizeCurrent() } label: {
            HStack(spacing: 6) {
                if item.isOptimizing {
                    ProgressView().scaleEffect(0.7).tint(.black)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(item.isOptimizing ? "Wird optimiert …" : "Auto optimieren")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.cta)
        )
        .disabled(item.isOptimizing)
    }

    /// **„Alle auto-optimieren"** — Multi-Image-Variante. Triggert
    /// `optimizeAllItems()`, das pro Bild **individuell** Quality-
    /// Analyse + Optimierung durchführt. Originale bleiben erhalten,
    /// per-image-State wird sauber gesetzt.
    private var optimizeAllButton: some View {
        Button { optimizeAllItems() } label: {
            HStack(spacing: 6) {
                if isOptimizingAll {
                    ProgressView().scaleEffect(0.7).tint(.black)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(optimizeAllButtonLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.cta)
        )
        .disabled(isOptimizingAll)
    }

    private var optimizeAllButtonLabel: String {
        if isOptimizingAll {
            // Während des Laufs Live-Counter, damit klar ist, dass
            // die App pro Bild arbeitet.
            return "Optimiere \(optimizeAllProcessedCount) von \(items.count) …"
        }
        return "Alle auto-optimieren"
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        thumbnailButton(for: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: selectedItemID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func thumbnailButton(for item: GalleryReviewItem) -> some View {
        let isSelected = item.id == selectedItemID
        return Button {
            withAnimation(AppMotion.state) {
                selectedItemID = item.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: item.displayImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if item.optimizationApplied {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.success)
                        .background(Circle().fill(.white))
                        .padding(2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? sectionStyle.accent : Color.white.opacity(0.18), lineWidth: isSelected ? 2.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit-Footer

    private var submitFooter: some View {
        Button {
            let snapshot = items
            dismiss()
            DispatchQueue.main.async { onSubmitAll(snapshot) }
        } label: {
            Text("Übernehmen und analysieren")
                .font(AppTheme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .disabled(items.isEmpty)
    }

    // MARK: - Empty-State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Keine Bilder ausgewählt.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer()
        }
    }

    // MARK: - Async-Tasks (Quality + Optimization)

    private func analyzeIfNeeded() async {
        guard let id = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        // Schon analysiert? Skip.
        if items[idx].qualityReport != nil { return }
        let item = items[idx]
        let result = await onAnalyzeQuality(item)
        // Item könnte zwischendurch entfernt worden sein.
        guard let stillIdx = items.firstIndex(where: { $0.id == id }) else { return }
        items[stillIdx].qualityReport = result.report
        items[stillIdx].recommendedProfile = result.recommendedProfile
    }

    private func optimizeCurrent() {
        guard let id = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == id }),
              !items[idx].isOptimizing else { return }
        items[idx].isOptimizing = true
        let item = items[idx]
        Task {
            let optimized = await onOptimizeItem(item)
            await MainActor.run {
                guard let stillIdx = items.firstIndex(where: { $0.id == id }) else { return }
                items[stillIdx].isOptimizing = false
                if let opt = optimized {
                    items[stillIdx].optimizedVariant = opt
                    items[stillIdx].optimizationApplied = true
                }
            }
        }
    }

    /// **„Alle auto-optimieren"** — geht durch alle Items, ruft pro
    /// Item zuerst Quality-Analyse (falls noch nicht da) und dann
    /// Optimierung. Originale bleiben in `originalImage` erhalten.
    /// Bilder, deren `onOptimizeItem`-Callback `nil` zurückgibt
    /// (= keine echte Verbesserung), bleiben auf Original.
    /// Bereits optimierte Items werden übersprungen — kein Re-Run,
    /// keine Doppel-Verbrauch von Compute-Cycles.
    private func optimizeAllItems() {
        guard !isOptimizingAll else { return }
        isOptimizingAll = true
        optimizeAllProcessedCount = 0
        // Batch-Summary verstecken solange ein neuer Lauf läuft.
        lastBatchSummary = nil

        // Snapshot der IDs, damit wir robust gegen mid-flight
        // Mutationen sind (z. B. User wischt während des Laufs).
        let itemIDs = items.map(\.id)
        let totalCount = itemIDs.count

        Task {
            var optimizedCount = 0
            for itemID in itemIDs {
                // Aktuellen Item-State holen (kann sich pro Iteration
                // geändert haben, z. B. wenn Quality-Analyse parallel
                // lief).
                guard let snapshot = await MainActor.run(body: { () -> GalleryReviewItem? in
                    items.first(where: { $0.id == itemID })
                }) else { continue }

                // Schon optimiert? → in Zählung mitnehmen, aber
                // nichts tun.
                if snapshot.optimizationApplied {
                    optimizedCount += 1
                    await MainActor.run { optimizeAllProcessedCount += 1 }
                    continue
                }

                // Quality fehlt? → erst analysieren, dann optimieren.
                var workingItem = snapshot
                if workingItem.qualityReport == nil {
                    let qualityResult = await onAnalyzeQuality(workingItem)
                    await MainActor.run {
                        if let idx = items.firstIndex(where: { $0.id == itemID }) {
                            items[idx].qualityReport = qualityResult.report
                            items[idx].recommendedProfile = qualityResult.recommendedProfile
                            workingItem = items[idx]
                        }
                    }
                }

                // Optimierung anwerfen — pro Item individuell, nie
                // ein globaler Filter.
                await MainActor.run {
                    if let idx = items.firstIndex(where: { $0.id == itemID }) {
                        items[idx].isOptimizing = true
                    }
                }
                let optimized = await onOptimizeItem(workingItem)
                await MainActor.run {
                    if let idx = items.firstIndex(where: { $0.id == itemID }) {
                        items[idx].isOptimizing = false
                        if let opt = optimized {
                            items[idx].optimizedVariant = opt
                            items[idx].optimizationApplied = true
                            optimizedCount += 1
                        }
                        // Wenn `optimized == nil`: keine echte
                        // Verbesserung → Item bleibt auf Original
                        // (User-Spec).
                    }
                    optimizeAllProcessedCount += 1
                }
            }

            await MainActor.run {
                isOptimizingAll = false
                optimizeAllProcessedCount = 0
                let summary = BatchOptimizationSummary(
                    optimized: optimizedCount,
                    total: totalCount
                )
                lastBatchSummary = summary
                // Auto-hide Summary nach 3 s, falls kein neuer Lauf
                // dazwischenkommt.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if lastBatchSummary == summary {
                        lastBatchSummary = nil
                    }
                }
            }
        }
    }

    private func revertCurrent() {
        guard let id = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].optimizationApplied = false
    }

    // MARK: - Helpers

    private var currentIndex: Int? {
        guard let id = selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    private var currentItem: GalleryReviewItem? {
        guard let idx = currentIndex else { return nil }
        return items[idx]
    }

    private func ensureSelection() {
        if selectedItemID == nil || items.first(where: { $0.id == selectedItemID }) == nil {
            selectedItemID = items.first?.id
        }
    }
}
