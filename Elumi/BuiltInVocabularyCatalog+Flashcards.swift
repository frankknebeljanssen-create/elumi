import Foundation

extension BuiltInVocabularyCatalog {
    static let flashcardsOne = makeFlashcardDeckCards(idPrefix: "fc1", pairs: [
        "bonjour|guten tag", "merci|danke", "s il vous plaît|bitte", "au revoir|auf wiedersehen", "eau|wasser",
        "pain|brot", "fromage|käse", "gare|bahnhof", "voiture|auto", "hôtel|hotel",
        "famille|familie", "ami|freund", "jour|tag", "nuit|nacht", "soleil|sonne",
        "lune|mond", "école|schule", "travail|arbeit", "argent|geld", "musique|musik",
        "maison|haus", "livre|buch", "ville|stadt", "rue|straße", "porte|tür",
        "fenêtre|fenster", "chien|hund", "chat|katze", "café|kaffee", "thé|tee",
        "Comment ça va ?|wie geht es dir", "Je m appelle Marie.|ich heiße marie", "Où est la gare ?|wo ist der bahnhof",
        "Je voudrais un café.|ich möchte einen kaffee", "Combien ça coûte ?|wie viel kostet das", "Je ne comprends pas.|ich verstehe nicht",
        "Parlez plus lentement, s il vous plaît.|sprechen sie bitte langsamer", "Où sont les toilettes ?|wo ist die toilette",
        "J ai une réservation.|ich habe eine reservierung", "Je cherche mon hôtel.|ich suche mein hotel",
        "Pouvez vous m aider ?|können sie mir helfen", "Je suis allemand.|ich bin deutscher", "J aime la musique.|ich mag musik",
        "Nous partons demain.|wir fahren morgen los", "Il fait très chaud aujourd hui.|heute ist es sehr heiß",
        "Je prends le métro.|ich nehme die u bahn", "Nous avons faim.|wir haben hunger", "La table est prête.|der tisch ist fertig",
        "Je voudrais payer.|ich möchte bezahlen", "À demain matin.|bis morgen früh"
    ], sourceLanguage: .french)

    static let flashcardsEnglishOne = makeFlashcardDeckCards(idPrefix: "fcen1", pairs: [
        "hello|hallo", "thank you|danke", "please|bitte", "goodbye|auf wiedersehen", "water|wasser",
        "bread|brot", "cheese|käse", "station|bahnhof", "car|auto", "hotel|hotel",
        "family|familie", "friend|freund", "day|tag", "night|nacht", "sun|sonne",
        "moon|mond", "school|schule", "work|arbeit", "money|geld", "music|musik",
        "house|haus", "book|buch", "city|stadt", "street|straße", "door|tür",
        "window|fenster", "dog|hund", "cat|katze", "coffee|kaffee", "tea|tee",
        "How are you?|wie geht es dir", "My name is Tom.|ich heiße tom", "Where is the station?|wo ist der bahnhof",
        "I would like a coffee.|ich möchte einen kaffee", "How much is it?|wie viel kostet das", "I do not understand.|ich verstehe nicht",
        "Please speak more slowly.|bitte sprich langsamer", "Where are the toilets?|wo ist die toilette", "I have a reservation.|ich habe eine reservierung",
        "I am looking for my hotel.|ich suche mein hotel", "Can you help me?|kannst du mir helfen", "I am from Germany.|ich komme aus deutschland",
        "I like music.|ich mag musik", "We are leaving tomorrow.|wir fahren morgen los", "It is very hot today.|heute ist es sehr heiß",
        "I am taking the underground.|ich nehme die u bahn", "We are hungry.|wir haben hunger", "The table is ready.|der tisch ist fertig",
        "I would like to pay.|ich möchte bezahlen", "See you tomorrow morning.|bis morgen früh"
    ], sourceLanguage: .english)

    static let flashcardDecks: [FlashcardDeck] = [
        FlashcardDeck(
            id: "flashcards-1",
            name: "Karteikarten 1",
            sourceLanguage: .french,
            cards: flashcardsOne
        ),
        FlashcardDeck(
            id: "flashcards-en-1",
            name: "English Basics",
            sourceLanguage: .english,
            cards: flashcardsEnglishOne
        )
    ]
}
