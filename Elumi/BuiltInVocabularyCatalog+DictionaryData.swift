import Foundation

extension BuiltInVocabularyCatalog {
    static let frenchSupplementalDictionaryItems = makeItems([
        "dauphin|delfin", "baleine|wal", "requin|hai", "tortue|schildkröte", "phoque|robbe",
        "pieuvre|krake", "grenouille|frosch", "abeille|biene", "papillon|schmetterling", "renard|fuchs",
        "loup|wolf", "ours|bär", "tigre|tiger", "lion|löwe", "girafe|giraffe",
        "zèbre|zebra", "singe|affe", "éléphant|elefant", "crocodile|krokodil", "écureuil|eichhörnchen"
    ], type: .words, level: .intermediate)

    static let englishSupplementalDictionaryItems = makeItems([
        "dolphin|delfin", "dophin|delfin", "whale|wal", "shark|hai", "turtle|schildkröte",
        "seal|robbe", "octopus|krake", "frog|frosch", "bee|biene", "butterfly|schmetterling",
        "fox|fuchs", "wolf|wolf", "bear|bär", "tiger|tiger", "lion|löwe",
        "giraffe|giraffe", "zebra|zebra", "monkey|affe", "elephant|elefant", "crocodile|krokodil",
        "squirrel|eichhörnchen", "inhabited|bewohnt", "remote|fernbedienung", "remote control|fernbedienung"
    ], type: .words, level: .intermediate, sourceLanguage: .english)

    static let englishSupplementalPhraseDictionaryItems = makeItems([
        "(to) be cut off|von etw. abgeschnitten sein",
        "to be cut off|von etw. abgeschnitten sein",
        "(to) sum sth up|etw. zusammenfassen",
        "to sum sth up|etw. zusammenfassen"
    ], type: .phrases, level: .intermediate, sourceLanguage: .english)

    static let frenchBeginnerLexiconWords = normalizedLexiconWords(from: [
        "rouge, bleu, vert, jaune, noir, blanc, gris, orange, rose, violet, marron, père, mère, frère, soeur, cousin, cousine, oncle, tante, bébé, garçon, fille, voisin, voisine, classe, élève, professeur, cahier, crayon, gomme, feuille, règle, trousse, cartable, devoir, leçon, semaine, mois, dimanche, lundi, mardi, mercredi, jeudi, vendredi, samedi, printemps, automne, pluie, neige, vent, nuage, chaud, froid, propre, sale, rapide, lent, fort, faible, facile, difficile, heureux, triste, jeune, vieux, grand, petit, long, court, tôt, tard, souvent, parfois, jamais, dauphin, baleine, requin, tortue, phoque, pieuvre, poisson, grenouille, abeille, papillon, renard, loup, ours, tigre, lion, girafe, zèbre, singe, éléphant, crocodile"
    ])

    static let frenchIntermediateLexiconWords = normalizedLexiconWords(from: [
        "quartier, immeuble, boulangerie, librairie, bibliothèque, piscine, stade, carrefour, trottoir, circulation, pharmacie, ordonnance, blessure, traitement, médicament, pansement, facture, colis, livraison, formulaire, abonnement, mot de passe, chargeur, batterie, clavier, écran, souris, imprimante, réparation, entretien, rangement, aspirateur, lessive, parapluie, écharpe, gants, randonnée, paysage, cascade, falaise, sentier, frontière, douane, itinéraire, embouteillage, navette, escale, auberge, réception, pension, annulation, bagage, assurance, conseil, habitude, effort, progrès, discussion, exemple, explication, traduction, prononciation, mémoire, attention, patience, politesse, voisinage, banlieue, campagne, réussite, examen, concours, dossier, stage, embauche, salaire, réunion, agenda, retard, avance"
    ])

    static let frenchAdvancedLexiconWords = normalizedLexiconWords(from: [
        "enjeu, nuance, résilience, cohérence, ambiguïté, démarche, épanouissement, pénurie, dilemme, lucidité, héritage, conviction, persévérance, vulnérabilité, réconciliation, anticipation, solidarité, désaccord, raisonnement, témoignage, fiabilité, légitimité, durabilité, responsabilité, complexité, diversité, égalité, injustice, prospérité, précarité, méfiance, bouleversement, éthique, morale, pouvoir, influence, stratégie, coopération, confrontation, revendication, négociation, discours, argument, hypothèse, certitude, éventualité, conséquence, contrainte, stabilité, autonomie, créativité, sensibilité, bienveillance, tolérance, arrogance, gratitude, inquiétude, soulagement, épuisement, perspicacité, exigence, discipline, rigueur, pertinence, priorité, compromis, adaptation, transformation, innovation, modernité, tradition, appartenance, identité, réputation, réputation, perspective, engagement, réticence"
    ])

    static let englishBeginnerLexiconWords = normalizedLexiconWords(from: [
        "red, blue, green, yellow, black, white, grey, orange, pink, purple, brown, father, mother, brother, sister, cousin, uncle, aunt, baby, boy, girl, neighbour, pupil, teacher, notebook, pencil, eraser, ruler, schoolbag, homework, lesson, week, month, sunday, monday, tuesday, wednesday, thursday, friday, saturday, spring, autumn, rain, snow, wind, cloud, warm, cold, clean, dirty, fast, slow, strong, weak, easy, difficult, happy, sad, young, old, tall, short, early, late, always, often, sometimes, never, breakfast, lunch, kitchen, bedroom, bathroom, garden, flower, bird, fish, horse, rabbit, mouse, beach, village, dolphin, whale, shark, turtle, seal, octopus, frog, butterfly, bee, fox, wolf, bear, tiger, lion, giraffe, zebra, monkey, elephant, crocodile"
    ])

