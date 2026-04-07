import Foundation

let frenchArticleHints: Set<String> = [
    "le", "la", "les", "un", "une", "des", "du", "de la", "de l", "au", "aux", "l"
]

let germanArticleHints: Set<String> = [
    "der", "die", "das", "ein", "eine", "einer", "einem", "einen", "den", "dem", "des", "kein", "keine"
]

let germanNounTriggerWords: Set<String> = germanArticleHints.union([
    "dieser", "diese", "dieses", "diesem", "diesen",
    "jeder", "jede", "jedes", "jedem", "jeden",
    "mein", "meine", "meinem", "meinen",
    "dein", "deine", "deinem", "deinen",
    "sein", "seine", "seinem", "seinen",
    "ihr", "ihre", "ihrem", "ihren",
    "unser", "unsere", "unserem", "unseren",
    "euer", "eure", "eurem", "euren"
])

let germanHabenForms: Set<String> = [
    "habe", "hast", "hat", "haben", "habt"
]

let germanLexiconLowercaseExceptions: Set<String> = [
    "bitte", "danke", "hallo", "ja", "nein", "heute", "morgen",
    "gestern", "bald", "oft", "nie", "gern", "sehr", "mehr",
    "weniger", "schon", "noch", "hier", "dort", "zusammen",
    "langsam", "schnell", "warm", "kalt", "sauber", "schmutzig"
]

let strongFrenchFeminineSuffixes = [
    "tion", "sion", "té", "té", "ette", "ance", "ence", "ie",
    "ure", "esse", "euse", "ence", "aison", "eille", "ille"
]

let strongFrenchMasculineSuffixes = [
    "age", "isme", "ment", "eau", "phone", "scope", "oir", "ier", "port", "teur"
]

let strongGermanFeminineSuffixes = [
    "ung", "heit", "keit", "schaft", "tion", "tät", "ik", "ur", "ei", "enz", "anz"
]

let strongGermanMasculineSuffixes = [
    "ling", "ismus", "ist", "ant", "ent", "eur", "or"
]

let strongGermanNeuterSuffixes = [
    "chen", "lein", "ment", "um", "ma"
]

let lexiconFrenchPhraseStarterWords: Set<String> = [
    "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
    "me", "m", "te", "t", "se", "s", "ne", "n", "ce", "c", "ca", "ça",
    "au", "aux", "a", "à", "de", "d", "du", "des", "chez", "pour",
    "sans", "avec", "sur", "sous", "vers", "dans", "par"
]

let lexiconGermanPhraseStarterWords: Set<String> = [
    "ich", "du", "er", "sie", "es", "wir", "ihr", "man", "mich", "dich",
    "mir", "dir", "uns", "euch", "nicht", "bitte", "am", "im", "an",
    "auf", "unter", "bei", "mit", "ohne", "fur", "für", "zu", "aus",
    "vor", "nach", "vom", "zum", "zur"
]

let frenchNounGenderHeadOverrides: [String: LexiconNounGender] = [
    "aeroport": .masculine,
    "port": .masculine,
    "hotel": .masculine,
    "musee": .masculine,
    "bureau": .masculine,
    "ordinateur": .masculine,
    "telephone": .masculine,
    "fromage": .masculine,
    "billet": .masculine,
    "train": .masculine,
    "livre": .masculine,
    "probleme": .masculine,
    "contrat": .masculine,
    "sentiment": .masculine,
    "resultat": .masculine,
    "bagage": .masculine,
    "voyage": .masculine,
    "marché": .masculine,
    "marche": .masculine,
    "ville": .feminine,
    "gare": .feminine,
    "route": .feminine,
    "question": .feminine,
    "reponse": .feminine,
    "famille": .feminine,
    "voiture": .feminine,
    "valise": .feminine,
    "fenetre": .feminine,
    "porte": .feminine,
    "phrase": .feminine,
    "histoire": .feminine,
    "musique": .feminine
]

let germanNounGenderHeadOverrides: [String: LexiconNounGender] = [
    "flughafen": .masculine,
    "bahnhof": .masculine,
    "hafen": .masculine,
    "markt": .masculine,
    "bericht": .masculine,
    "urlaub": .masculine,
    "computer": .masculine,
    "koffer": .masculine,
    "vertrag": .masculine,
    "fortschritt": .masculine,
    "kompromiss": .masculine,
    "mut": .masculine,
    "erfolg": .masculine,
    "fluss": .masculine,
    "wald": .masculine,
    "berg": .masculine,
    "bildschirm": .masculine,
    "toast": .masculine,
    "hunger": .masculine,
    "durst": .masculine,
    "haus": .neuter,
    "buch": .neuter,
    "wort": .neuter,
    "telefon": .neuter,
    "ticket": .neuter,
    "passwort": .neuter,
    "gepack": .neuter,
    "gepäck": .neuter,
    "wetter": .neuter,
    "brot": .neuter,
    "wasser": .neuter,
    "geld": .neuter,
    "museum": .neuter,
    "thema": .neuter,
    "problem": .neuter,
    "team": .neuter,
    "zimmer": .neuter,
    "set": .neuter,
    "fruhstuck": .neuter,
    "frühstück": .neuter,
    "abendessen": .neuter,
    "mittagessen": .neuter,
    "toastbrot": .neuter,
    "schule": .feminine,
    "familie": .feminine,
    "straße": .feminine,
    "strasse": .feminine,
    "frage": .feminine,
    "antwort": .feminine,
    "geschichte": .feminine,
    "musik": .feminine,
    "reise": .feminine,
    "tur": .feminine,
    "tür": .feminine,
    "fensterbank": .feminine,
    "kuche": .feminine,
    "küche": .feminine
]

let lexiconPlaceNameConnectorWords: Set<String> = [
    "a", "à", "am", "an", "au", "aux",
    "by", "bei",
    "d", "de", "del", "des", "du",
    "en", "et",
    "im",
    "la", "le", "les",
    "of",
    "sur",
    "und",
    "von"
]
