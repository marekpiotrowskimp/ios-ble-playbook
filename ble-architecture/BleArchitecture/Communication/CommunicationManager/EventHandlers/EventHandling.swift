//
//  EventHandling.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

protocol EventHandling {
    func applay(_ event: EventTypeProtocol) -> Bool
    func handleEvent(_ event: EventTypeProtocol)
}

