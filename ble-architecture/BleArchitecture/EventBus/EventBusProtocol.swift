//
//  EventBusProtocol.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 10/09/2024.
//

import Foundation
import Combine

protocol EventBusProtocol {
    func subscribe<T: EventTypeProtocol>(_ type: T.Type, _ closure: ((T) -> Void)?)
    func publish<T: EventTypeProtocol>(_ type: T.Type, _ data: T)
}
