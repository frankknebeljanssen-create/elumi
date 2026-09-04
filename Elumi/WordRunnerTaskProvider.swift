import Foundation

/// **Phase-3-Layer**: zentrale Stelle, die `RunnerTask`s erzeugt.
///
/// Bewusst ein Protokoll, kein konkreter Typ. Phase-3 shippt einen
/// eingebauten Seed-Provider mit kuratierten Artikel- und
/// Verbform-Aufgaben (deterministisch, fachlich geprüft). Später
/// können wir einen `LiveListRunnerTaskProvider` anhängen, der aus
/// `VocabularyListStore` + `LexiconGenderInfo` live Aufgaben baut —
/// das Protokoll bleibt gleich, die View muss nicht mitwissen, woher
/// die Aufgabe kommt.
///
/// Invariante: `nextTask()` liefert entweder eine **well-formed**
/// `RunnerTask` (3 Optionen, genau 1 korrekt, nicht leer) oder `nil`.
/// Der Runner fragt bei `nil` fair nach einer Gap-Welle zurück — es
/// erscheint also nie eine kaputte Aufgabe im Spielfeld.
protocol RunnerTaskProvider: AnyObject {
    func nextTask() -> RunnerTask?
}

// MARK: - Seed-Provider

/// Kuratierter Seed-Set: feste Artikel- und Verbform-Aufgaben. Immer
/// well-formed, immer lieferbar. Nutzt einen **mischenden Pool** —
/// jede Aufgabe kommt genau einmal vor, bevor das Pool-Reshuffle
/// einsetzt. Dadurch sieht der Spieler nicht 3 Mal dieselbe Frage
/// hintereinander, auch ohne großen Content-Pool.
///
/// **Distraktor-Qualität**: die Distraktoren sind plausibel —
/// Artikel aus der gleichen Familie (`le/la/les`) für Nomen,
/// Konjugationen aus derselben Verbfamilie für Verben. Keine
/// Zufalls-Nonsense-Optionen.
///
/// Für Phase 3 reicht das seedbasierte Set (~13 Aufgaben). Wenn das
/// zu kurz wird, kommt der Live-Pfad oben drauf.
final class SeedRunnerTaskProvider: RunnerTaskProvider {

    private var pool: [RunnerTask] = []

    init() {
        reshuffle()
    }

    func nextTask() -> RunnerTask? {
        if pool.isEmpty {
            reshuffle()
        }
        let task = pool.removeLast()
        // Guard-Rail: sollte nie nötig sein, weil alle Seed-Tasks
        // handgeprüft sind — aber billiger als ein Runtime-Crash
        // bei späteren Erweiterungen.
        guard task.isWellFormed else {
            return pool.isEmpty ? nil : nextTask()
        }
        return task
    }

    private func reshuffle() {
        pool = (Self.articleSeed + Self.reverseArticleSeed + Self.verbFormSeed).shuffled()
    }

    // MARK: - Artikel-Seed
    //
    // Kuratiert: Alltagswörter + nicht-triviales Genus (kein „le père"
    // o. ä., wo der Artikel aus dem Prompt trivialerweise erratbar
    // wäre). Drei Optionen immer `[le, la, les]` — Distraktoren
    // stammen aus der gleichen Artikel-Familie (Phase-3-Anforderung).

    private static let articleSeed: [RunnerTask] = [
        .init(category: .article, prompt: "chat",     options: ["le", "la", "les"], correctIndex: 0),
        .init(category: .article, prompt: "maison",   options: ["le", "la", "les"], correctIndex: 1),
        .init(category: .article, prompt: "enfants",  options: ["le", "la", "les"], correctIndex: 2),
        .init(category: .article, prompt: "livre",    options: ["le", "la", "les"], correctIndex: 0),
        .init(category: .article, prompt: "table",    options: ["le", "la", "les"], correctIndex: 1),
        .init(category: .article, prompt: "fleurs",   options: ["le", "la", "les"], correctIndex: 2),
        .init(category: .article, prompt: "soleil",   options: ["le", "la", "les"], correctIndex: 0),
        .init(category: .article, prompt: "nuit",     options: ["le", "la", "les"], correctIndex: 1),
        .init(category: .article, prompt: "voitures", options: ["le", "la", "les"], correctIndex: 2),
    ]

