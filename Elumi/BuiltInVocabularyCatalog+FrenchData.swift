import Foundation

extension BuiltInVocabularyCatalog {
    static let beginnerWords = makeItems([
        "bonjour|Guten tag", "merci|danke", "s il vous plaît|bitte", "oui|ja", "non|nein",
        "eau|Wasser", "pain|Brot", "lait|Milch", "café|Kaffee", "thé|Tee",
        "pomme|Apfel", "banane|Banane", "fromage|Käse", "maison|Haus", "école|Schule",
        "livre|Buch", "ami|Freund", "famille|Familie", "ville|Stadt", "gare|Bahnhof",
        "voiture|Auto", "rue|Straße", "porte|Tür", "fenêtre|Fenster", "soleil|Sonne",
        "lune|Mond", "jour|Tag", "nuit|Nacht", "table|Tisch", "chaise|Stuhl",
        "chien|Hund", "chat|Katze", "argent|Geld", "travail|Geburtsarbeit", "musique|Musik"
    ], type: .words, level: .beginner)

    static let beginnerPhrases = makeItems([
        "Comment ça va ?|Wie geht es dir", "Je m appelle Marie.|Ich heiße marie", "Où est la gare ?|Wo ist der bahnhof",
        "Je voudrais un café.|Ich möchte einen kaffee", "Je ne comprends pas.|Ich verstehe nicht",
        "Parlez plus lentement, s il vous plaît.|Sprechen sie bitte langsamer", "Où sont les toilettes ?|Wo ist die toilette",
        "J ai une réservation.|Ich habe eine reservierung", "Je cherche mon hôtel.|Ich suche mein hotel",
        "Pouvez vous m aider ?|Können sie mir helfen", "J aime la musique.|Ich mag musik", "À demain matin.|Bis morgen früh",
        "Bon appétit !|Guten appetit", "Excusez moi.|Entschuldigen sie", "Quelle heure est il ?|Wie spät ist es",
        "Je suis fatigué.|Ich bin müde", "J ai faim.|Ich habe hunger", "J ai soif.|Ich habe durst",
        "C est très bien.|Das ist sehr gut", "À bientôt.|Bis bald", "Bienvenue chez nous.|Willkommen bei uns",
        "Où habites tu ?|Wo wohnst du", "Voici mon billet.|Hier ist mein ticket", "Je suis prêt.|Ich bin bereit",
        "Cela va bien.|Es geht gut", "Je suis en retard.|Ich bin zu spät", "Je suis perdu.|Ich habe mich verlaufen",
        "C est parfait.|Das ist perfekt", "Ouvrez la porte, s il vous plaît.|Öffnen sie bitte die tür",
        "Fermez la fenêtre, s il vous plaît.|Schließen sie bitte das fenster"
    ], type: .phrases, level: .beginner)

    static let intermediateWords = makeItems([
        "marché|Markt", "pharmacie|Apotheke", "hôpital|Krankenhaus", "aéroport|Flughafen", "train|Zug",
        "métro|U bahn", "billet|Fahrkarte", "valise|Koffer", "plage|Strand", "montagne|Berg",
        "forêt|Wald", "rivière|Fluss", "journal|Zeitung", "histoire|Geschichte", "question|Frage",
        "réponse|Antwort", "voyage|Reise", "vacances|Ferien", "bureau|Schreibtisch", "ordinateur|Computer",
        "téléphone|Telefon", "réunion|Meeting", "voisin|Nachbar", "cuisine|Küche", "déjeuner|Mittagessen",
        "dîner|Abendessen", "petit déjeuner|Frühstück", "magasin|Geschäft", "vitesse|Geschwindigkeit", "météo|Wetterbericht",
        "printemps|Frühling", "été|Sommer", "automne|Herbst", "hiver|Winter", "problème|Problem"
    ], type: .words, level: .intermediate)

