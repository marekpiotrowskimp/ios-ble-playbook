//
//  FindDevicesEventHandling.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

class FindDevicesEventHandling {
    private var bus = EventBus.shared
    
    init() {
        binding()
    }
    
    private func binding() {
        bus.subscribe(BLEConnectionEvent.self) { [unowned self] event in
            if case BLEConnectionEvent.scanReturn(let devices) = event {
                self.bus.publish(CommunicationManagerEvent.self, .findDevicesReturn(devices))
            }
        }
    }
    
}


extension FindDevicesEventHandling: EventHandling {
    func applay(_ event: EventTypeProtocol) -> Bool {
        return event.communicationManagerEvent == .findDevices
    }
    
    func handleEvent(_ event: EventTypeProtocol) {
        guard let event = event.communicationManagerEvent else { return }
        bus.publish(BLEConnectionEvent.self, .scan)
    }
}
