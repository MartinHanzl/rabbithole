import Foundation

/// Mapping of app topics to Czech Wikipedia categories.
///
/// This is the single place to edit when tuning content:
/// - `categories` are category names on cs.wikipedia.org **without** the `Kategorie:` prefix.
/// - Subcategories are crawled automatically up to `AppConfig.categoryCrawlDepth`.
/// - `id` is persisted (selection, weights) – don't rename existing ids.
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
    ]

    static func topic(id: String) -> Topic? {
        all.first { $0.id == id }
    }
}
