//
//  CommunicationManagerHandlers.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

extension CommunicationManager {
    static var communicationManagerHandlers: [EventHandling] =
        [
            FindDevicesEventHandling()
        ]
}