    static let intermediatePhrases = makeItems([
        "Je vais au marché.|Ich gehe zum markt", "Puis je payer par carte ?|Kann ich mit karte bezahlen",
        "Mon téléphone ne fonctionne plus.|Mein telefon funktioniert nicht mehr", "Nous partons ce soir.|Wir fahren heute abend los",
        "Il pleut depuis ce matin.|Es regnet seit heute morgen", "Pouvez vous répéter la question ?|Können sie die frage wiederholen",
        "Je prends le train à huit heures.|Ich nehme den zug um acht uhr", "Nous visitons la ville demain.|Wir besuchen morgen die stadt",
        "Je travaille au bureau aujourd hui.|Ich arbeite heute im büro", "Il y a trop de bruit ici.|Hier ist es zu laut",
        "Combien de temps faut il ?|Wie lange dauert es", "J ai oublié mon billet.|Ich habe mein ticket vergessen",
        "La pharmacie est elle ouverte ?|Ist die apotheke geöffnet", "Je voudrais réserver une table.|Ich möchte einen tisch reservieren",
        "Cette rue est très calme.|Diese straße ist sehr ruhig", "Nous avons besoin d aide.|Wir brauchen hilfe",
        "Le magasin ferme à six heures.|Das geschäft schließt um sechs uhr", "Je cherche une pharmacie de garde.|Ich suche eine notapotheke",
        "Le musée ouvre à dix heures.|Das museum öffnet um zehn uhr", "Je dois appeler ma famille.|Ich muss meine familie anrufen",
        "Nous restons trois nuits.|Wir bleiben drei nächte", "Il fait meilleur qu hier.|Das wetter ist besser als gestern",
        "Je voudrais changer de chambre.|Ich möchte das zimmer wechseln", "Où puis je acheter un billet ?|Wo kann ich ein ticket kaufen",
        "Mon ordinateur est trop lent.|Mein computer ist zu langsam", "Je préfère voyager en train.|Ich reise lieber mit dem zug",
        "Le voisin parle très fort.|Der nachbar spricht sehr laut", "Je prépare le dîner ce soir.|Ich bereite heute abend das abendessen vor",
        "Nous faisons une promenade en forêt.|Wir machen einen spaziergang im wald", "La météo annonce du vent demain.|Der wetterbericht meldet morgen wind"
    ], type: .phrases, level: .intermediate)

    static let advancedWords = makeItems([
        "confiance|Vertrauen", "réussite|Erfolg", "connaissance|Kenntnis", "décision|Entscheidung", "développement|Entwicklung",
        "entreprise|Unternehmen", "environnement|Umwelt", "habitude|Gewohnheit", "expérience|Erfahrung", "responsabilité|Verantwortung",
        "liberté|Freiheit", "avenir|Zukunft", "mémoire|Gedächtnis", "sentiment|Gefühl", "courage|Mut",
        "richesse|Reichtum", "pauvreté|Armut", "discours|Rede", "amélioration|Verbesserung", "recherche|Recherche",
        "résultat|Ergebnis", "solution|Lösung", "proposition|Vorschlag", "contrat|Vertrag", "entretien|Gespräch",
        "candidature|Bewerbung", "occasion|Gelegenheit", "comportement|Verhalten", "soutien|Stütze", "défi|Herausforderung",
        "qualité|Qualität", "efficacité|Wirksamkeit", "précision|Genauigkeit", "perspective|Perspektive", "équilibre|Gleichgewicht",
        "enjeu|Herausforderung", "bouleversement|Umwälzung", "méfiance|Misstrauen", "rayonnement|Strahlung", "démarche|Vorgehen",
        "épanouissement|Aufblühen", "pénurie|Mangel", "dilemme|Dilemma", "ambiguïté|Ambiguität", "cohérence|Kohärenz",
        "résilience|Schlagfestigkeit", "lucidité|Klarblick", "nuance|Nuance", "héritage|Erbe", "conviction|Überzeugung",
        "persévérance|Ausdauer", "vulnérabilité|Verletzlichkeit", "réconciliation|Versöhnung", "anticipation|Vorwegnahme", "solidarité|Solidarität",
        "désaccord|Meinungsverschiedenheit", "raisonnement|Argumentation", "témoignage|Zeugnis", "fiabilité|Zuverlässigkeit"
    ], type: .words, level: .advanced)

