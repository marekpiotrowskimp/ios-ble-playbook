//
//  BLEServices.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

class BLEServices {
    private var bus = EventBus.shared
    
    init() {
        binding()
    }
    
    private func binding() {
        bus.subscribe(BLEConnectionEvent.self) { [unowned self] event in
            self.bus.publish(CommunicationManagerEvent.self, .findDevicesReturn([.init(name: "Gahan", id: "gahan")]))
        }
    }
}