    // MARK: - Reverse-Article-Seed (Entscheidungsformat-Variante)
    //
    // **Reverse-Auswahl** (Spec 1): statt „Nomen → Artikel" hier
    // „Artikel → Nomen". Der Spieler sieht den Artikel als Prompt
    // und muss aus drei Nomen das passende auswählen — dasselbe
    // Lernziel (Genus), aber andere Frage-Richtung. Nach 9 normalen
    // Artikel-Tasks gibt's 6 Reverse-Tasks im Mix → bleibt der Pool
    // im 60/40-Verhältnis Standard:Reverse.
    //
    // Distraktoren stammen jeweils aus den **anderen** Genera, sodass
    // genau eine Antwort fachlich passt. Prompt-Format: „Artikel + ___"
    // analog zu Verbformen, damit das Layout konsistent bleibt.

    private static let reverseArticleSeed: [RunnerTask] = [
        // le → masculin
        .init(category: .article, prompt: "le ___",
              options: ["chat", "maison", "fleurs"], correctIndex: 0),
        .init(category: .article, prompt: "le ___",
              options: ["soleil", "nuit", "voitures"], correctIndex: 0),

        // la → féminin
        .init(category: .article, prompt: "la ___",
              options: ["livre", "table", "enfants"], correctIndex: 1),
        .init(category: .article, prompt: "la ___",
              options: ["chat", "nuit", "voitures"], correctIndex: 1),

        // les → pluriel
        .init(category: .article, prompt: "les ___",
              options: ["livre", "fleurs", "soleil"], correctIndex: 1),
        .init(category: .article, prompt: "les ___",
              options: ["maison", "table", "voitures"], correctIndex: 2),
    ]

    // MARK: - Verbform-Seed
    //
    // Kuratiert: drei Hochfrequenz-Verben (être, avoir, aller) in je
    // zwei Personen. Distraktoren = andere Formen **derselben** Verb-
    // familie (sein/haben/gehen), niemals Quer-Familien — so bleibt
    // die Entscheidung fachlich sauber statt „raten gegen Noise".
    //
    // **Prompt-Format** (Phase-3-Fix):
    //   „je ___ [aller]" — der Infinitiv steht in **eckigen Klammern**
    //   am Ende, damit er klar vom Satz getrennt bleibt. Ohne Klammern
    //   liest sich „je ___ aller" wie Satzfortsetzung und verwirrt
    //   (vor allem bei längeren Sätzen später). Die Klammer-Form ist
    //   sprachdidaktisch etabliert als „Lemma in Brackets".

    private static let verbFormSeed: [RunnerTask] = [
        // aller
        .init(category: .verbForm, prompt: "je ___ [aller]",
              options: ["vais", "va", "vont"], correctIndex: 0),
        .init(category: .verbForm, prompt: "tu ___ [aller]",
              options: ["vas", "va", "vont"], correctIndex: 0),

        // être
        .init(category: .verbForm, prompt: "il ___ [être]",
              options: ["es", "est", "sont"], correctIndex: 1),
        .init(category: .verbForm, prompt: "vous ___ [être]",
              options: ["êtes", "est", "sommes"], correctIndex: 0),

        // avoir
        .init(category: .verbForm, prompt: "nous ___ [avoir]",
              options: ["avons", "avez", "ont"], correctIndex: 0),
        .init(category: .verbForm, prompt: "elles ___ [avoir]",
              options: ["a", "avez", "ont"], correctIndex: 2),
    ]
}

// MARK: - Placeholder Provider (Phase-2-Fallback)

/// Wenn gar kein Content-Provider wirken soll (z. B. reiner
/// Gameplay-Test ohne Phase-3-Inhalte), liefert dieser Provider
/// schlicht `nil` — der Spawner fällt dann auf Gap-Wellen
/// (reiner Dodge) + neutrale Platzhalter-Choice-Wellen zurück.
///
/// Nützlich für Unit-Tests der Gameplay-Schicht, die **ohne** echte
/// Aufgaben Kollisionen/State validieren wollen.
final class NullRunnerTaskProvider: RunnerTaskProvider {
    func nextTask() -> RunnerTask? { nil }
}
