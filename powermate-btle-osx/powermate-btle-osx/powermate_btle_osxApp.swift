//
//  powermate_btle_osxApp.swift
//  powermate-btle-osx
//
//  Created by Al Corbett on 5/15/26.
//

import SwiftUI

@main
struct powermate_btle_osxApp: App {
  @StateObject var driver = PowermateControllerDriver()

    var body: some Scene {
      MenuBarExtra {
        MenuBarExtraView()
          .environmentObject(driver)
      } label: {
        Image(driver.connected ? "record.circle.fill.blue" : "record.circle.fill.red")
          .symbolEffect(.rotate)
      }

      Window("Powermate Controller", id: "main") {
        ContentView()
          .environmentObject(driver)
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
    @EnvironmentObject var driver: PowermateControllerDriver

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
