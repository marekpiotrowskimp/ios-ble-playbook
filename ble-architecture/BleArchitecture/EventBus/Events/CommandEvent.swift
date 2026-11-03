//
//  CommandEvent.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

enum CommandEvent: EventTypeProtocol {
    case findDevices
}

enum BLEConnectionEvent: EventTypeProtocol {
    case scan
    case scanReturn([Device])
//    case connect
//    case disconnect
//    case write
//    case read
//    case notification
}

enum CommunicationManagerEvent: EventTypeProtocol {
    case findDevices
    case findDevicesReturn([Device])
//    case connectToDevice
//    case disconnectDevice
//    case writeData
//    case readData
//    case setNotification
}

extension CommunicationManagerEvent: Equatable {
    static func == (lhs: CommunicationManagerEvent, rhs: CommunicationManagerEvent) -> Bool {
        switch (lhs, rhs) {
            case (.findDevices, .findDevices), (.findDevicesReturn, .findDevicesReturn):
                return true
            default:
                return false
        }
    }
}

extension EventTypeProtocol {
    var communicationManagerEvent: CommunicationManagerEvent? { self as? CommunicationManagerEvent }
}
