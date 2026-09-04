import Foundation

#if DEBUG

/// Debug-Test-Harness für den `ArticleModeClassifier`. Das Projekt hat
/// (Stand heute) kein eigenes XCTest-Target; trotzdem ist die Logik
/// zentral genug, dass Regressionen automatisch gefangen werden müssen.
/// Lösung: eine fest eingebaute Test-Suite, die beim App-Start in DEBUG
/// einmalig durchläuft und in der Konsole reports. Fehlschläge lösen
/// in DEBUG ein `assertionFailure` aus — in Release-Builds wird die
/// gesamte Datei via `#if DEBUG` ausgeblendet, die Tests laufen dort
/// also nie und verursachen keinen Overhead.
///
/// Aufruf: `ArticleModeClassifierTests.runIfNeeded()` — triggert sich
/// selbst einmal pro App-Lifecycle (guard via static Flag). Einzige
/// Dependency: das Master-Lexikon muss geladen sein (passiert via
/// `StandardVocabularyLoader.allEntries` beim ersten Zugriff).
enum ArticleModeClassifierTests {

    private static var didRun = false

    /// Entry-Point für den App-Start. Guard stellt sicher, dass die
    /// Tests pro App-Lauf nur einmal feuern — sonst würden sie bei
    /// jedem `onAppear` des Root-Views wiederholt laufen.
    static func runIfNeeded() {
        guard !didRun else { return }
        didRun = true
        runAllTests()
    }

