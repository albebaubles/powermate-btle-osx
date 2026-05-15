//
//  powermate_btle_osxApp.swift
//  powermate-btle-osx
//
//  Created by Al Corbett on 5/15/26.
//

import SwiftUI

@main
struct powermate_btle_osxApp: App {
  @State private var isActive = false
  let driver = PowermateControllerDriver()
  init() {
    driver.setLedOn()
  }

    var body: some Scene {
      MenuBarExtra {
        MenuBarExtraView()
      } label: {
        Image(isActive ? "record.circle.fill.blue" : "record.circle.fill.red")
          .symbolEffect(.rotate)
      }

      Window("Powermate Controller", id: "main") {
        ContentView()
          .frame(minWidth: 350,
                 idealWidth: 350,
                 maxWidth: 350,
                 minHeight: 200,
                 idealHeight: 200,
                 maxHeight: 200)
      }
      .windowResizability(.contentSize)
      .defaultSize(width: 350, height: 200)
    }
}

struct MenuBarExtraView: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Powermate...") {
            openWindow(id: "main")
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
