//
//  PowermateInputState.swift
//  powermate-btle-osx
//
//  Created by Al Corbett on 5/15/26.
//

import Foundation
import CoreBluetooth
import ApplicationServices
import AVKit
import SwiftUI
import Combine

/// Internal constants used throughout PowermateControllerDriver.
private struct PowermateConstants {
    /// BLE Service UUID for Powermate.
    static let serviceUUID = "25598CF7-4240-40A6-9910-080F19F91EBC"
    /// BLE Read Characteristic UUID.
    static let readCharacteristicUUID = "9CF53570-DDD9-47F3-BA63-09ACEFC60415"
    /// BLE LED Characteristic UUID.
    static let ledCharacteristicUUID = "847D189E-86EE-4BD2-966F-800832B1259D"

    /// Notification name for knob events.
    static let knobNotification = "powermateKnobNotification"
    /// Notification name for LED events.
    static let ledNotification = "powermateLEDNotification"

    /// LED command keys.
    static let ledOn = "powermateLEDOn"
    static let ledOff = "powermateLEDOff"
    static let ledFlash = "powermateLEDFlash"
    static let ledLevel = "powermateLEDLevel"
}

/// The set of input states reported by the Powermate device.
enum PowermateInputState: UInt8 {
    case press = 0x65
    case release = 0x66
    case ccw = 0x67
    case cw = 0x68
    case pressedCCW = 0x69
    case pressedCW = 0x70
    case pressed1s = 0x72
    case pressed2s = 0x73
    case pressed3s = 0x74
    case pressed4s = 0x75
    case pressed5s = 0x76
    case pressed6s = 0x77
}

/// Driver class to manage Powermate device connection and interaction.
final class PowermateControllerDriver: NSObject, ObservableObject {
    /// Indicates whether the Powermate is currently connected.
    @Published private(set) var connected: Bool = false

    /// When true, the scroll direction of the Powermate is swapped.
    @AppStorage("swapDirection") var swapDirection: Bool = false
    /// Number of lines to scroll per notch of the Powermate.
    @AppStorage("lineCount") var lineCount: Int = 1

