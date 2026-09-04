#!/usr/bin/env swift

import AppKit
import Foundation

let mediaKeyCodes: [String: Int64] = [
    "volume-up": 0,
    "volume-down": 1,
    "brightness-up": 2,
    "brightness-down": 3,
    "mute": 7,
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: send-media-key.swift volume-up|volume-down|mute|brightness-up|brightness-down|f1|f2|f14|f15\n".utf8))
    exit(2)
}

let requestedKey = CommandLine.arguments[1]

if let virtualKey: CGKeyCode = ["f1": 122, "f2": 120, "f14": 107, "f15": 113][requestedKey] {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
    down?.flags = []
    down?.post(tap: .cghidEventTap)
    usleep(20_000)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
    up?.flags = []
    up?.post(tap: .cghidEventTap)
    exit(0)
}

guard let keyCode = mediaKeyCodes[requestedKey] else {
    FileHandle.standardError.write(Data("unknown key: \(requestedKey)\n".utf8))
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
