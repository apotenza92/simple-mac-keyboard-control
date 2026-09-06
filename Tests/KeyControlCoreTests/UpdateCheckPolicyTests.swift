import Testing
@testable import KeyControlCore

@Test func updateScheduleDefaultsAndChoices() {
    #expect(UpdateCheckSchedule.resolve(saved: nil, bundleIdentifier: "com.apotenza.KeyControl.beta", automaticChecksEnabled: true) == .startup)
    #expect(UpdateCheckSchedule.resolve(saved: nil, bundleIdentifier: "com.apotenza.KeyControl", automaticChecksEnabled: true) == .weekly)
    #expect(UpdateCheckSchedule.resolve(saved: "weekly", bundleIdentifier: "com.apotenza.KeyControl.beta", automaticChecksEnabled: true) == .weekly)
    #expect(UpdateCheckSchedule.resolve(saved: "startup", bundleIdentifier: "com.apotenza.KeyControl", automaticChecksEnabled: true) == .startup)
    #expect(UpdateCheckSchedule.resolve(saved: "startup", bundleIdentifier: "com.apotenza.KeyControl.beta", automaticChecksEnabled: false) == .never)
}

@Test func dailyAndMonthlySchedulesPersistAndUseTheirIntervals() {
    for choice in [UpdateCheckSchedule.daily, .monthly] {
        #expect(UpdateCheckSchedule.resolve(saved: choice.rawValue, bundleIdentifier: "com.apotenza.KeyControl.beta", automaticChecksEnabled: true) == choice)
    }
    #expect(UpdateCheckSchedule.daily.interval == 86400)
    #expect(UpdateCheckSchedule.weekly.interval == 604800)
    #expect(UpdateCheckSchedule.monthly.interval == 2592000)
}
