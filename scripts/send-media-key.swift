#!/usr/bin/env swift

import AppKit
import Foundation

let keyCodes: [String: Int64] = [
    "volume-up": 0,
    "volume-down": 1,
    "brightness-up": 2,
    "brightness-down": 3,
    "mute": 7,
]

guard CommandLine.arguments.count == 2,
      let keyCode = keyCodes[CommandLine.arguments[1]] else {
    FileHandle.standardError.write(Data("usage: send-media-key.swift volume-up|volume-down|mute|brightness-up|brightness-down\n".utf8))
    exit(2)
}

func post(state: Int64) {
    let data1 = Int((keyCode << 16) | (state << 8))
    guard let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    )?.cgEvent else {
        FileHandle.standardError.write(Data("could not construct media-key event\n".utf8))
        exit(1)
    }
    event.post(tap: .cghidEventTap)
}

post(state: 0x0A)
usleep(20_000)
post(state: 0x0B)
