import Foundation

/// Curated list of beginner-friendly words shown to new users before the normal frequency-based flow.
/// To extend: just append more word IDs to the array. Previously-learned words are automatically skipped.
struct StarterWords {
    static let wordIds: [String] = [
        // Greetings & Polite
        "en_es_5081",  // hola (hello)
        "en_es_2712",  // adiós (goodbye)
        "en_es_2231",  // por favor (please)
        "en_es_5323",  // gracias (thanks)
        "en_es_1042",  // lo siento (sorry)

        // Essentials
        "en_es_0078",  // sí (yes)
        "en_es_0043",  // no (no/not)
        "en_es_0046",  // mucho (much)
        "en_es_0091",  // también (also/too)
        "en_es_0106",  // ahora (now)

        // Core Nouns
        "en_es_0283",  // nombre (name)
        "en_es_0200",  // persona (person)
        "en_es_0151",  // casa (house)
        "en_es_0234",  // agua (water)
        "en_es_0268",  // amigo (friend)

        // Core Verbs
        "en_es_0188",  // tener (to have)
        "en_es_0154",  // querer (to want)
        "en_es_0173",  // hablar (to speak)
        "en_es_0448",  // comer (to eat)
        "en_es_0264",  // necesitar (to need)

        // Adjectives & Descriptions
        "en_es_0011",  // bueno (good)
        "en_es_0345",  // malo (bad)
        "en_es_0049",  // grande (big)
        "en_es_0276",  // pequeño (small)
        "en_es_1190",  // feliz (happy)

        // Question Words & Time
        "en_es_0079",  // qué (what)
        "en_es_0158",  // donde (where)
        "en_es_0139",  // cómo (how)
        "en_es_0178",  // hoy (today)
        "en_es_0060",  // día (day)
    ]
}
