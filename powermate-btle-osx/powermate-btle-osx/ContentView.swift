//
//  ContentView.swift
//  powermate-btle-osx
//
//  Created by Al Corbett on 5/15/26.
//

import SwiftUI

struct ContentView: View {
  @AppStorage("lineCount")
  private var lineCount = 1

  @AppStorage("swapDirection")
  private var swapDirection: Bool = false

  var body: some View {

    VStack {
      HStack {
        VStack {
          Image("powermate")
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)

          Text("Powermate")
            .font(.title)

          Text("BTLE Driver")
            .font(.caption)
        }
        .padding()

        Rectangle()
          .fill(Color.gray.opacity(0.4))
          .frame(width: 1)
          .padding(.vertical)

        VStack(alignment: .leading) {
          Toggle(isOn: $swapDirection) {
            Text("Swap Direction")
          }
          Picker("Line count", selection: $lineCount) {
            ForEach(1...10, id: \.self) { i in

              Text("\(i)").tag(i)

            }

          }
        }
        .padding()
      }
    }
  }
}

#Preview {
  ContentView()
    .frame(minWidth: 350,
           idealWidth: 350,
           maxWidth: 350,
           minHeight: 200,
           idealHeight: 200,
           maxHeight: 200)
}
