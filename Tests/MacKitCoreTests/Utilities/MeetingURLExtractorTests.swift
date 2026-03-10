import Testing
import Foundation
@testable import MacKitCore

@Suite("MeetingURLExtractor")
struct MeetingURLExtractorTests {
    @Test("Extracts Zoom URL")
    func zoomURL() {
        let result = MeetingURLExtractor.extract(from: "https://zoom.us/j/123456789")
        #expect(result == "https://zoom.us/j/123456789")
    }

    @Test("Extracts Zoom URL with password")
    func zoomWithPassword() {
        let result = MeetingURLExtractor.extract(from: "https://zoom.us/j/123456789?pwd=abc")
        #expect(result == "https://zoom.us/j/123456789?pwd=abc")
    }

    @Test("Extracts Google Meet URL")
    func googleMeet() {
        let result = MeetingURLExtractor.extract(from: "Join: https://meet.google.com/abc-defg-hij")
        #expect(result == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Extracts Teams URL")
    func teamsURL() {
        let url = "https://teams.microsoft.com/l/meetup-join/abc123"
        let result = MeetingURLExtractor.extract(from: url)
        #expect(result == url)
    }

    @Test("Extracts Zoom subdomain URL")
    func zoomSubdomain() {
        let result = MeetingURLExtractor.extract(from: "https://us02web.zoom.us/j/12345?pwd=xyz")
        #expect(result == "https://us02web.zoom.us/j/12345?pwd=xyz")
    }

    @Test("Returns nil for plain text")
    func plainText() {
        let result = MeetingURLExtractor.extract(from: "Notes with no URL")
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        let result = MeetingURLExtractor.extract(from: "")
        #expect(result == nil)
    }

    @Test("Returns nil for non-meeting URL")
    func nonMeetingURL() {
        let result = MeetingURLExtractor.extract(from: "https://example.com/not-a-meeting")
        #expect(result == nil)
    }

    @Test("Extracts URL from surrounding text")
    func urlInText() {
        let result = MeetingURLExtractor.extract(from: "Zoom: https://zoom.us/j/123 and also random text")
        #expect(result == "https://zoom.us/j/123")
    }

    @Test("Extracts Webex URL")
    func webexURL() {
        let result = MeetingURLExtractor.extract(from: "https://webex.com/meet/john.doe")
        #expect(result == "https://webex.com/meet/john.doe")
    }

    @Test("Prefers location over notes when both have URLs")
    func prefersLocation() {
        let result = MeetingURLExtractor.extract(
            fromLocation: "https://zoom.us/j/111",
            notes: "https://zoom.us/j/222",
            url: nil
        )
        #expect(result == "https://zoom.us/j/111")
    }

    @Test("Falls back to notes if location has no URL")
    func fallsBackToNotes() {
        let result = MeetingURLExtractor.extract(
            fromLocation: "Conference Room A",
            notes: "Join via https://meet.google.com/abc-defg-hij",
            url: nil
        )
        #expect(result == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Uses url field as fallback")
    func usesURLField() {
        let result = MeetingURLExtractor.extract(
            fromLocation: nil,
            notes: nil,
            url: "https://zoom.us/j/999"
        )
        #expect(result == "https://zoom.us/j/999")
    }

    @Test("Extracts Around URL")
    func aroundURL() {
        let result = MeetingURLExtractor.extract(from: "https://app.around.co/r/abc-123")
        #expect(result == "https://app.around.co/r/abc-123")
    }
}
