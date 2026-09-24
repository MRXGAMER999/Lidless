import Testing
@testable import LidlessCore

struct RefreshScheduleTests {
    var schedule = RefreshSchedule(quiet: 0.3, maxWait: 1.0)

    @Test mutating func `fires quiet seconds after a single event`() {
        #expect(schedule.eventArrived(at: 10).isApproximately(10.3))
    }

    @Test mutating func `later events push the refresh back`() {
        _ = schedule.eventArrived(at: 10)
        #expect(schedule.eventArrived(at: 10.2).isApproximately(10.5))
        #expect(schedule.eventArrived(at: 10.5).isApproximately(10.8))
    }

    /// A steady stream, such as an EDR ramp, must not starve the refresh.
    @Test mutating func `never fires later than maxWait after the first event`() {
        var fireTime = 0.0
        for now in stride(from: 10.0, through: 12.0, by: 0.1) {
            fireTime = schedule.eventArrived(at: now)
            #expect(fireTime <= 11.0 + 1e-9)
        }
        #expect(fireTime.isApproximately(11.0))
    }

    @Test mutating func `fired starts a new burst`() {
        _ = schedule.eventArrived(at: 10)
        _ = schedule.eventArrived(at: 10.9)
        schedule.fired()
        #expect(schedule.eventArrived(at: 20).isApproximately(20.3))
        #expect(schedule.eventArrived(at: 20.95).isApproximately(21.0))
    }

    @Test mutating func `is pending between an event and the refresh`() {
        #expect(!schedule.isPending)
        _ = schedule.eventArrived(at: 10)
        #expect(schedule.isPending)
        schedule.fired()
        #expect(!schedule.isPending)
    }

    @Test func `maxWait is never shorter than quiet`() {
        let short = RefreshSchedule(quiet: 0.5, maxWait: 0.1)
        #expect(short.maxWait == 0.5)
        #expect(RefreshSchedule() == RefreshSchedule(quiet: 0.3, maxWait: 1.0))
    }
}
