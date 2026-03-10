import Testing
import Foundation
@testable import MacKitCore

@Suite("CalendarWriteService")
struct CalendarWriteServiceTests {
    private let now = Date()

    // MARK: - createEvent

    @Test("Create event returns correct fields")
    func createEventReturnsCorrectFields() async throws {
        let mock = MockCalendarWriteService()
        let start = now.addingTimeInterval(3600)
        let end = now.addingTimeInterval(7200)

        let request = CreateEventRequest(
            title: "Team Standup",
            startDate: start,
            endDate: end,
            calendarName: "Work",
            location: "Room 42",
            notes: "Daily sync"
        )

        let event = try await mock.createEvent(request)

        #expect(event.title == "Team Standup")
        #expect(event.startDate == start)
        #expect(event.endDate == end)
        #expect(event.calendarName == "Work")
        #expect(event.location == "Room 42")
        #expect(event.notes == "Daily sync")
        #expect(event.isAllDay == false)
        #expect(mock.createdEvents.count == 1)
        #expect(mock.mockEvents.count == 1)
    }

    @Test("Create all-day event")
    func createAllDayEvent() async throws {
        let mock = MockCalendarWriteService()
        let start = now
        let end = now.addingTimeInterval(86400)

        let request = CreateEventRequest(
            title: "Holiday",
            startDate: start,
            endDate: end,
            isAllDay: true
        )

        let event = try await mock.createEvent(request)

        #expect(event.title == "Holiday")
        #expect(event.isAllDay == true)
    }

    // MARK: - deleteEvent

    @Test("Delete event removes it")
    func deleteEventRemoves() async throws {
        let mock = MockCalendarWriteService()
        let request = CreateEventRequest(
            title: "To Delete",
            startDate: now,
            endDate: now.addingTimeInterval(3600)
        )
        let event = try await mock.createEvent(request)

        try await mock.deleteEvent(id: event.id)

        #expect(mock.mockEvents.isEmpty)
        #expect(mock.deletedIds == [event.id])
    }

    @Test("Delete non-existent event throws notFound")
    func deleteNonExistentThrows() async {
        let mock = MockCalendarWriteService()

        await #expect(throws: MacKitError.self) {
            try await mock.deleteEvent(id: "nonexistent-id")
        }
    }

    // MARK: - updateEvent

    @Test("Update event changes fields")
    func updateEventChangesFields() async throws {
        let mock = MockCalendarWriteService()
        let request = CreateEventRequest(
            title: "Original",
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            location: "Room A"
        )
        let event = try await mock.createEvent(request)

        let newStart = now.addingTimeInterval(7200)
        let updateRequest = UpdateEventRequest(
            eventId: event.id,
            title: "Updated Title",
            startDate: newStart,
            location: "Room B"
        )

        let updated = try await mock.updateEvent(updateRequest)

        #expect(updated.id == event.id)
        #expect(updated.title == "Updated Title")
        #expect(updated.startDate == newStart)
        #expect(updated.endDate == event.endDate)
        #expect(updated.location == "Room B")
    }

    @Test("Update non-existent event throws notFound")
    func updateNonExistentThrows() async {
        let mock = MockCalendarWriteService()

        let request = UpdateEventRequest(eventId: "nonexistent-id", title: "New Title")

        await #expect(throws: MacKitError.self) {
            try await mock.updateEvent(request)
        }
    }

    // MARK: - findEvent

    @Test("Find event returns matching event")
    func findEventReturns() async throws {
        let mock = MockCalendarWriteService()
        let request = CreateEventRequest(
            title: "Findable",
            startDate: now,
            endDate: now.addingTimeInterval(3600)
        )
        let created = try await mock.createEvent(request)

        let found = try await mock.findEvent(id: created.id)
        #expect(found.id == created.id)
        #expect(found.title == "Findable")
    }

    @Test("Find non-existent event throws notFound")
    func findNonExistentThrows() async {
        let mock = MockCalendarWriteService()

        await #expect(throws: MacKitError.self) {
            try await mock.findEvent(id: "nonexistent-id")
        }
    }

    // MARK: - Permission handling

    @Test("Permission denied throws correct error on create")
    func permissionDeniedOnCreate() async {
        let mock = MockCalendarWriteService()
        mock.shouldDenyPermission = true

        let request = CreateEventRequest(
            title: "Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )

        await #expect(throws: MacKitError.self) {
            try await mock.createEvent(request)
        }
    }

    @Test("Permission denied throws correct error on delete")
    func permissionDeniedOnDelete() async {
        let mock = MockCalendarWriteService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.deleteEvent(id: "some-id")
        }
    }
}
