import Foundation

extension BuiltInVocabularyCatalog {
    static let beginnerWords = makeItems([
        "bonjour|guten tag", "merci|danke", "s il vous plaît|bitte", "oui|ja", "non|nein",
        "eau|wasser", "pain|brot", "lait|milch", "café|kaffee", "thé|tee",
        "pomme|apfel", "banane|banane", "fromage|käse", "maison|haus", "école|schule",
        "livre|buch", "ami|freund", "famille|familie", "ville|stadt", "gare|bahnhof",
        "voiture|auto", "rue|straße", "porte|tür", "fenêtre|fenster", "soleil|sonne",
        "lune|mond", "jour|tag", "nuit|nacht", "table|tisch", "chaise|stuhl",
        "chien|hund", "chat|katze", "argent|geld", "travail|arbeit", "musique|musik"
    ], type: .words, level: .beginner)

    static let beginnerPhrases = makeItems([
        "Comment ça va ?|wie geht es dir", "Je m appelle Marie.|ich heiße marie", "Où est la gare ?|wo ist der bahnhof",
        "Je voudrais un café.|ich möchte einen kaffee", "Je ne comprends pas.|ich verstehe nicht",
        "Parlez plus lentement, s il vous plaît.|sprechen sie bitte langsamer", "Où sont les toilettes ?|wo ist die toilette",
        "J ai une réservation.|ich habe eine reservierung", "Je cherche mon hôtel.|ich suche mein hotel",
        "Pouvez vous m aider ?|können sie mir helfen", "J aime la musique.|ich mag musik", "À demain matin.|bis morgen früh",
        "Bon appétit !|guten appetit", "Excusez moi.|entschuldigen sie", "Quelle heure est il ?|wie spät ist es",
        "Je suis fatigué.|ich bin müde", "J ai faim.|ich habe hunger", "J ai soif.|ich habe durst",
        "C est très bien.|das ist sehr gut", "À bientôt.|bis bald", "Bienvenue chez nous.|willkommen bei uns",
        "Où habites tu ?|wo wohnst du", "Voici mon billet.|hier ist mein ticket", "Je suis prêt.|ich bin bereit",
        "Cela va bien.|es geht gut", "Je suis en retard.|ich bin zu spät", "Je suis perdu.|ich habe mich verlaufen",
        "C est parfait.|das ist perfekt", "Ouvrez la porte, s il vous plaît.|öffnen sie bitte die tür",
        "Fermez la fenêtre, s il vous plaît.|schließen sie bitte das fenster"
    ], type: .phrases, level: .beginner)

    static let intermediateWords = makeItems([
        "marché|markt", "pharmacie|apotheke", "hôpital|krankenhaus", "aéroport|flughafen", "train|zug",
        "métro|u bahn", "billet|ticket", "valise|koffer", "plage|strand", "montagne|berg",
        "forêt|wald", "rivière|fluss", "journal|zeitung", "histoire|geschichte", "question|frage",
        "réponse|antwort", "voyage|reise", "vacances|urlaub", "bureau|büro", "ordinateur|computer",
        "téléphone|telefon", "réunion|meeting", "voisin|nachbar", "cuisine|küche", "déjeuner|mittagessen",
        "dîner|abendessen", "petit déjeuner|frühstück", "magasin|geschäft", "vitesse|geschwindigkeit", "météo|wetter",
        "printemps|frühling", "été|sommer", "automne|herbst", "hiver|winter", "problème|problem"
    ], type: .words, level: .intermediate)

