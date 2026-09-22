import Foundation

public struct Config: Codable, Equatable {
    public var passwordHash: String?
    public var message: String
    public var keepAwake: Bool

    public static let defaultMessage = "正在工作，请勿触碰。"

    public init(passwordHash: String?, message: String, keepAwake: Bool) {
        self.passwordHash = passwordHash
        self.message = message
        self.keepAwake = keepAwake
    }

    public static let empty = Config(passwordHash: nil, message: defaultMessage, keepAwake: true)

    enum CodingKeys: String, CodingKey {
        case passwordHash = "password_hash"
        case message
        case keepAwake = "keep_awake"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        passwordHash = try box.decodeIfPresent(String.self, forKey: .passwordHash)
        message = try box.decodeIfPresent(String.self, forKey: .message) ?? Self.defaultMessage
        keepAwake = try box.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
    }
}

public final class Store {
    public static let directory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/app.vigil.lock", isDirectory: true)
    }()

    public let fileURL: URL
    public private(set) var config: Config

    public init(fileURL: URL = Store.directory.appendingPathComponent("config.json")) {
        self.fileURL = fileURL
        config = Config.load(from: fileURL)
    }

    public var hasPassword: Bool {
        guard let hash = config.passwordHash else { return false }
        return !hash.isEmpty
    }

    public func setPassword(_ password: String) throws {
        config.passwordHash = try Password.hash(password)
        try save()
    }

    public func setMessage(_ message: String) throws {
        config.message = String(message.prefix(80))
        try save()
    }

    public func setKeepAwake(_ value: Bool) throws {
        config.keepAwake = value
        try save()
    }

    public func verify(_ password: String) -> Bool {
        guard let hash = config.passwordHash, !hash.isEmpty else { return false }
        return Password.verify(password, hash: hash)
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}

extension Config {
    static func load(from url: URL) -> Config {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? .empty
    }
}
