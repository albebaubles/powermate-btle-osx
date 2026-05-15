# Powermate BTLE Driver for macOS

A modern macOS driver and controller for the Bluetooth Low Energy (BTLE) Griffin Powermate device. This app connects to and manages a Powermate knob, allowing you to emulate scrolling, clicks, and control the LED via a menu bar interface and customizable settings.

## Features
- **Bluetooth LE connection** to the Griffin Powermate knob
- **Menu bar app** for quick access and status
- **Customizable scroll direction and line count**
- **LED control**: turn on/off, set brightness, and blink
- **macOS native integration** with smooth scrolling and click events
- Built with **SwiftUI** and **Combine**

## Installation
1. Clone this repository.
2. Open the project in Xcode (tested with Xcode 26.5).
3. Build and run the `powermate-btle-osx` target.

> **Note:** This project requires a Bluetooth Low Energy Powermate device.

## Usage
- Launch the app. The menu bar icon will indicate connection status (blue: connected, red: disconnected).
- Access preferences via the menu bar or window:
  - **Swap Direction**: Reverses the scroll direction.
  - **Line Count**: Number of lines scrolled per knob notch.
- Device input (rotate, press) triggers system scroll/click events.
- LED can be controlled programmatically or via notifications.

## Settings
- **Swap Direction:** Toggle in the main window or menu bar.
- **Line Count:** Select from 1–10 lines per step.

## Screenshots
<img src="./screenshot.png" width="300" />

## Project Structure
- `PowermateControllerDriver.swift`: Core device communication and event processing
- `ContentView.swift`: SwiftUI UI for configuration
- `powermate_btle_osxApp.swift`: App entry and menu bar integration

## Acknowledgements
- Inspired by the original Griffin Powermate software
- Built with Apple's CoreBluetooth, SwiftUI, and Combine frameworks

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
---