    static let intermediatePhrases = makeItems([
        "Je vais au marché.|ich gehe zum markt", "Puis je payer par carte ?|kann ich mit karte bezahlen",
        "Mon téléphone ne fonctionne plus.|mein telefon funktioniert nicht mehr", "Nous partons ce soir.|wir fahren heute abend los",
        "Il pleut depuis ce matin.|es regnet seit heute morgen", "Pouvez vous répéter la question ?|können sie die frage wiederholen",
        "Je prends le train à huit heures.|ich nehme den zug um acht uhr", "Nous visitons la ville demain.|wir besuchen morgen die stadt",
        "Je travaille au bureau aujourd hui.|ich arbeite heute im büro", "Il y a trop de bruit ici.|hier ist es zu laut",
        "Combien de temps faut il ?|wie lange dauert es", "J ai oublié mon billet.|ich habe mein ticket vergessen",
        "La pharmacie est elle ouverte ?|ist die apotheke geöffnet", "Je voudrais réserver une table.|ich möchte einen tisch reservieren",
        "Cette rue est très calme.|diese straße ist sehr ruhig", "Nous avons besoin d aide.|wir brauchen hilfe",
        "Le magasin ferme à six heures.|das geschäft schließt um sechs uhr", "Je cherche une pharmacie de garde.|ich suche eine notapotheke",
        "Le musée ouvre à dix heures.|das museum öffnet um zehn uhr", "Je dois appeler ma famille.|ich muss meine familie anrufen",
        "Nous restons trois nuits.|wir bleiben drei nächte", "Il fait meilleur qu hier.|das wetter ist besser als gestern",
        "Je voudrais changer de chambre.|ich möchte das zimmer wechseln", "Où puis je acheter un billet ?|wo kann ich ein ticket kaufen",
        "Mon ordinateur est trop lent.|mein computer ist zu langsam", "Je préfère voyager en train.|ich reise lieber mit dem zug",
        "Le voisin parle très fort.|der nachbar spricht sehr laut", "Je prépare le dîner ce soir.|ich bereite heute abend das abendessen vor",
        "Nous faisons une promenade en forêt.|wir machen einen spaziergang im wald", "La météo annonce du vent demain.|der wetterbericht meldet morgen wind"
    ], type: .phrases, level: .intermediate)

    static let advancedWords = makeItems([
        "confiance|vertrauen", "réussite|erfolg", "connaissance|wissen", "décision|entscheidung", "développement|entwicklung",
        "entreprise|unternehmen", "environnement|umgebung", "habitude|gewohnheit", "expérience|erfahrung", "responsabilité|verantwortung",
        "liberté|freiheit", "avenir|zukunft", "mémoire|erinnerung", "sentiment|gefühl", "courage|mut",
        "richesse|reichtum", "pauvreté|armut", "discours|rede", "amélioration|verbesserung", "recherche|forschung",
        "résultat|ergebnis", "solution|lösung", "proposition|vorschlag", "contrat|vertrag", "entretien|gespräch",
        "candidature|bewerbung", "occasion|gelegenheit", "comportement|verhalten", "soutien|unterstützung", "défi|herausforderung",
        "qualité|qualität", "efficacité|effizienz", "précision|genauigkeit", "perspective|perspektive", "équilibre|balance",
        "enjeu|tragweite", "bouleversement|umbruch", "méfiance|misstrauen", "rayonnement|ausstrahlung", "démarche|vorgehensweise",
        "épanouissement|entfaltung", "pénurie|knappheit", "dilemme|zwiespalt", "ambiguïté|mehrdeutigkeit", "cohérence|stimmigkeit",
        "résilience|widerstandskraft", "lucidité|klarheit", "nuance|nuance", "héritage|vermächtnis", "conviction|überzeugung",
        "persévérance|ausdauer", "vulnérabilité|verletzlichkeit", "réconciliation|versöhnung", "anticipation|vorausahnung", "solidarité|solidarität",
        "désaccord|meinungsverschiedenheit", "raisonnement|gedankengang", "témoignage|zeugnis", "fiabilité|zuverlässigkeit"
    ], type: .words, level: .advanced)

