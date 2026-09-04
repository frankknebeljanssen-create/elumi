import Foundation

extension ScanAnalysisEngine {
    func analyze(_ request: ScanRequest) async -> ScanProviderResult {
        await analyze(request, progressHandler: nil)
    }

    func analyze(
        _ request: ScanRequest,
        progressHandler: ProgressHandler?
    ) async -> ScanProviderResult {
        if shouldRunPrimaryFirstWithPreflightFallback(for: request) {
            return await analyzePrimaryFirstWithPreflightFallback(
                request,
                progressHandler: progressHandler
            )
        }

        if shouldRunPrimaryAndPreflightConcurrently(for: request) {
            return await analyzeConcurrentPrimaryAndPreflight(
                request,
                progressHandler: progressHandler
            )
        }

        let totalStart = CFAbsoluteTimeGetCurrent()
        if preflightProvider != nil {
            await progressHandler?(.ocrPreflight)
        }
        let preflightStart = CFAbsoluteTimeGetCurrent()
        let preflightResult = await preflightProvider?.analyze(request: request, context: nil)
        if preflightProvider != nil {
            logTiming("engine_preflight", start: preflightStart)
        }

        if let preflightResult, shouldUsePreflightAsFinalResult(preflightResult) {
            logTiming("engine_total", start: totalStart)
            return preflightResult
        }

        if let preflightResult, !shouldConsultPrimaryProvider(after: preflightResult) {
            logTiming("engine_total", start: totalStart)
            return preflightResult
        }

        let primaryContext = preflightResult.map { ScanProviderContext(primaryResult: $0) }
        await progressHandler?(.aiConnecting)
        let primaryStart = CFAbsoluteTimeGetCurrent()
        await progressHandler?(.aiPrimary)
        let primaryResult = await primaryProvider.analyze(request: request, context: primaryContext)
        logTiming("engine_primary", start: primaryStart)
        // Nach dem Request: Antwort ist zurück, die App entpackt die
        // Daten. Eigene Stage, damit der User sieht, dass wir aus der
        // „KI analysiert"-Phase raus sind und jetzt die Antwort lesen.
        await progressHandler?(.aiReceiving)

        if shouldAbortAfterPrimaryFailure(primaryResult) {
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        if let preflightResult {
            var bestResult = shouldPrefer(primaryResult, over: preflightResult) ? primaryResult : preflightResult

            if shouldConsultFallbackProviders(for: bestResult), !fallbackProviders.isEmpty {
                let context = ScanProviderContext(primaryResult: primaryResult)
                for provider in fallbackProviders {
                    await progressHandler?(.ocrFallback)
                    let fallbackResult = await provider.analyze(request: request, context: context)
                    if shouldPrefer(fallbackResult, over: bestResult) {
                        bestResult = fallbackResult
                    }
                }
            }

            let merged = mergedResult(bestResult, primaryResult: primaryResult)
            logTiming("engine_total", start: totalStart)
            return merged
        }

        guard shouldConsultFallbackProviders(for: primaryResult), !fallbackProviders.isEmpty else {
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        var bestResult = primaryResult
        let context = ScanProviderContext(primaryResult: primaryResult)
        for provider in fallbackProviders {
            await progressHandler?(.ocrFallback)
            let fallbackResult = await provider.analyze(request: request, context: context)
            if shouldPrefer(fallbackResult, over: bestResult) {
                bestResult = fallbackResult
            }
        }

        let merged = mergedResult(bestResult, primaryResult: primaryResult)
        logTiming("engine_total", start: totalStart)
        return merged
    }

    func analyzePrimaryFirstWithPreflightFallback(
        _ request: ScanRequest,
        progressHandler: ProgressHandler?
    ) async -> ScanProviderResult {
        let totalStart = CFAbsoluteTimeGetCurrent()

        await progressHandler?(.aiPrimary)
        let primaryStart = CFAbsoluteTimeGetCurrent()
        let primaryResult = await primaryProvider.analyze(request: request, context: nil)
        logTiming("engine_primary", start: primaryStart)
        await progressHandler?(.aiReceiving)

        if shouldAbortAfterPrimaryFailure(primaryResult) {
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        guard shouldConsultPreflightAfterPrimary(primaryResult, for: request),
              let preflightProvider else {
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        await progressHandler?(.ocrPreflight)
        let preflightStart = CFAbsoluteTimeGetCurrent()
        let preflightResult = await preflightProvider.analyze(
            request: request,
            context: ScanProviderContext(primaryResult: primaryResult)
        )
        logTiming("engine_preflight", start: preflightStart)

        let bestResult = shouldPrefer(preflightResult, over: primaryResult) ? preflightResult : primaryResult
        let merged = mergedResult(bestResult, primaryResult: primaryResult)
        logTiming("engine_total", start: totalStart)
        return merged
    }

    func analyzeConcurrentPrimaryAndPreflight(
        _ request: ScanRequest,
        progressHandler: ProgressHandler?
    ) async -> ScanProviderResult {
        let totalStart = CFAbsoluteTimeGetCurrent()

        if preflightProvider != nil {
            await progressHandler?(.ocrPreflight)
        }
        await progressHandler?(.aiPrimary)

        let sharedStart = CFAbsoluteTimeGetCurrent()
        async let preflightTask: ScanProviderResult? = preflightProvider?.analyze(request: request, context: nil)
        async let primaryTask: ScanProviderResult = primaryProvider.analyze(request: request, context: nil)

        let primaryResult = await primaryTask
        logTiming("engine_primary", start: sharedStart)
        await progressHandler?(.aiReceiving)

        if shouldAbortAfterPrimaryFailure(primaryResult) {
            _ = await preflightTask
            if preflightProvider != nil {
                logTiming("engine_preflight", start: sharedStart)
            }
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        let preflightResult = await preflightTask
        if preflightProvider != nil {
            logTiming("engine_preflight", start: sharedStart)
        }

        if let preflightResult {
            var bestResult = shouldPrefer(primaryResult, over: preflightResult) ? primaryResult : preflightResult

            if shouldConsultFallbackProviders(for: bestResult), !fallbackProviders.isEmpty {
                let context = ScanProviderContext(primaryResult: primaryResult)
                for provider in fallbackProviders {
                    await progressHandler?(.ocrFallback)
                    let fallbackResult = await provider.analyze(request: request, context: context)
                    if shouldPrefer(fallbackResult, over: bestResult) {
                        bestResult = fallbackResult
                    }
                }
            }

            let merged = mergedResult(bestResult, primaryResult: primaryResult)
            logTiming("engine_total", start: totalStart)
            return merged
        }

        guard shouldConsultFallbackProviders(for: primaryResult), !fallbackProviders.isEmpty else {
            logTiming("engine_total", start: totalStart)
            return primaryResult
        }

        var bestResult = primaryResult
        let context = ScanProviderContext(primaryResult: primaryResult)
        for provider in fallbackProviders {
            await progressHandler?(.ocrFallback)
            let fallbackResult = await provider.analyze(request: request, context: context)
            if shouldPrefer(fallbackResult, over: bestResult) {
                bestResult = fallbackResult
            }
        }

        let merged = mergedResult(bestResult, primaryResult: primaryResult)
        logTiming("engine_total", start: totalStart)
        return merged
    }

    func logTiming(_ label: String, start: CFAbsoluteTime) {
        #if DEBUG
        let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
        NSLog("[ScanTiming] %@: %dms", label, elapsedMS)
        #endif
    }
}
