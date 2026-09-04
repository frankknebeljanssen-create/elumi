import SwiftUI

// ElumiHelp.swift
// **Elumi-Hilfe (2026-08-05)** — kontextbezogene Hilfe, die Elumi gibt,
// wenn der Nutzer sie anfordert. Datenmodell + Textkatalog + Presenter.
//
// **Warum überhaupt** (User-Idee): "Wir haben ja oben das Elumi-Icon im
// Mainscreen. Vielleicht sollte man das machen, wenn man das antippt,
// dann kommt Elumi." Bisher gab es nur die `InfoView` — ein statischer
// Katalog aller Module auf einem Screen, ohne Bezug dazu, wo der Nutzer
// gerade steht und woran er gerade hängt.
//
// **Die drei Regeln, nach denen das gebaut ist** (Recherche 2026-08-05):
//
//   1. **Nur auf Anfrage, niemals von selbst.** Elumi taucht nicht auf,
//      weil ein Timer abgelaufen ist, weil jemand lange nichts getippt
//      hat oder weil eine Antwort falsch war. Razzaq & Heffernan (ITS
//      2010) haben für Lernsysteme direkt verglichen: angeforderte
//      Hinweise bringen mehr Lernertrag als von selbst erscheinende.
//      Und es ist der Punkt, an dem Clippy, Navi und Fi gescheitert
//      sind — nicht am Charakter, sondern daran, dass sie ungefragt
//      dazwischenredeten.
//
//   2. **Kein Defizit-Framing.** Nirgends steht "Brauchst du Hilfe?"
//      oder "Probleme?". Ryan/Hicks/Midgley (1997) und Ryan & Pintrich
//      zeigen, dass Jugendliche Hilfesuchen als Bedrohung ihres
//      Selbstbilds erleben, am stärksten die mit geringer
//      Selbstwirksamkeit — also genau die, die es am nötigsten hätten.
//      Deshalb ist der Einstieg eine Neugier-Frage ("Was willst du
//      wissen?") und die Einträge sind konkrete Fragen, die sich der
//      Nutzer selbst stellt, keine Themen-Etiketten. Nebeneffekt: eine
//      konkrete Frage hat auch den besseren "Information Scent" (NN/g)
//      als das Wort "Hilfe".
//
//   3. **Eine Antwort, kurz.** NN/g-Teenager-Report: Ziel-Leseniveau
//      6. Klasse, dichter Text ist ein Abbruch-Auslöser. Keine Hinweis-
//      Ketten, keine Tour. Jede Antwort hier sind zwei bis drei Sätze.
//
// **Ton der Texte:** nie strafend. "Falsch ist normal", "dein
// Fortschritt bleibt", "kann nie sinken". Das ist dieselbe Haltung wie
// beim Gewinn-Framing der Ziel-Karte (siehe `HomeGoalCard`) und der
// Grund, warum Finch (4,9 Sterne bei ~712.000 Bewertungen) bei jungen
// Nutzern funktioniert, wo Verlust-Mechaniken abschrecken.

/// Ein Frage-Antwort-Paar. Optional mit einer Aktion, die die Sache
/// direkt tut, statt sie nur zu beschreiben — Carrolls Minimalismus-
/// Prinzip: Hilfe soll die Aufgabe durchtragen, nicht ersetzen.
struct ElumiHelpEntry: Identifiable {
    let id = UUID()
    /// So, wie der Nutzer sie sich selbst stellen würde. Erste Person,
    /// keine Themen-Überschrift ("Wofür ist die Flamme?", nicht "Streak").
    let question: String
    /// Zwei bis drei kurze Sätze. Keine Fachbegriffe.
    let answer: String
    var actionTitle: String? = nil
    var actionScreen: AppScreen? = nil
}

