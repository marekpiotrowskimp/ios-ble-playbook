//
//  ContentView.swift
//  BleArchitecture
//
//  Created by Marek Piotrowski on 01/09/2024.
//

import SwiftUI

struct ContentView: View {
    let communicationManager = CommunicationManager()
    let bus = EventBus.shared
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .onTapGesture {
                    bus.subscribe(CommunicationManagerEvent.self) { event in
                        print(event)
                    }
                    bus.publish(CommunicationManagerEvent.self, .findDevices)
                }
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