    static let advancedPhrases = makeItems([
        "Malgré le retard, nous sommes restés calmes.|Trotz der verspätung sind wir ruhig geblieben",
        "J aimerais améliorer ma prononciation chaque jour.|Ich möchte meine aussprache jeden tag verbessern",
        "Cette décision aura des conséquences importantes.|Diese entscheidung wird wichtige folgen haben",
        "Il faut trouver une solution durable.|Wir müssen eine dauerhafte lösung finden",
        "Je préfère réfléchir avant de répondre.|Ich denke lieber nach bevor ich antworte",
        "Nous avons discuté du projet pendant une heure.|Wir haben eine stunde über das projekt gesprochen",
        "Il manque encore quelques détails essentiels.|Es fehlen noch einige wichtige details",
        "Je n étais pas d accord au début.|Ich war am anfang nicht einverstanden",
        "Cette expérience m a beaucoup appris.|Diese erfahrung hat mir viel beigebracht",
        "Pouvez vous résumer les points principaux ?|Können sie die wichtigsten punkte zusammenfassen",
        "Je me sens plus à l aise en français.|Ich fühle mich auf französisch sicherer",
        "Il serait utile de pratiquer plus souvent.|Es wäre sinnvoll öfter zu üben",
        "Cette proposition semble intéressante.|Dieser vorschlag wirkt interessant",
        "Nous devons respecter la date limite.|Wir müssen die frist einhalten",
        "Je n ai pas encore pris ma décision.|Ich habe meine entscheidung noch nicht getroffen",
        "Son discours était clair et convaincant.|Seine rede war klar und überzeugend",
        "J essaie de garder un bon équilibre.|Ich versuche eine gute balance zu halten",
        "Il vaut mieux prévenir que guérir.|Vorsicht ist besser als nachsicht",
        "Cette tâche demande beaucoup de précision.|Diese aufgabe verlangt viel genauigkeit",
        "Nous avons besoin d une réponse rapide.|Wir brauchen eine schnelle antwort",
        "Je voudrais approfondir ce sujet.|Ich möchte dieses thema vertiefen",
        "Les résultats sont meilleurs que prévu.|Die ergebnisse sind besser als erwartet",
        "Il faut tenir compte du contexte.|Man muss den kontext berücksichtigen",
        "Cette habitude m aide à progresser.|Diese gewohnheit hilft mir beim fortschritt",
        "Je cherche un environnement plus calme.|Ich suche eine ruhigere umgebung",
        "Nous avons finalement trouvé un compromis.|Wir haben am ende einen kompromiss gefunden",
        "La qualité de ce travail est remarquable.|Die qualität dieser arbeit ist bemerkenswert",
        "Je manque parfois de confiance en moi.|Mir fehlt manchmal das selbstvertrauen",
        "Son comportement a changé récemment.|Sein verhalten hat sich kürzlich verändert",
        "Cette candidature mérite une réponse rapide.|Diese bewerbung verdient eine schnelle antwort",
        "Il faut analyser la situation avec précision.|Wir müssen die situation genau analysieren",
        "Ce défi demande beaucoup d énergie.|Diese herausforderung braucht viel energie",
        "Le soutien de l équipe était précieux.|Die unterstützung des teams war wertvoll",
        "J ai besoin de prendre un peu de recul.|Ich muss etwas abstand gewinnen",
        "Cette perspective me semble plus réaliste.|Diese perspektive erscheint mir realistischer"
    ], type: .phrases, level: .advanced)

    static let additionalFrenchBeginnerWords = makeItems([
        "jardin|Garten", "fleur|Blume", "oiseau|Vogel", "poisson|Fisch", "cheval|Pferd",
        "lapin|Kaninchen", "souris|Maus", "village|Dorf", "gâteau|Kuchen", "jus|Saft",
        "soupe|Suppe", "salade|Salat", "montre|Uhr", "pantalon|Hose", "chemise|Hemd",
        "chaussure|Schuh", "visage|Gesicht", "cheveux|Haare", "main|Hand", "bras|Arm",
        "jambe|Bein", "ciel|Himmel", "étoile|Sternform", "nuage|Wolke", "pluie|Regen",
        "neige|Schnee", "vent|Wind", "matin|Morgen", "soir|Abend", "clé|Schlüssel"
    ], type: .words, level: .beginner)