/// Der Kontext, aus dem die Hilfe gerufen wurde. Bewusst ein eigenes
/// Enum statt `AppScreen`: `AppScreen` trägt Launch-Contexts als
/// assoziierte Werte (`.quiz(QuizLaunchContext?)`) und taugt damit nicht
/// als stabiler Katalog-Schlüssel. Außerdem entspricht ein Hilfe-Thema
/// nicht immer genau einem Screen.
enum ElumiHelpTopic: String, Identifiable, CaseIterable {
    case home
    case quiz
    case training
    case lists
    case progress
    case flashcards
    case scan
    case lexicon
    case accents
    case dailyDrop
    case games
    case goal
    case settings

    var id: String { rawValue }

    var entries: [ElumiHelpEntry] {
        switch self {
        case .home:       return Self.homeEntries
        case .quiz:       return Self.quizEntries
        case .training:   return Self.trainingEntries
        case .lists:      return Self.listsEntries
        case .progress:   return Self.progressEntries
        case .flashcards: return Self.flashcardsEntries
        case .scan:       return Self.scanEntries
        case .lexicon:    return Self.lexiconEntries
        case .accents:    return Self.accentsEntries
        case .dailyDrop:  return Self.dailyDropEntries
        case .games:      return Self.gamesEntries
        case .goal:       return Self.goalEntries
        case .settings:   return Self.settingsEntries
        }
    }

    // MARK: - Home

