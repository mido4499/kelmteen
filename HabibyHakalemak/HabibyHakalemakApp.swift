//
//  HabibyHakalemakApp.swift
//  HabibyHakalemak
//
//  Created by Ahmed Shaheen on 11/8/26.
//

import SwiftUI

@main
struct HabibyHakalemakApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
