import Foundation

private final class BundleToken {}

/// Loads JSON fixtures captured from the real cs.wikipedia.org APIs (trimmed).
enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
