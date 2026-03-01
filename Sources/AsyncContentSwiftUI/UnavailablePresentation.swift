import Foundation

public struct UnavailablePresentation: Sendable, Equatable {
    public var title: String
    public var message: String?
    public var systemImage: String

    public init(
        title: String,
        message: String? = nil,
        systemImage: String
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }
}
