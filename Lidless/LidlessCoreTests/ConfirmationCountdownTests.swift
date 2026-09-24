import Foundation
import Testing
@testable import LidlessCore

struct ConfirmationCountdownTests {
    let countdown = ConfirmationCountdown(deadline: 115, total: 15)

    @Test(arguments: [
        (100.0, 15),
        (100.2, 15),
        (103.0, 12),
        (103.5, 12),
        (114.01, 1),
        (115.0, 0),
        (130.0, 0),
    ])
    func `seconds left round up and never go negative`(now: TimeInterval, seconds: Int) {
        #expect(countdown.secondsLeft(now: now) == seconds)
    }

    @Test(arguments: [
        (90.0, 1.0),
        (100.0, 1.0),
        (103.0, 0.8),
        (107.5, 0.5),
        (115.0, 0.0),
        (130.0, 0.0),
    ])
    func `the bar empties linearly from full to the deadline`(now: TimeInterval, fraction: Double) {
        #expect(abs(countdown.fraction(now: now) - fraction) < 1e-9)
    }

    @Test func `a zero-length countdown shows an empty bar`() {
        #expect(ConfirmationCountdown(deadline: 10, total: 0).fraction(now: 5) == 0)
    }

    @Test func `expires at the deadline`() {
        #expect(!countdown.isExpired(now: 114.99))
        #expect(countdown.isExpired(now: 115))
    }

    @Test func `the default length is 15 seconds`() {
        #expect(ConfirmationCountdown(deadline: 15).total == 15)
    }

    @Test func `VoiceOver hears 15, 10, 5 and the last three seconds`() {
        let announced = (0...20).filter(ConfirmationCountdown.shouldAnnounce(secondsLeft:))
        #expect(announced == [1, 2, 3, 5, 10, 15])
    }
}
