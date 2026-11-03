
import Foundation
import Combine

class EventBus {
    static let shared: EventBusProtocol = EventBus()
    private var cancellables = Set<AnyCancellable>()
    private var bus = PassthroughSubject<Event, Never>()
    private let eventBuffer = EventBuffer()
    private var subscriptions: [((EventTypeProtocol) -> Void)?] = []
    
    private init() {
        binding()
    }
    
    private func binding() {
        bus
            .sink { event in
                self.subscriptions.forEach { closure in
                    closure?(event.data)
                }
            }
            .store(in: &cancellables)
    }
}

extension EventBus: EventBusProtocol {
    func subscribe<T>(_ type: T.Type, _ closure: ((T) -> Void)?) where T : EventTypeProtocol {
        subscriptions.append({ event in
            if let data = event as? T {
                closure?(data)
            }
        })
        let typeName = String(describing: T.self)
        let event = eventBuffer.getEvent(typeName)
        if let event = event {
            bus.send(event)
        }
    }
    
    func publish<T>(_ type: T.Type, _ data: T) where T : EventTypeProtocol {
        let typeName = String(describing: T.self)
        let event = Event(name: typeName, data: data)
        eventBuffer.setEvent(typeName, event)
        bus.send(event)
    }
}

extension EventBus {
    class Event {
        let chanel: String
        let data: EventTypeProtocol
        init(name: String, data: EventTypeProtocol) {
            self.chanel = name
            self.data = data
        }
    }
}



