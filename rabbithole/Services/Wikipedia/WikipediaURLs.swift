import Foundation

nonisolated enum WikipediaURLs {
    static let restBase = URL(string: "https://cs.wikipedia.org/api/rest_v1/")!
    static let actionAPI = URL(string: "https://cs.wikipedia.org/w/api.php")!
    static let wikiBase = URL(string: "https://cs.wikipedia.org/wiki/")!
    static let license = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/deed.cs")!

    /// Wiki titles use underscores in URLs; `/` and `?` must be escaped inside a path segment.
    static func encodedTitle(_ title: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let underscored = title.replacingOccurrences(of: " ", with: "_")
        return underscored.addingPercentEncoding(withAllowedCharacters: allowed) ?? underscored
    }

    // String concatenation, not `relativeTo:` – a title like `Soubor:X` would parse as a URL scheme.
    static func summary(title: String) -> URL {
        URL(string: restBase.absoluteString + "page/summary/" + encodedTitle(title))!
    }

    static func article(title: String) -> URL {
        URL(string: wikiBase.absoluteString + encodedTitle(title))!
    }

    static func filePage(fileTitle: String) -> URL {
        article(title: "Soubor:\(fileTitle)")
    }

    static func actionQuery(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: actionAPI, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ] + items
        return components.url!
    }

    /// Extracts the file name from an `upload.wikimedia.org` URL, handling `/thumb/` variants
    /// and stripping query parameters.
    ///
    ///     …/commons/0/02/Mars.jpg?utm=…            -> Mars.jpg
    ///     …/commons/thumb/0/02/Mars.jpg/330px-Mars.jpg -> Mars.jpg
    static func fileTitle(fromImageURL url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 2 else { return nil }
        let raw: String
        if let thumbIndex = parts.firstIndex(of: "thumb"), parts.count > thumbIndex + 3 {
            raw = parts[thumbIndex + 3]
        } else {
            raw = parts[parts.count - 1]
        }
        let decoded = raw.removingPercentEncoding ?? raw
        return decoded.isEmpty ? nil : decoded.replacingOccurrences(of: "_", with: " ")
    }
}
