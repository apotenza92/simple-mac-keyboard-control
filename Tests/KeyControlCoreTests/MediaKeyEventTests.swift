import Testing
@testable import KeyControlCore

@Test func decodesSupportedKeyDownEvents() {
    #expect(decode(0).key == .volumeUp)
    #expect(decode(1).key == .volumeDown)
    #expect(decode(2).key == .brightnessUp)
    #expect(decode(3).key == .brightnessDown)
    #expect(decode(7).key == .mute)
    #expect(decode(7).isKeyDown)
}

@Test func decodesKeyUpWithoutTriggeringPress() {
    let data = (Int64(0) << 16) | 0x0B00
    #expect(MediaKeyEvent.decode(data1: data)?.key == .volumeUp)
    #expect(MediaKeyEvent.decode(data1: data)?.isKeyDown == false)
}

@Test func rejectsUnrelatedMediaKeys() {
    let playPause = (Int64(16) << 16) | 0x0A00
    #expect(MediaKeyEvent.decode(data1: playPause) == nil)
}

private func decode(_ code: Int64) -> (key: MediaKey, isKeyDown: Bool) {
    MediaKeyEvent.decode(data1: (code << 16) | 0x0A00)!
}