    static let advancedPhrases = makeItems([
        "Malgré le retard, nous sommes restés calmes.|trotz der verspätung sind wir ruhig geblieben",
        "J aimerais améliorer ma prononciation chaque jour.|ich möchte meine aussprache jeden tag verbessern",
        "Cette décision aura des conséquences importantes.|diese entscheidung wird wichtige folgen haben",
        "Il faut trouver une solution durable.|wir müssen eine dauerhafte lösung finden",
        "Je préfère réfléchir avant de répondre.|ich denke lieber nach bevor ich antworte",
        "Nous avons discuté du projet pendant une heure.|wir haben eine stunde über das projekt gesprochen",
        "Il manque encore quelques détails essentiels.|es fehlen noch einige wichtige details",
        "Je n étais pas d accord au début.|ich war am anfang nicht einverstanden",
        "Cette expérience m a beaucoup appris.|diese erfahrung hat mir viel beigebracht",
        "Pouvez vous résumer les points principaux ?|können sie die wichtigsten punkte zusammenfassen",
        "Je me sens plus à l aise en français.|ich fühle mich auf französisch sicherer",
        "Il serait utile de pratiquer plus souvent.|es wäre sinnvoll öfter zu üben",
        "Cette proposition semble intéressante.|dieser vorschlag wirkt interessant",
        "Nous devons respecter la date limite.|wir müssen die frist einhalten",
        "Je n ai pas encore pris ma décision.|ich habe meine entscheidung noch nicht getroffen",
        "Son discours était clair et convaincant.|seine rede war klar und überzeugend",
        "J essaie de garder un bon équilibre.|ich versuche eine gute balance zu halten",
        "Il vaut mieux prévenir que guérir.|vorsicht ist besser als nachsicht",
        "Cette tâche demande beaucoup de précision.|diese aufgabe verlangt viel genauigkeit",
        "Nous avons besoin d une réponse rapide.|wir brauchen eine schnelle antwort",
        "Je voudrais approfondir ce sujet.|ich möchte dieses thema vertiefen",
        "Les résultats sont meilleurs que prévu.|die ergebnisse sind besser als erwartet",
        "Il faut tenir compte du contexte.|man muss den kontext berücksichtigen",
        "Cette habitude m aide à progresser.|diese gewohnheit hilft mir beim fortschritt",
        "Je cherche un environnement plus calme.|ich suche eine ruhigere umgebung",
        "Nous avons finalement trouvé un compromis.|wir haben am ende einen kompromiss gefunden",
        "La qualité de ce travail est remarquable.|die qualität dieser arbeit ist bemerkenswert",
        "Je manque parfois de confiance en moi.|mir fehlt manchmal das selbstvertrauen",
        "Son comportement a changé récemment.|sein verhalten hat sich kürzlich verändert",
        "Cette candidature mérite une réponse rapide.|diese bewerbung verdient eine schnelle antwort",
        "Il faut analyser la situation avec précision.|wir müssen die situation genau analysieren",
        "Ce défi demande beaucoup d énergie.|diese herausforderung braucht viel energie",
        "Le soutien de l équipe était précieux.|die unterstützung des teams war wertvoll",
        "J ai besoin de prendre un peu de recul.|ich muss etwas abstand gewinnen",
        "Cette perspective me semble plus réaliste.|diese perspektive erscheint mir realistischer"
    ], type: .phrases, level: .advanced)

    static let additionalFrenchBeginnerWords = makeItems([
        "jardin|garten", "fleur|blume", "oiseau|vogel", "poisson|fisch", "cheval|pferd",
        "lapin|kaninchen", "souris|maus", "village|dorf", "gâteau|kuchen", "jus|saft",
        "soupe|suppe", "salade|salat", "montre|uhr", "pantalon|hose", "chemise|hemd",
        "chaussure|schuh", "visage|gesicht", "cheveux|haare", "main|hand", "bras|arm",
        "jambe|bein", "ciel|himmel", "étoile|stern", "nuage|wolke", "pluie|regen",
        "neige|schnee", "vent|wind", "matin|morgen", "soir|abend", "clé|schlüssel"
    ], type: .words, level: .beginner)

    static let additionalFrenchBeginnerPhrases = makeItems([
        "J’aime lire le soir.|ich lese gern am abend", "Nous sommes dans le jardin.|wir sind im garten",
        "Le chat dort sur la chaise.|die katze schläft auf dem stuhl", "Où est ma clé ?|wo ist mein schlüssel",
        "Je cherche mes chaussures.|ich suche meine schuhe", "Il y a des étoiles ce soir.|heute abend sieht man sterne",
        "Tu veux du jus ?|möchtest du saft", "La soupe est chaude.|die suppe ist warm",
        "Le village est très calme.|das dorf ist sehr ruhig", "J’ouvre la fenêtre.|ich öffne das fenster",
        "Ferme la porte, s’il te plaît.|schließ bitte die tür", "Je vois un oiseau.|ich sehe einen vogel",
        "Le cheval est dans le champ.|das pferd ist auf dem feld", "Il neige ce matin.|es schneit heute morgen",
        "Nous mangeons une salade.|wir essen einen salat", "Ma montre est neuve.|meine uhr ist neu",
        "Pourquoi tu ris ?|warum lachst du", "Je lave mes mains.|ich wasche meine hände",
        "Le ciel est bleu.|der himmel ist blau", "Tu as froid ?|ist dir kalt"
    ], type: .phrases, level: .beginner)

