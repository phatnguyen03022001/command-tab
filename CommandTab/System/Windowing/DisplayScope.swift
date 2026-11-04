// Windowing owns display scope semantics; Settings owns persistence and its UI title.
enum DisplayScope: String, CaseIterable {
    case allVisible
    case activeOnly
}
