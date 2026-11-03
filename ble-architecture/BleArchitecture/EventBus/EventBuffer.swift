//
//  EventBuffer.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation

class EventBuffer {
    private var cache: NSCache<NSString, EventBus.Event> = .init()
    
    func getEvent(_ key: String) -> EventBus.Event? {
        if let buffer = cache.object(forKey: key as NSString) {
            return buffer
        }
        return nil
    }
    
    func setEvent(_ key: String, _ event: EventBus.Event) {
        cache.setObject(event, forKey: key as NSString)
    }
}