    static let additionalFrenchIntermediateWords = makeItems([
        "bibliothèque|bibliothek", "boulangerie|bäckerei", "quartier|viertel", "carrefour|kreuzung", "ordonnance|rezept",
        "médicament|medikament", "facture|rechnung", "colis|paket", "abonnement|abonnement", "chargeur|ladegerät",
        "batterie|batterie", "écran|bildschirm", "clavier|tastatur", "imprimante|drucker", "randonnée|wanderung",
        "cascade|wasserfall", "falaise|klippe", "frontière|grenze", "itinéraire|route", "bagage|gepäck"
    ], type: .words, level: .intermediate)

    static let additionalFrenchIntermediatePhrases = makeItems([
        "La bibliothèque ferme à dix-huit heures.|die bibliothek schließt um achtzehn uhr",
        "Je dois acheter un médicament.|ich muss ein medikament kaufen", "Le colis arrive demain.|das paket kommt morgen an",
        "Mon chargeur est dans le bureau.|mein ladegerät ist im büro", "Cette randonnée est assez longue.|diese wanderung ist ziemlich lang",
        "Nous suivons le même itinéraire.|wir folgen derselben route", "À quelle heure ouvre la boulangerie ?|um wie viel uhr öffnet die bäckerei",
        "J’ai imprimé le document ce matin.|ich habe das dokument heute morgen ausgedruckt",
        "La batterie de mon téléphone est presque vide.|der akku von meinem telefon ist fast leer", "Je traverse le carrefour.|ich überquere die kreuzung",
        "La frontière est encore loin.|die grenze ist noch weit entfernt", "Nous avons reçu la facture par e-mail.|wir haben die rechnung per e mail erhalten",
        "Peux-tu vérifier l’adresse ?|kannst du die adresse überprüfen", "Le quartier change rapidement.|das viertel verändert sich schnell",
        "Je prépare mon bagage.|ich packe mein gepäck", "La cascade est magnifique.|der wasserfall ist wunderschön",
        "Il faut suivre les indications.|man muss den hinweisen folgen", "Cette falaise est impressionnante.|diese klippe ist beeindruckend",
        "J’attends une livraison importante.|ich warte auf eine wichtige lieferung", "Nous avons pris un abonnement mensuel.|wir haben ein monatliches abonnement abgeschlossen"
    ], type: .phrases, level: .intermediate)

    static let additionalFrenchAdvancedWords = makeItems([
        "analyse|analyse", "adaptation|anpassung", "autonomie|selbstständigkeit", "bienveillance|freundlichkeit", "certitude|gewissheit",
        "contrainte|einschränkung", "créativité|kreativität", "diversité|vielfalt", "durabilité|nachhaltigkeit", "égalité|gleichheit",
        "éthique|ethik", "éventualité|möglichkeit", "exigence|anforderung", "gratitude|dankbarkeit", "hypothèse|hypothese",
        "injustice|ungerechtigkeit", "innovation|innovation", "légitimité|legitimität", "modernité|moderne", "négociation|verhandlung",
        "perspicacité|scharfsinn", "polémique|kontroverse", "priorité|priorität", "prospérité|wohlstand", "précarité|unsicherheit",
        "réputation|ruf", "revendication|forderung", "rigueur|strenge", "sensibilité|sensibilität", "solidité|stabilität",
        "soulagement|erleichterung", "tolérance|toleranz", "transformation|veränderung", "valeur|wert", "vigilance|wachsamkeit"
    ], type: .words, level: .advanced)
}
