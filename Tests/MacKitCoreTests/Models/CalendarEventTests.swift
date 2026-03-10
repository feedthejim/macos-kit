import Testing
import Foundation
@testable import MacKitCore

@Suite("CalendarEvent Model")
struct CalendarEventTests {
    private let now = Date()

    private func event(
        title: String = "Standup",
        minutesFromNow: Int = 30,
        durationMinutes: Int = 15,
        calendar: String = "Work",
        isAllDay: Bool = false,
        meetingURL: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: "test-id",
            title: title,
            startDate: now.addingTimeInterval(TimeInterval(minutesFromNow * 60)),
            endDate: now.addingTimeInterval(TimeInterval((minutesFromNow + durationMinutes) * 60)),
            isAllDay: isAllDay,
            calendarName: calendar,
            meetingURL: meetingURL
        )
    }

    // MARK: - Codable round-trip

    @Test("Encodes and decodes without data loss")
    func codableRoundTrip() throws {
        let original = CalendarEvent(
            id: "abc",
            title: "Test Event",
            startDate: Date(timeIntervalSince1970: 1700000000),
            endDate: Date(timeIntervalSince1970: 1700003600),
            isAllDay: false,
            location: "Room 42",
            calendarName: "Work",
            calendarColor: "#FF0000",
            status: .confirmed,
            organizer: "boss@example.com",
            notes: "Bring laptop",
            url: "https://example.com",
            meetingURL: "https://zoom.us/j/123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalendarEvent.self, from: data)

        #expect(decoded == original)
    }

    @Test("Encodes nil optional fields by omitting them")
    func nilFieldsOmitted() throws {
        let e = event(meetingURL: nil)
        let data = try JSONEncoder().encode(e)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("meetingURL"))
    }

    // MARK: - TextRepresentable

    @Test("Text summary contains title and calendar")
    func textSummary() {
        let e = event(title: "Design Review", calendar: "Engineering")
        #expect(e.textSummary.contains("Design Review"))
        #expect(e.textSummary.contains("Engineering"))
    }

    @Test("All-day event shows 'All day'")
    func allDayText() {
        let e = event(title: "Holiday", isAllDay: true)
        #expect(e.textSummary.contains("All day"))
    }

    @Test("Meeting URL shows host in summary")
    func meetingURLInSummary() {
        let e = event(meetingURL: "https://zoom.us/j/123")
        #expect(e.textSummary.contains("zoom.us"))
    }

    @Test("Text detail shows meeting URL")
    func textDetailMeetingURL() {
        let e = event(meetingURL: "https://zoom.us/j/123456")
        #expect(e.textDetail.contains("https://zoom.us/j/123456"))
    }

    // MARK: - TableRepresentable

    @Test("Table headers match row structure")
    func tableStructure() {
        let e = event()
        #expect(CalendarEvent.tableHeaders.count == e.tableRow.count)
    }

    // MARK: - FieldSelectable

    @Test("Available fields includes optional fields")
    func availableFieldsComplete() {
        let fields = CalendarEvent.availableFields
        #expect(fields.contains("meetingURL"))
        #expect(fields.contains("location"))
        #expect(fields.contains("organizer"))
        #expect(fields.contains("notes"))
        #expect(fields.contains("title"))
        #expect(fields.contains("startDate"))
    }
}