    static func runAllTests() {
        var passed = 0
        var failed = 0
        var failures: [String] = []

        // Kleiner inline-Asserter. `line` wird über `#line` an den
        // Call-Sites automatisch befüllt, damit Fehlschläge auf die
        // richtige Testzeile zeigen.
        func check(
            _ input: String,
            german: String = "",
            wordClass: String? = "noun",
            expectedValid: Bool,
            expectedNoyau: String? = nil,
            expectedReponse: String? = nil,
            note: String = "",
            line: UInt = #line
        ) {
            // Raw-Constructor umgeht die Normalisierung (lowercasing,
            // Artikel-Drops) aus dem Default-Init — wir wollen genau den
            // Test-String an den Classifier geben.
            let item = VocabularyItem(
                rawFrench: input,
                rawGerman: german,
                cardType: .words,
                level: nil,
                sourceLanguage: .french,
                wordClass: wordClass
            )
            let target = ArticleModeClassifier.classify(item)

            var errs: [String] = []
            if target.estValidePourExerciceArticle != expectedValid {
                errs.append("valid=\(target.estValidePourExerciceArticle) ≠ \(expectedValid)")
            }
            if let expectedNoyau, target.noyauLexical != expectedNoyau {
                errs.append("noyau='\(target.noyauLexical)' ≠ '\(expectedNoyau)'")
            }
            if let expectedReponse, target.reponseAttendueArticle != expectedReponse {
                errs.append("reponse='\(target.reponseAttendueArticle ?? "nil")' ≠ '\(expectedReponse)'")
            }

            if errs.isEmpty {
                passed += 1
            } else {
                failed += 1
                let tag = note.isEmpty ? "" : " (\(note))"
                let msg = "❌ [L\(line)] '\(input)'\(tag): " + errs.joined(separator: ", ")
                failures.append(msg)
                appDebugLog(msg)
            }
        }

        // MARK: - Spec-Testfälle (User-Brief, 10 Fälle)

        // 1. reiner Artikel „le" → aussortieren
        check("le", expectedValid: false, note: "pure article")

        // 2. reiner Artikel „la" → aussortieren
        check("la", expectedValid: false, note: "pure article")

        // 3. Artikel-Paar „le / la" → aussortieren
        check("le / la", expectedValid: false, note: "article pair")

        // 4. „mon ami" → Kern „ami", Antwort „l'"
        check("mon ami", german: "mein Freund",
              expectedValid: true, expectedNoyau: "ami", expectedReponse: "l'",
              note: "possessive + vowel")

        // 5. „mon amie" → Kern „amie", Antwort „l'"
        check("mon amie", german: "meine Freundin",
              expectedValid: true, expectedNoyau: "amie", expectedReponse: "l'",
              note: "possessive + vowel (fem)")

        // 6. „mon copain" → Kern „copain", Antwort „le"
        check("mon copain", german: "mein Freund",
              expectedValid: true, expectedNoyau: "copain", expectedReponse: "le",
              note: "possessive + masc")

        // 7. „ma copine" → Kern „copine", Antwort „la"
        check("ma copine", german: "meine Freundin",
              expectedValid: true, expectedNoyau: "copine", expectedReponse: "la",
              note: "possessive + fem")

        // 8. „la fille" → Kern „fille", Antwort „la"
        check("la fille", german: "das Mädchen",
              expectedValid: true, expectedNoyau: "fille", expectedReponse: "la",
              note: "leading article + fem")

        // 9. „homme" → Antwort „l'"
        check("homme", german: "der Mann",
              expectedValid: true, expectedReponse: "l'",
              note: "h-muet elision")

        // 10. „comment" → aussortieren (Adverb, kein Nomen)
        check("comment", german: "wie", wordClass: "adverb",
              expectedValid: false,
              note: "adverb — nicht nominalisieren")

        // MARK: - Runde 2: Gatekeeper-Lockerung (User-Nachbrief #2)
        //
        // Scenario: Liste hat 34 Nomen, Artikel-Modus zeigte nur 24.
        // Grund war ein zu strikter Noun-Check. Lockerung: Begleiter-
        // Marker + Kern-Lexikon-Lookup akzeptieren jetzt als nominal.

        // R2-1: Elision-Form ohne Leerzeichen — „l'école"
        check("l'école", german: "die Schule",
              expectedValid: true, expectedNoyau: "école", expectedReponse: "l'",
              note: "l'-elision + vowel core")

        // R2-2: Elision mit h-muet — „l'histoire"
        check("l'histoire", german: "die Geschichte",
              expectedValid: true, expectedNoyau: "histoire", expectedReponse: "l'",
              note: "l'-elision + h-muet")

        // R2-3: Elision-Form masculin — „l'homme"
        check("l'homme", german: "der Mann",
              expectedValid: true, expectedNoyau: "homme", expectedReponse: "l'",
              note: "l'-elision + masc")

        // R2-4: Elision-Form feminin — „l'amie" (mit Lexikon-Hit)
        check("l'amie", german: "die Freundin",
              expectedValid: true, expectedNoyau: "amie", expectedReponse: "l'",
              note: "l'-elision + fem")

        // R2-5: Possessivbegleiter „mon" rettet selbst ohne Lexikon-Hit
        //   (mon → masculin direkt impliziert). Test ohne wordClass-Hint.
        check("mon carnet", german: "mein Heft", wordClass: nil,
              expectedValid: true, expectedNoyau: "carnet", expectedReponse: "le",
              note: "possessive 'mon' implies masc")

        // R2-6: Possessivbegleiter „ma" → feminin
        check("ma montre", german: "meine Uhr", wordClass: nil,
              expectedValid: true, expectedNoyau: "montre", expectedReponse: "la",
              note: "possessive 'ma' implies fem")

        // R2-7: Possessivbegleiter „mon" vor Vokal → Elision-Antwort l'
        check("mon école", german: "meine Schule", wordClass: nil,
              expectedValid: true, expectedNoyau: "école", expectedReponse: "l'",
              note: "possessive + vowel → l' override")

        // R2-8: Demonstrativ „cette" → feminin
        check("cette rue", german: "diese Straße", wordClass: nil,
              expectedValid: true, expectedNoyau: "rue", expectedReponse: "la",
              note: "demonstrative 'cette' implies fem")

        // R2-9: „cet" (masc. vor Vokal) → „l'"-Antwort
        check("cet ami", german: "dieser Freund", wordClass: nil,
              expectedValid: true, expectedNoyau: "ami", expectedReponse: "l'",
              note: "demonstrative 'cet' + vowel → l'")

        // R2-10: Plural-Demonstrativ „ces"
        check("ces amis", german: "diese Freunde", wordClass: nil,
              expectedValid: true, expectedNoyau: "amis", expectedReponse: "les",
              note: "demonstrative 'ces' implies pluriel")

        // R2-11: Unbestimmter Artikel „un"
        check("un carnet", german: "ein Heft", wordClass: nil,
              expectedValid: true, expectedNoyau: "carnet", expectedReponse: "le",
              note: "indefinite 'un' implies masc")

        // R2-12: Unbestimmter Artikel „une" vor Vokal
        check("une école", german: "eine Schule", wordClass: nil,
              expectedValid: true, expectedNoyau: "école", expectedReponse: "l'",
              note: "indefinite 'une' + vowel → l'")

        // R2-13: „des" als Plural-Marker
        check("des amis", german: "Freunde", wordClass: nil,
              expectedValid: true, expectedNoyau: "amis", expectedReponse: "les",
              note: "'des' implies pluriel")

        // R2-14: Possessivbegleiter rettet auch wenn der Kern mehrwortig ist
        check("mon meilleur ami", german: "mein bester Freund", wordClass: nil,
              expectedValid: true, expectedReponse: "l'",
              note: "possessive + multi-word core (fallback: masc+vowel)")

        // R2-15: Harter Stop — Begleiter + Nicht-Noun-Kern („mon très")
        check("mon très", german: "mein sehr", wordClass: "adverb",
              expectedValid: false,
              note: "begleiter + adverb → harter Stop via isCoreLikelyNonNominal")

        // MARK: - Zusatz-Testfälle (User-Nachbrief, 9 Fälle)

        // A. „amis" → Plural-Heuristik (Sing „ami" im Lexikon) → „les"
        check("amis", german: "Freunde",
              expectedValid: true, expectedReponse: "les",
              note: "plural-heuristic from sing")

        // B. „les amis" → Kern „amis" (oder „ami", je nach Logik), „les"
        //    Unsere Extraktion liefert „amis" (ohne Lemmatisierung).
        check("les amis", german: "die Freunde",
              expectedValid: true, expectedNoyau: "amis", expectedReponse: "les",
              note: "leading 'les'")

        // C. „histoire" → Antwort „l'" (h-muet + fem)
        check("histoire", german: "die Geschichte",
              expectedValid: true, expectedReponse: "l'",
              note: "h-muet fem")

        // D. „hommes" → Plural → „les"
        check("hommes", german: "Männer",
              expectedValid: true, expectedReponse: "les",
              note: "plural of homme")

        // E. „maisons" → Plural → „les"
        check("maisons", german: "Häuser",
              expectedValid: true, expectedReponse: "les",
              note: "plural of maison")

        // F. „voiture" → Sing. fem → „la"
        check("voiture", german: "das Auto",
              expectedValid: true, expectedReponse: "la",
              note: "sing fem")

        // G. „voitures" → Plural → „les"
        check("voitures", german: "Autos",
              expectedValid: true, expectedReponse: "les",
              note: "plural of voiture")

        // H. „mon histoire" → Kern „histoire", Antwort „l'"
        check("mon histoire", german: "meine Geschichte",
              expectedValid: true, expectedNoyau: "histoire", expectedReponse: "l'",
              note: "possessive + h-muet fem")

        // I. „mes amis" → Kern „amis", Antwort „les"
        check("mes amis", german: "meine Freunde",
              expectedValid: true, expectedNoyau: "amis", expectedReponse: "les",
              note: "plural possessive")

        // MARK: - Zusätzliche Gatekeeper-Edge-Cases

        // Reine Artikel in verschiedenen Formen
        check("les", expectedValid: false, note: "pure article plural")
        check("un", expectedValid: false, note: "pure indefinite article")
        check("une", expectedValid: false, note: "pure indefinite article fem")
        check("des", expectedValid: false, note: "pure plural article")
        check("l'", expectedValid: false, note: "pure elision article")
        check("un / une", expectedValid: false, note: "article pair")
        check("le|la", expectedValid: false, note: "pipe-separated pair")

        // Non-Noun-Gatekeeper — müssen alle aussortieren
        check("bonjour", german: "hallo", wordClass: "interjection",
              expectedValid: false, note: "interjection")
        check("très", german: "sehr", wordClass: "adverb",
              expectedValid: false, note: "adverb")
        check("avec", german: "mit", wordClass: "preposition",
              expectedValid: false, note: "preposition")
        check("aimer", german: "lieben", wordClass: "verb",
              expectedValid: false, note: "verb — nicht nominalisieren")

        // Phrasen (cardType.phrases) — müssen aussortieren
        let phraseItem = VocabularyItem(
            rawFrench: "comment ça va",
            rawGerman: "wie gehts",
            cardType: .phrases,
            level: nil,
            sourceLanguage: .french,
            wordClass: nil
        )
        let phraseTarget = ArticleModeClassifier.classify(phraseItem)
        if phraseTarget.estValidePourExerciceArticle == false {
            passed += 1
        } else {
            failed += 1
            let msg = "❌ phrase-cardType not excluded"
            failures.append(msg)
            appDebugLog(msg)
        }

        // Leere/Whitespace-Eingabe → ungültig
        check("", expectedValid: false, note: "empty string")
        check("   ", expectedValid: false, note: "whitespace only")

        // MARK: - Report

        let total = passed + failed
        appDebugLog("🧪 [ArticleModeClassifier] \(passed)/\(total) Tests passed — \(failed) failed")

        if failed > 0 {
            // In DEBUG crashen wir laut: jeder Fehlschlag ist eine
            // Regression, die **nicht** still im Hintergrund laufen
            // darf. Release-Builds sehen das Harness-File nicht (per
            // `#if DEBUG`), also kein Produktions-Risiko.
            let detail = failures.joined(separator: "\n")
            assertionFailure("ArticleModeClassifier test failures:\n\(detail)")
        }
    }
}

#endif
