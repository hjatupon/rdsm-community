import Testing
import Foundation
@testable import ConnectionUI

@Suite("URLValidatorTests")
struct URLValidatorTests {

    // MARK: - Valid URLs

    @Test("ws:// with host is valid")
    func testWsValid() {
        let result = URLValidator.validate("ws://localhost:8765")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("wss:// with host is valid")
    func testWssValid() {
        let result = URLValidator.validate("wss://robot.local:8765")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("ws:// with IP address is valid")
    func testWsIPValid() {
        let result = URLValidator.validate("ws://192.168.1.10:8765")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("ws:// with no port is valid")
    func testWsNoPortValid() {
        let result = URLValidator.validate("ws://localhost")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("URL with path segment is valid")
    func testWsWithPath() {
        let result = URLValidator.validate("ws://localhost:8765/ros")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("valid URL returns correct URL object")
    func testValidReturnsURL() {
        let result = URLValidator.validate("ws://myrobot:9000")
        guard case .valid(let url) = result else {
            Issue.record("Expected valid"); return
        }
        #expect(url.host == "myrobot")
        #expect(url.port == 9000)
    }

    // MARK: - Empty

    @Test("empty string returns empty")
    func testEmpty() {
        #expect(URLValidator.validate("") == .empty)
    }

    @Test("whitespace-only string returns empty")
    func testWhitespace() {
        #expect(URLValidator.validate("   ") == .empty)
    }

    // MARK: - Wrong scheme

    @Test("http:// scheme rejected")
    func testHttpScheme() {
        let result = URLValidator.validate("http://localhost:8765")
        if case .invalidScheme = result { } else {
            Issue.record("Expected invalidScheme, got \(result)")
        }
    }

    @Test("tcp:// scheme rejected")
    func testTcpScheme() {
        let result = URLValidator.validate("tcp://robot.local:9090")
        if case .invalidScheme = result { } else {
            Issue.record("Expected invalidScheme, got \(result)")
        }
    }

    @Test("no scheme rejected")
    func testNoScheme() {
        let result = URLValidator.validate("localhost:8765")
        // Either invalidScheme or malformed depending on how URL parses it
        switch result {
        case .invalidScheme, .malformed: break
        default: Issue.record("Expected invalidScheme or malformed, got \(result)")
        }
    }

    // MARK: - Port out of range

    @Test("port 0 is out of range")
    func testPortZero() {
        let result = URLValidator.validate("ws://localhost:0")
        if case .portOutOfRange(0) = result { } else {
            Issue.record("Expected portOutOfRange(0), got \(result)")
        }
    }

    @Test("port 65536 is out of range")
    func testPortOverflow() {
        let result = URLValidator.validate("ws://localhost:65536")
        if case .portOutOfRange(65536) = result { } else {
            Issue.record("Expected portOutOfRange(65536), got \(result)")
        }
    }

    @Test("port 65535 is valid")
    func testMaxPort() {
        let result = URLValidator.validate("ws://localhost:65535")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    @Test("port 1 is valid")
    func testMinPort() {
        let result = URLValidator.validate("ws://localhost:1")
        if case .valid = result { } else {
            Issue.record("Expected valid, got \(result)")
        }
    }

    // MARK: - Error messages

    @Test("errorMessage is nil for valid URL")
    func testNoErrorForValid() {
        let result = URLValidator.validate("ws://localhost:8765")
        #expect(URLValidator.errorMessage(for: result) == nil)
    }

    @Test("errorMessage is nil for empty")
    func testNoErrorForEmpty() {
        #expect(URLValidator.errorMessage(for: .empty) == nil)
    }

    @Test("errorMessage is non-nil for invalid scheme")
    func testErrorForBadScheme() {
        let result = URLValidator.validate("http://localhost")
        #expect(URLValidator.errorMessage(for: result) != nil)
    }

    @Test("errorMessage is non-nil for out-of-range port")
    func testErrorForBadPort() {
        let result = URLValidator.validate("ws://localhost:99999")
        #expect(URLValidator.errorMessage(for: result) != nil)
    }

    // MARK: - Trimming

    @Test("leading/trailing whitespace is trimmed before validation")
    func testTrimming() {
        let result = URLValidator.validate("  ws://localhost:8765  ")
        if case .valid = result { } else {
            Issue.record("Expected valid after trimming, got \(result)")
        }
    }
}
