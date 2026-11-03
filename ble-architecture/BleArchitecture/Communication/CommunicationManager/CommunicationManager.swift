//
//  CommunicationManager.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

class CommunicationManager {
    private let bus = EventBus.shared
    private let services = [BLEServices()]
    
    init() {
        inputData()
    }
    
    
    private func inputData() {
        bus.subscribe(CommunicationManagerEvent.self) { [unowned self] event in
            self.handleEvent(event)
        }
    }
    
    func handleEvent(_ event: CommunicationManagerEvent) {
        CommunicationManager
            .communicationManagerHandlers
            .filter { $0.applay(event) }
            .forEach { $0.handleEvent(event) }
    }
    
}
