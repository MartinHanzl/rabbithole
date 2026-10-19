import Foundation

/// Mapping of app topics to Czech Wikipedia categories.
///
/// This is the single place to edit when tuning content:
/// - `categories` are category names on cs.wikipedia.org **without** the `Kategorie:` prefix.
/// - Subcategories are crawled automatically up to `AppConfig.categoryCrawlDepth`.
/// - `id` is persisted (selection, weights) – don't rename existing ids.
/// - `group` decides the section in onboarding and settings.
/// - Personal-development topics have thinner Wikipedia coverage; YouTube channels in
///   `VideoChannelCatalog` help most there.
enum TopicCatalog {
    static let all: [Topic] = [
        Topic(
            id: "space",
            name: "Vesmír",
            symbol: "sparkles",
            categories: ["Vesmír", "Astronomie", "Kosmologie", "Planety", "Kosmonautika"]
        ),
        Topic(
            id: "history",
            name: "Historie",
            symbol: "building.columns",
            categories: ["Historie", "Starověk", "Středověk"]
        ),
        Topic(
            id: "biology",
            name: "Biologie",
            symbol: "leaf",
            categories: ["Biologie", "Živočichové", "Rostliny", "Zoologie", "Evoluce", "Genetika"]
        ),
        Topic(
            id: "technology",
            name: "Technika",
            symbol: "gearshape.2",
            categories: ["Technika", "Stroje", "Informatika"]
        ),
        Topic(
            id: "art",
            name: "Umění",
            symbol: "paintpalette",
            categories: ["Umění", "Výtvarné umění", "Malířství", "Architektura"]
        ),
        Topic(
            id: "geography",
            name: "Geografie",
            symbol: "globe.europe.africa",
            categories: ["Geografie", "Hory a kopce", "Řeky", "Ostrovy"]
        ),
        Topic(
            id: "psychology",
            name: "Psychologie",
            symbol: "brain.head.profile",
            categories: ["Psychologie", "Kognitivní zkreslení"]
        ),
        Topic(
            id: "philosophy",
            name: "Filozofie",
            symbol: "books.vertical",
            categories: ["Filozofie", "Etika", "Filozofové"]
        ),
        Topic(
            id: "music",
            name: "Hudba",
            symbol: "music.note",
            categories: ["Hudba", "Hudební nástroje", "Hudební žánry"]
        ),
        Topic(
            id: "sport",
            name: "Sport",
            symbol: "figure.run",
            categories: ["Sport", "Olympijské hry"]
        ),
        Topic(
            id: "language",
            name: "Jazyk",
            symbol: "character.book.closed",
            categories: ["Lingvistika", "Jazyky", "Etymologie"]
        ),
        Topic(
            id: "curiosities",
            name: "Zajímavosti",
            symbol: "lightbulb",
            categories: ["Rekordy", "Záhady", "Paradoxy", "Optické klamy", "Městské legendy"]
        ),

        // MARK: Osobní rozvoj a vztahy
        Topic(
            id: "accounting", name: "Účetnictví", symbol: "banknote",
            categories: ["Účetnictví", "Daně"], group: .personal
        ),
        Topic(
            id: "emotional-stability", name: "Emoční stabilita", symbol: "heart.text.square",
            categories: ["Emoce", "Duševní zdraví", "Psychoterapie"], group: .personal
        ),
        Topic(
            id: "relational-intelligence", name: "Vztahová inteligence", symbol: "person.2.wave.2",
            categories: ["Sociální psychologie", "Vztahy"], group: .personal
        ),
        Topic(
            id: "relationships", name: "Navazování a udržování vztahů", symbol: "person.2",
            categories: ["Vztahy", "Přátelství", "Láska", "Manželství"], group: .personal
        ),
        Topic(
            id: "family", name: "Vztahy s rodinou", symbol: "figure.2.and.child.holdinghands",
            categories: ["Rodina", "Příbuzenství"], group: .personal
        ),
        Topic(
            id: "sales", name: "Prodej", symbol: "cart",
            categories: ["Prodej", "Marketing", "Obchod"], group: .personal
        ),
        Topic(
            id: "negotiation", name: "Vyjednávání", symbol: "arrow.left.arrow.right",
            categories: ["Diplomacie", "Teorie her"], group: .personal
        ),
        Topic(
            id: "leadership", name: "Leadership", symbol: "flag",
            categories: ["Management", "Personalistika", "Podnikání"], group: .personal
        ),
        Topic(
            id: "communication", name: "Komunikace", symbol: "bubble.left.and.bubble.right",
            categories: ["Lidská komunikace", "Rétorika"], group: .personal
        ),
        // Pravdomluvnost, integrita, odvaha, držení slova – on Wikipedia all under "Ctnosti".
        Topic(
            id: "character", name: "Charakter a hodnoty", symbol: "checkmark.seal",
            categories: ["Ctnosti", "Etika"], group: .personal
        ),
        // Proaktivita, vytrvalost, cílevědomost, pozitivita, sebevědomí.
        Topic(
            id: "motivation", name: "Motivace a sebedůvěra", symbol: "flame",
            categories: ["Osobní rozvoj", "Motivace", "Osobnost"], group: .personal
        ),
        // Time management, organizovanost.
        Topic(
            id: "productivity", name: "Produktivita", symbol: "checklist",
            categories: ["Řízení projektů", "Návyky", "Učení", "Ergonomie"], group: .personal
        ),
        Topic(
            id: "health", name: "Zdraví", symbol: "heart",
            categories: ["Zdraví", "Výživa", "Hygiena", "Spánek"], group: .personal
        ),
        Topic(
            id: "fun", name: "Legrace", symbol: "theatermasks",
            categories: ["Humor", "Satira", "Vtipy", "Komedie"], group: .personal
        ),
        Topic(
            id: "dreaming", name: "Snění", symbol: "moon.stars",
            categories: ["Sen", "Lucidní snění", "Fantazie", "Spánek"], group: .personal
        ),
    ]

    static func topic(id: String) -> Topic? {
        all.first { $0.id == id }
    }
}
