import OSLog

enum Log {
    static let app = Logger(subsystem: "com.picmao.commandtab", category: "app")
    static let input = Logger(subsystem: "com.picmao.commandtab", category: "input")
    static let windows = Logger(subsystem: "com.picmao.commandtab", category: "windows")
    static let focus = Logger(subsystem: "com.picmao.commandtab", category: "focus")
    static let settings = Logger(subsystem: "com.picmao.commandtab", category: "settings")
}