    static let englishIntermediateLexiconWords = normalizedLexiconWords(from: [
        "district, building, bakery, bookshop, library, swimming, stadium, crossing, pavement, traffic, prescription, injury, treatment, medicine, bandage, invoice, parcel, delivery, form, subscription, password, charger, battery, keyboard, screen, printer, repair, storage, vacuum, laundry, umbrella, scarf, gloves, hiking, landscape, waterfall, cliff, path, border, customs, route, trafficjam, shuttle, stopover, hostel, reception, cancellation, luggage, insurance, advice, habit, effort, progress, discussion, example, explanation, translation, pronunciation, memory, attention, patience, politeness, suburb, countryside, success, exam, competition, file, internship, application, salary, meeting, schedule, delay, advantage, disadvantage, headline, article, report, channel, device, update, download, upload"
    ])

    static let englishAdvancedLexiconWords = normalizedLexiconWords(from: [
        "stake, nuance, resilience, coherence, ambiguity, approach, fulfilment, shortage, dilemma, insight, heritage, conviction, perseverance, vulnerability, reconciliation, anticipation, solidarity, disagreement, reasoning, testimony, reliability, legitimacy, sustainability, responsibility, complexity, diversity, equality, injustice, prosperity, insecurity, mistrust, upheaval, ethics, morality, authority, influence, strategy, cooperation, confrontation, claim, negotiation, argument, hypothesis, certainty, possibility, consequence, constraint, stability, autonomy, creativity, sensitivity, kindness, tolerance, arrogance, gratitude, concern, relief, exhaustion, perception, requirement, discipline, rigour, relevance, priority, compromise, adaptation, transformation, innovation, modernity, tradition, belonging, identity, reputation, perspective, commitment, hesitation, accountability, likelihood, significance, adjustment"
    ])

    static let germanValidationLexiconWords = normalizedLexiconWords(from: [
        "hallo, danke, bitte, ja, nein, wasser, brot, milch, kaffee, tee, apfel, banane, käse, haus, schule, buch, freund, familie, stadt, bahnhof, auto, straße, tür, fenster, sonne, mond, tag, nacht, tisch, stuhl, hund, katze, geld, arbeit, musik, rot, blau, grün, gelb, schwarz, weiß, grau, orange, rosa, lila, braun, vater, mutter, bruder, schwester, cousin, cousine, onkel, tante, baby, junge, mädchen, nachbar, nachbarin, schüler, lehrer, lehrerin, heft, bleistift, radiergummi, lineal, tasche, hausaufgabe, lektion, woche, monat, sonntag, montag, dienstag, mittwoch, donnerstag, freitag, samstag, frühling, sommer, herbst, winter, regen, schnee, wind, wolke, warm, kalt, sauber, schmutzig, schnell, langsam, stark, schwach, einfach, schwierig, glücklich, traurig, jung, alt, groß, klein, lang, kurz, früh, spät, immer, oft, manchmal, nie, frühstück, mittagessen, abendessen, küche, schlafzimmer, badezimmer, garten, blume, vogel, fisch, pferd, kaninchen, maus, strand, dorf, gebäude, bäckerei, buchhandlung, bibliothek, schwimmbad, stadion, kreuzung, gehweg, verkehr, rezept, verletzung, behandlung, medikament, verband, rechnung, paket, lieferung, formular, abonnement, passwort, ladegerät, tastatur, bildschirm, drucker, reparatur, ordnung, staubsauger, wäsche, regenschirm, schal, handschuhe, wanderung, landschaft, wasserfall, klippe, pfad, grenze, zoll, route, stau, transfer, zwischenstopp, jugendherberge, empfang, stornierung, gepäck, versicherung, rat, gewohnheit, mühe, fortschritt, diskussion, beispiel, erklärung, übersetzung, aussprache, gedächtnis, aufmerksamkeit, geduld, höflichkeit, vorort, land, erfolg, prüfung, wettbewerb, akte, praktikum, bewerbung, gehalt, besprechung, kalender, verspätung, vorteil, nachteil, überschrift, artikel, bericht, kanal, gerät, aktualisierung, download, upload, tragweite, nuance, widerstandskraft, stimmigkeit, mehrdeutigkeit, ansatz, entwicklung, knappheit, zwiespalt, klarheit, vermächtnis, überzeugung, ausdauer, verletzlichkeit, versöhnung, vorausblick, solidarität, meinungsverschiedenheit, gedankengang, zeugnis, zuverlässigkeit, legitimität, nachhaltigkeit, verantwortung, komplexität, vielfalt, gleichheit, ungerechtigkeit, wohlstand, unsicherheit, misstrauen, umbruch, ethik, moral, macht, einfluss, strategie, zusammenarbeit, konfrontation, forderung, verhandlung, argument, hypothese, gewissheit, möglichkeit, folge, einschränkung, stabilität, selbstständigkeit, kreativität, sensibilität, freundlichkeit, toleranz, arroganz, dankbarkeit, sorge, erleichterung, erschöpfung, wahrnehmung, anforderung, disziplin, strenge, relevanz, priorität, kompromiss, anpassung, veränderung, innovation, moderne, tradition, zugehörigkeit, identität, ruf, perspektive, engagement, zögern, verantwortlichkeit, wahrscheinlichkeit, bedeutung, delfin, wal, hai, schildkröte, robbe, krake, frosch, biene, schmetterling, fuchs, wolf, bär, tiger, löwe, giraffe, zebra, affe, elefant, krokodil"
    ])
}
