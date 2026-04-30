import Foundation

public struct EndpointConfig: Codable, Equatable {
    /// URL of the JSON endpoint discovered during implementation. TBD on first run.
    public var jsonEndpoint: URL?
    /// Path of the rendered settings page (always known).
    public var htmlEndpoint: URL = URL(string: "https://claude.ai/settings/usage")!

    public static let storedKey = "endpointConfig"

    public init(jsonEndpoint: URL? = nil) { self.jsonEndpoint = jsonEndpoint }
}