    static let additionalFrenchBeginnerPhrases = makeItems([
        "J’aime lire le soir.|Ich lese gern am abend", "Nous sommes dans le jardin.|Wir sind im garten",
        "Le chat dort sur la chaise.|Die katze schläft auf dem stuhl", "Où est ma clé ?|Wo ist mein schlüssel",
        "Je cherche mes chaussures.|Ich suche meine schuhe", "Il y a des étoiles ce soir.|Heute abend sieht man sterne",
        "Tu veux du jus ?|Möchtest du saft", "La soupe est chaude.|Die suppe ist warm",
        "Le village est très calme.|Das dorf ist sehr ruhig", "J’ouvre la fenêtre.|Ich öffne das fenster",
        "Ferme la porte, s’il te plaît.|Schließ bitte die tür", "Je vois un oiseau.|Ich sehe einen vogel",
        "Le cheval est dans le champ.|Das pferd ist auf dem feld", "Il neige ce matin.|Es schneit heute morgen",
        "Nous mangeons une salade.|Wir essen einen salat", "Ma montre est neuve.|Meine uhr ist neu",
        "Pourquoi tu ris ?|Warum lachst du", "Je lave mes mains.|Ich wasche meine hände",
        "Le ciel est bleu.|Der himmel ist blau", "Tu as froid ?|Ist dir kalt"
    ], type: .phrases, level: .beginner)

    static let additionalFrenchIntermediateWords = makeItems([
        "bibliothèque|Bibliothek", "boulangerie|Bäckerei", "quartier|Viertel", "carrefour|Kreuzung", "ordonnance|Rezept",
        "médicament|Medikament", "facture|Rechnung", "colis|Paket", "abonnement|Abo", "chargeur|Ladegerät",
        "batterie|Akku", "écran|Bildschirm", "clavier|Tastatur", "imprimante|Drucker", "randonnée|Wanderung",
        "cascade|Wasserfall", "falaise|Klippe", "frontière|Grenze", "itinéraire|Route", "bagage|Gepäck"
    ], type: .words, level: .intermediate)

    static let additionalFrenchIntermediatePhrases = makeItems([
        "La bibliothèque ferme à dix-huit heures.|Die bibliothek schließt um achtzehn uhr",
        "Je dois acheter un médicament.|Ich muss ein medikament kaufen", "Le colis arrive demain.|Das paket kommt morgen an",
        "Mon chargeur est dans le bureau.|Mein ladegerät ist im büro", "Cette randonnée est assez longue.|Diese wanderung ist ziemlich lang",
        "Nous suivons le même itinéraire.|Wir folgen derselben route", "À quelle heure ouvre la boulangerie ?|Um wie viel uhr öffnet die bäckerei",
        "J’ai imprimé le document ce matin.|Ich habe das dokument heute morgen ausgedruckt",
        "La batterie de mon téléphone est presque vide.|Der akku von meinem telefon ist fast leer", "Je traverse le carrefour.|Ich überquere die kreuzung",
        "La frontière est encore loin.|Die grenze ist noch weit entfernt", "Nous avons reçu la facture par e-mail.|Wir haben die rechnung per e mail erhalten",
        "Peux-tu vérifier l’adresse ?|Kannst du die adresse überprüfen", "Le quartier change rapidement.|Das viertel verändert sich schnell",
        "Je prépare mon bagage.|Ich packe mein gepäck", "La cascade est magnifique.|Der wasserfall ist wunderschön",
        "Il faut suivre les indications.|Man muss den hinweisen folgen", "Cette falaise est impressionnante.|Diese klippe ist beeindruckend",
        "J’attends une livraison importante.|Ich warte auf eine wichtige lieferung", "Nous avons pris un abonnement mensuel.|Wir haben ein monatliches abonnement abgeschlossen"
    ], type: .phrases, level: .intermediate)

    static let additionalFrenchAdvancedWords = makeItems([
        "analyse|Analyse", "adaptation|Anpassung", "autonomie|Selbstständigkeit", "bienveillance|Wohlwollen", "certitude|Gewissheit",
        "contrainte|Einschränkung", "créativité|Kreativität", "diversité|Vielfalt", "durabilité|Nachhaltigkeit", "égalité|Gleichheit",
        "éthique|Ethik", "éventualité|Möglichkeit", "exigence|Anforderung", "gratitude|Dankbarkeit", "hypothèse|Hypothese",
        "injustice|Ungerechtigkeit", "innovation|Innovation", "légitimité|Berechtigung", "modernité|Modernität", "négociation|Verhandlung",
        "perspicacité|Scharfsinn", "polémique|Polemik", "priorité|Priorität", "prospérité|Wohlstand", "précarité|Prekarität",
        "réputation|Ruf", "revendication|Forderung", "rigueur|Genauigkeit", "sensibilité|Sensibilität", "solidité|Festigkeit",
        "soulagement|Erleichterung", "tolérance|Toleranz", "transformation|Bearbeitung", "valeur|Wert", "vigilance|Wachsamkeit"
    ], type: .words, level: .advanced)
}