    private static let homeEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Womit fang ich an?",
            answer: """
            Tipp einfach auf Training oder Quiz, dann geht es direkt los.
            Wenn du noch keine eigenen Vokabeln drin hast, scann dir eine Seite aus deinem Buch ein.
            """,
            actionTitle: "Vokabeln scannen",
            actionScreen: .scan
        ),
        ElumiHelpEntry(
            question: "Was bedeutet mein Ziel?",
            answer: """
            Dein Ziel sagt, wie oft du pro Woche üben willst.
            Der Balken füllt sich mit jedem Tag, an dem du geübt hast.
            Ändern kannst du es jederzeit, das kostet dich keinen Fortschritt.
            """,
            actionTitle: "Ziel ansehen",
            actionScreen: .learningGoal
        ),
        ElumiHelpEntry(
            question: "Wofür ist die Flamme?",
            answer: """
            Die Flamme zählt, an wie vielen Tagen hintereinander du geübt hast.
            Wenn du mal einen Tag auslässt, fängt sie wieder bei eins an.
            Dein Lernstand bleibt davon völlig unberührt.
            """
        ),
        ElumiHelpEntry(
            question: "Was ist der Daily Drop?",
            answer: """
            Einmal am Tag darfst du am Rad drehen.
            Das Rad würfelt aus, was du übst, und es dauert nur ein paar Minuten.
            Dafür gibt es Würmchen.
            """
        )
    ]

    // MARK: - Quiz

    private static let quizEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Wie läuft das Quiz?",
            answer: """
            Du bekommst gemischte Fragen: mal ankreuzen, mal selbst tippen, mal Paare verbinden.
            Vorher wählst du die Lernliste und wie viele Fragen es sein sollen.
            """
        ),
        ElumiHelpEntry(
            question: "Was sind Würmchen und XP?",
            answer: """
            XP sammelst du fürs Üben, damit steigt dein Level.
            Würmchen sind Elumis Futter, damit schaltest du Spiele frei.
            """
        ),
        ElumiHelpEntry(
            question: "Woher kommen die Fragen?",
            answer: """
            Immer aus der Lernliste, die oben ausgewählt ist.
            Willst du etwas anderes üben, tipp auf die Liste und wähl eine andere aus.
            """
        ),
        ElumiHelpEntry(
            question: "Ich hab was falsch, und jetzt?",
            answer: """
            Falsch ist völlig normal, davon geht nichts kaputt.
            Wörter, die noch wackeln, kommen automatisch öfter dran, bis sie sitzen.
            """
        )
    ]

    // MARK: - Training

    private static let trainingEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was ist der Unterschied zum Quiz?",
            answer: """
            Beim Training übst du gezielt eine Sache: nur Nomen, nur Verben, nur Artikel.
            Das Quiz mischt dagegen alles durcheinander.
            """
        ),
        ElumiHelpEntry(
            question: "Welchen Modus nehm ich?",
            answer: """
            Wenn du unsicher bist, nimm Vokabeln. Das geht quer durch deine Liste.
            Die anderen vier sind für den Feinschliff, wenn dir eine Sache besonders schwerfällt.
            """
        ),
        ElumiHelpEntry(
            question: "Was sind Verbformen?",
            answer: """
            Da übst du, wie sich ein Verb verändert, je nachdem wer etwas macht.
            Also je parle, tu parles, il parle und so weiter.
            """
        ),
        ElumiHelpEntry(
            question: "Was bringen mir Akzente?",
            answer: """
            Im Französischen ändert ein Akzent die Aussprache und manchmal sogar die Bedeutung.
            Hier übst du, wo genau er hingehört.
            """
        )
    ]

    // MARK: - Lernlisten

    private static let listsEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was ist eine Lernliste?",
            answer: """
            Eine Lernliste ist dein eigener Stapel Vokabeln.
            Alles, was du scannst oder selbst eingibst, landet in so einer Liste.
            Beim Üben suchst du dir aus, mit welcher du arbeiten willst.
            """
        ),
        ElumiHelpEntry(
            question: "Was sind Wackelkandidaten?",
            answer: """
            Das sind die Wörter, die noch nicht sicher sitzen.
            Elumi sammelt sie automatisch für dich, du musst nichts dafür tun.
            Sobald ein Wort sitzt, fällt es von allein wieder raus.
            """,
            actionTitle: "Lernstand ansehen",
            actionScreen: .lernstatus
        ),
        ElumiHelpEntry(
            question: "Wie kommen neue Vokabeln rein?",
            answer: """
            Fotografier eine Seite aus deinem Vokabelheft oder Buch.
            Elumi liest sie aus und macht eine Lernliste daraus.
            """,
            actionTitle: "Jetzt scannen",
            actionScreen: .scan
        ),
        ElumiHelpEntry(
            question: "Welche Liste wird gerade geübt?",
            answer: """
            Die mit dem Haken.
            In welcher Kategorie sie steckt, siehst du schon außen an der Kategorie-Karte.
            """
        )
    ]

    // MARK: - Fortschritt

    private static let progressEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was heißt sitzt und wackelt?",
            answer: """
            Sitzt heißt: du hattest das Wort mehrmals hintereinander richtig.
            Wackelt heißt: noch nicht sicher genug.
            Elumi merkt sich das für jedes Wort einzeln, quer durch alle Übungen.
            """,
            actionTitle: "Lernstand ansehen",
            actionScreen: .lernstatus
        ),
        ElumiHelpEntry(
            question: "Wie krieg ich Spiele frei?",
            answer: """
            Mit Würmchen, die du beim Üben sammelst.
            Im Spielen-Bereich tauschst du sie dann gegen Spielrunden ein.
            """
        ),
        ElumiHelpEntry(
            question: "Was bringt mir mein Level?",
            answer: """
            Das Level zeigt, wie viel du insgesamt schon geübt hast.
            Es kann nie sinken, egal wie eine einzelne Runde läuft.
            """
        ),
        ElumiHelpEntry(
            question: "Wofür ist die Serie?",
            answer: """
            Die Serie zählt deine Übungstage hintereinander.
            Sie ist ein netter Bonus, mehr nicht.
            Wie gut du die Wörter kannst, hängt nicht an ihr.
            """
        )
    ]

    // MARK: - Karteikarten

    private static let flashcardsEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Wie funktionieren Karteikarten?",
            answer: """
            Vorne steht das Wort, hinten die Übersetzung.
            Du überlegst erst selbst und drehst die Karte dann um.
            Danach sagst du ehrlich, ob du es wusstest.
            """
        ),
        ElumiHelpEntry(
            question: "Warum soll ich erst raten?",
            answer: """
            Weil genau das Nachdenken das Lernen ausmacht.
            Wenn du sofort umdrehst, kommt dir alles bekannt vor, sitzt aber nicht.
            Lass dir also ruhig ein paar Sekunden Zeit.
            """
        ),
        ElumiHelpEntry(
            question: "Was bringt der Vorlesen-Knopf?",
            answer: """
            Er spricht dir das französische Wort vor.
            Sehr praktisch, weil Französisch selten so klingt, wie es geschrieben wird.
            """
        ),
        ElumiHelpEntry(
            question: "Kann ich auch sprechen statt tippen?",
            answer: """
            Ja, mit dem Mikrofon sagst du das Wort einfach laut.
            Elumi hört zu und prüft, ob es gepasst hat.
            """
        )
    ]

    // MARK: - Scannen

    private static let scanEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was kann ich hier scannen?",
            answer: """
            Eine Seite aus deinem Vokabelheft oder deinem Schulbuch.
            Am besten eine, auf der Französisch und Deutsch nebeneinander stehen.
            """
        ),
        ElumiHelpEntry(
            question: "Wie fotografier ich richtig?",
            answer: """
            Leg das Heft flach hin und sorg für gutes Licht.
            Halte das Handy gerade darüber, sodass die Seite den Bildschirm gut ausfüllt.
            Schief oder dunkel macht es Elumi schwer.
            """
        ),
        ElumiHelpEntry(
            question: "Da ist ein Fehler drin, was tun?",
            answer: """
            Du siehst vor dem Speichern alle erkannten Wörter und kannst jedes ändern.
            Was nicht passt, wirfst du einfach raus.
            Nichts landet ungeprüft in deiner Liste.
            """
        ),
        ElumiHelpEntry(
            question: "Wo landen die Wörter danach?",
            answer: """
            In einer neuen Lernliste, der du selbst einen Namen gibst.
            Danach kannst du sofort damit üben.
            """,
            actionTitle: "Meine Listen ansehen",
            actionScreen: .lists(nil)
        )
    ]

    // MARK: - Wörterbuch

    private static let lexiconEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was steht im Wörterbuch?",
            answer: """
            Alle Wörter, die Elumi kennt, nicht nur deine eigenen.
            Du kannst nach einem Wort suchen und nachschlagen, was es heißt.
            """
        ),
        ElumiHelpEntry(
            question: "Kann ich von hier aus üben?",
            answer: """
            Nicht direkt. Das Wörterbuch ist zum Nachschlagen da.
            Zum Üben nimmst du eine Lernliste.
            """
        ),
        ElumiHelpEntry(
            question: "Wieso steht da le oder la davor?",
            answer: """
            Das ist der Artikel, also ob das Wort männlich oder weiblich ist.
            Im Französischen gehört er fest zum Wort dazu, deshalb lernst du ihn am besten gleich mit.
            """
        )
    ]

    // MARK: - Akzente

    private static let accentsEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was übe ich hier genau?",
            answer: """
            Die kleinen Striche und Häkchen über den Buchstaben: é, è, ê und ç.
            Du entscheidest, welcher davon in ein Wort gehört.
            """
        ),
        ElumiHelpEntry(
            question: "Warum ist das wichtig?",
            answer: """
            Ein Akzent verändert die Aussprache und manchmal die ganze Bedeutung.
            In einer Klassenarbeit zählt ein fehlender Akzent oft als Fehler.
            """
        ),
        ElumiHelpEntry(
            question: "Wie merke ich mir das?",
            answer: """
            Am besten über den Klang: é klingt geschlossen, è offener.
            Je öfter du es hörst und siehst, desto sicherer wird das Gefühl dafür.
            """
        )
    ]

    // MARK: - Daily Drop

    private static let dailyDropEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was ist der Daily Drop?",
            answer: """
            Einmal am Tag drehst du am Rad, und es würfelt dir deine Übung aus.
            Du musst also nicht selbst entscheiden, was dran ist.
            """
        ),
        ElumiHelpEntry(
            question: "Was kommt beim Drehen raus?",
            answer: """
            Mal eine Übung, mal ein Spiel, oft eine Mischung.
            Genau das macht den Reiz aus, du weißt es vorher nicht.
            """
        ),
        ElumiHelpEntry(
            question: "Was, wenn ich einen Tag verpasse?",
            answer: """
            Dann passiert einfach nichts.
            Am nächsten Tag ist das Rad wieder da, und dein Fortschritt bleibt wie er war.
            """
        )
    ]

    // MARK: - Spielen

    private static let gamesEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Wie schalte ich Spiele frei?",
            answer: """
            Mit Würmchen, die du beim Üben sammelst.
            Hier tauschst du sie gegen Spielrunden ein.
            """
        ),
        ElumiHelpEntry(
            question: "Lern ich beim Spielen was?",
            answer: """
            Ja, in den Spielen kommen deine Vokabeln vor.
            Es ist eher Wiederholung als neues Lernen, aber es bleibt trotzdem hängen.
            """
        ),
        ElumiHelpEntry(
            question: "Was kostet mich eine Runde?",
            answer: """
            Ein paar Würmchen, je nach Spiel unterschiedlich viele.
            Verlierst du eine Runde, kostet dich das keinen Lernfortschritt.
            """
        )
    ]

    // MARK: - Ziel

    private static let goalEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was macht mein Ziel genau?",
            answer: """
            Es legt fest, wie oft du pro Woche üben willst.
            Danach richtet sich, was Elumi dir vorschlägt.
            """
        ),
        ElumiHelpEntry(
            question: "Kann ich es ändern?",
            answer: """
            Jederzeit, und es kostet dich keinen Fortschritt.
            Deine schon geübten Tage dieser Woche bleiben stehen.
            """
        ),
        ElumiHelpEntry(
            question: "Was passiert, wenn ich es nicht schaffe?",
            answer: """
            Gar nichts. Es gibt keine Strafe und nichts geht verloren.
            Nächste Woche fängt der Zähler einfach neu an.
            """
        ),
        ElumiHelpEntry(
            question: "Warum eine Woche und nicht ein Tag?",
            answer: """
            Weil ein einzelner verpasster Tag sonst gleich alles kaputtmacht.
            Über eine Woche kannst du einen Tag ausfallen lassen und trotzdem dein Ziel erreichen.
            """
        )
    ]

    // MARK: - Einstellungen

    private static let settingsEntries: [ElumiHelpEntry] = [
        ElumiHelpEntry(
            question: "Was ist die Lernrichtung?",
            answer: """
            Sie legt fest, ob du vom Französischen ins Deutsche übst oder umgekehrt.
            Von Deutsch nach Französisch ist schwerer, dafür lernst du das Schreiben mit.
            """
        ),
        ElumiHelpEntry(
            question: "Kann ich Elumi stummschalten?",
            answer: """
            Ja, unter Sound schaltest du die Geräusche aus.
            Die Stimme fürs Vorlesen bleibt davon unberührt.
            """
        ),
        ElumiHelpEntry(
            question: "Was ist die globale Listen-Auswahl?",
            answer: """
            Wenn sie an ist, gilt deine gewählte Lernliste überall gleich.
            Schaltest du sie aus, merkt sich jede Übung ihre eigene Liste.
            """
        )
    ]
}

/// Steuert, ob und für welchen Kontext die Hilfe gerade offen ist.
///
/// **Warum ein Singleton statt State pro Screen:** Der Auslöser sitzt in
/// der `AppTopBar` (bzw. am Maskottchen im `HomeHeader`), die Sheet
/// selbst liegt einmal zentral in `RootContentView`. Ein Screen ruft nur
/// `ElumiHelpPresenter.shared.show(.quiz)` und braucht dafür weder
/// eigenen State noch eine Sheet-Deklaration. Gleiches Muster wie
/// `HintStore.shared` und `LearningGoalStore.shared`.
@MainActor
final class ElumiHelpPresenter: ObservableObject {
    static let shared = ElumiHelpPresenter()

    @Published var activeTopic: ElumiHelpTopic?

    private init() {}

    func show(_ topic: ElumiHelpTopic) {
        activeTopic = topic
    }

    func dismiss() {
        activeTopic = nil
    }
}
