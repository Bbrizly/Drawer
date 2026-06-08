import Foundation

public struct TodoItem: Equatable, Identifiable, Sendable {
    public let id: String          // sectionDate + "|" + occurrence + "|" + rawLine
    public let rawLine: String     // exact line as in the file (no trailing \r)
    public let title: String       // duration hint stripped
    public let isDone: Bool
    public let minutes: Int        // duration hint, default 25
    public let sectionDate: String // "YYYY-MM-DD"
    /// Index among identical rawLines within the same date section, so
    /// duplicate task lines stay distinct for SwiftUI and writeback.
    public let occurrence: Int
    /// Title of the nearest "### " subheading above the task within its
    /// section, nil if none. Lets grouped sections (Archive) render their
    /// sub-structure.
    public let subsection: String?

    public init(
        rawLine: String,
        title: String,
        isDone: Bool,
        minutes: Int,
        sectionDate: String,
        occurrence: Int = 0,
        subsection: String? = nil
    ) {
        self.id = sectionDate + "|" + String(occurrence) + "|" + rawLine
        self.rawLine = rawLine
        self.title = title
        self.isDone = isDone
        self.minutes = minutes
        self.sectionDate = sectionDate
        self.occurrence = occurrence
        self.subsection = subsection
    }
}

public struct DaySection: Equatable, Sendable {
    public let date: String
    public let items: [TodoItem]

    public init(date: String, items: [TodoItem]) {
        self.date = date
        self.items = items
    }
}
