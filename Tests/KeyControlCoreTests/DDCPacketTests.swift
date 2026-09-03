import Testing
@testable import KeyControlCore

@Test func brightnessReadPacket() {
    #expect(DDCController.readPacket(feature: 0x10) == [0x82, 0x01, 0x10, 0xAC])
}

@Test func brightnessWritePacket() {
    let packet = DDCController.writePacket(feature: 0x10, value: 75)
    #expect(packet == [0x84, 0x03, 0x10, 0x00, 0x4B, 0xE3])
    #expect(packet.reduce(0x6E ^ 0x51, ^) == 0)
}