    // MARK: - BLE Properties

    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controller: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    // MARK: - Initialization

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
        updateConnectionState(false)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(ledNotificationObserver(_:)),
            name: NSNotification.Name(PowermateConstants.ledNotification),
            object: nil
        )
    }

    deinit {
        if let peripheral = peripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Static Helpers

    /// Returns the CBUUID for the Powermate service.
    static var serviceUUID: CBUUID {
        CBUUID(string: PowermateConstants.serviceUUID)
    }

    /// Returns the string name for a PowermateInputState value.
    /// - Parameter state: The PowermateInputState enum value.
    /// - Returns: The associated string name.
    static func name(for state: PowermateInputState) -> String {
        String(describing: state)
    }

    // MARK: - Connection Management

    /// Starts scanning for Powermate peripherals.
    private func startScan() {
        manager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: nil
        )
    }

    /// Updates the connection state and publishes it.
    /// - Parameter state: New connection state.
    private func updateConnectionState(_ state: Bool) {
        connected = state
    }

    // MARK: - Event Processing

    /// Processes raw input value from Powermate and posts notification.
    /// - Parameter value: Raw UInt8 input value from device.
    private func process(_ value: UInt8) {
        if let state = PowermateInputState(rawValue: value) {
            let name = Self.name(for: state)
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name(PowermateConstants.knobNotification),
                object: name
            )
        }
    }

    // MARK: - LED Control via Distributed Notifications

    /// Observes and processes LED control notifications.
    /// - Parameter notification: Notification containing LED commands.
    @objc private func ledNotificationObserver(_ notification: Notification) {
        guard let message = notification.userInfo as? [String: Any],
              let function = message["fn"] as? String else {
            return
        }

        switch function {
        case PowermateConstants.ledOn:
            setLedOn()
        case PowermateConstants.ledOff:
            setLedOff()
        case PowermateConstants.ledFlash:
            let level = message["level"] as? Int ?? 0
            if level == 32 {
                quickBlinkLed()
            } else {
                blinkLed(atSpeed: level)
            }
        case PowermateConstants.ledLevel:
            let level = message["level"] as? Float ?? 0
            setLedBrightness(level)
        default:
            log("Unknown LED command: \(function)")
        }
    }

    // MARK: - LED Implementation

    /// Writes a raw brightness value to the Powermate LED characteristic.
    /// - Parameter brightness: 8-bit brightness value to send.
    private func setLedRawValue(_ brightness: UInt8) {
        guard let controller = controller, let writeCharacteristic = writeCharacteristic else { return }
        var value = brightness
        let data = Data(bytes: &value, count: 1)
        controller.writeValue(
            data,
            for: writeCharacteristic,
            type: .withResponse
        )
    }

    /// Sets LED brightness based on normalized intensity.
    ///
    /// The brightness is mapped between 0xA1 (minimum brightness) and 0xBF (maximum brightness).
    /// Intensity less or equal to 0 results in LED off (0x80).
    /// Intensity greater or equal to 1 results in maximum brightness (0xBF).
    ///
    /// - Parameter intensity: Float value between 0 and 1 representing brightness intensity.
    private func setLedBrightness(_ intensity: Float) {
        var brightness = UInt8((0xBF - 0xA1) * intensity + 0xA1)
        if intensity <= 0 { brightness = 0x80 }  // LED off
        if intensity >= 1 { brightness = 0xBF }  // maximum brightness
        setLedRawValue(brightness)
    }

    /// Turns the Powermate LED on with a low brightness constant.
    /// 0x81 corresponds to LED on at low steady brightness.
    func setLedOn() {
        setLedRawValue(0x81)
    }

    /// Turns the Powermate LED off.
    /// 0x80 corresponds to LED off.
    func setLedOff() {
        setLedRawValue(0x80)
    }

    /// Triggers a quick blink of the Powermate LED.
    /// 0xA0 is the command value for a quick blink.
    func quickBlinkLed() {
        setLedRawValue(0xA0)
    }

    /// Blinks the Powermate LED at a specified speed.
    /// The speed is clamped between 0 and 31, where a lower value is a slower blink.
    ///
    /// - Parameter speed: Integer speed for blinking (0-31).
    private func blinkLed(atSpeed speed: Int) {
        let clamped = min(max(speed, 0), 31)
        // LED brightness command for blinking with speed encoded by decreasing from 0xDF
        setLedRawValue(0xDF - UInt8(clamped))
    }

    // MARK: - CGEvent Scroll Helper

    /// Posts a scroll wheel event with the specified delta.
    /// - Parameter delta: Number of lines to scroll (positive or negative).
    private func postScroll(delta: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postClick() {
    let location = CGEvent(source: nil)?.location ?? .zero

    let mouseDown = CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseDown,
      mouseCursorPosition: location,
      mouseButton: .left
    )

      let mouseUp = CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseUp,
      mouseCursorPosition: location,
      mouseButton: .left
    )

      mouseDown?.post(tap: .cghidEventTap)
      mouseUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Logging

    /// Logs informational messages.
    /// - Parameter message: Message string to log.
    private func log(_ message: String) {
        // Placeholder for integration with system logging or debugging.
        // For now, no output to reduce noise.
    }
}

// MARK: - CBPeripheralDelegate

extension PowermateControllerDriver: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [
                    CBUUID(string: PowermateConstants.readCharacteristicUUID),
                    CBUUID(string: PowermateConstants.ledCharacteristicUUID)
                ],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        guard let chars = service.characteristics else { return }

        for char in chars {
            let uuidString = char.uuid.uuidString.uppercased()
            if uuidString == PowermateConstants.readCharacteristicUUID {
                peripheral.setNotifyValue(true, for: char)
            } else if uuidString == PowermateConstants.ledCharacteristicUUID {
                writeCharacteristic = char
                setLedOff()
            }
        }
        updateConnectionState(true)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        guard let data = characteristic.value else { return }
        let value = data.first ?? 0

        process(value)

        if value == UInt8(ascii: "g") {
          // scroll clockwise
            postScroll(delta: Int32(swapDirection ? lineCount * -1 : lineCount))
        } else if value == UInt8(ascii: "h") {
          // scroll counter clockwise
            postScroll(delta: Int32(swapDirection ? lineCount : lineCount * -1))
        } else if value == UInt8(ascii: "e") {
          // mouse button down
          postClick()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PowermateControllerDriver: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScan()
        case .poweredOff:
            log("Bluetooth is currently powered off.")
        case .unauthorized:
            log("App not authorized for Bluetooth.")
        case .unsupported:
            log("BLE not supported.")
        case .unknown:
            log("Bluetooth state unknown.")
        case .resetting:
            log("BLE state is resetting.")
        @unknown default:
            log("Unknown Bluetooth error.")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        self.peripheral = peripheral
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {

        controller = peripheral
        controller?.delegate = self

        peripheral.discoverServices([Self.serviceUUID])
        central.stopScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {

        updateConnectionState(false)
        startScan()
    }
}
