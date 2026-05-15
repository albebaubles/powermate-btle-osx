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
    /// BLE Service UUID for Powermate
    static let serviceUUID = "25598CF7-4240-40A6-9910-080F19F91EBC"
    /// BLE Read Characteristic UUID
  static let readCharacteristicUUID = "9cf53570-ddd9-47f3-ba63-09acefc60415".uppercased()
    /// BLE LED Characteristic UUID
  static let ledCharacteristicUUID = "847d189e-86ee-4bd2-966f-800832b1259d".uppercased()

    /// Notification name for knob events
    static let knobNotification = "powermateKnobNotification"
    /// Notification name for LED events
    static let ledNotification = "powermateLEDNotification"

    /// LED command keys
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

// MARK: - Delegate

protocol PowermateControllerDelegate: AnyObject {
    func controller(_ controller: PowermateControllerDriver, didChangeState connected: Bool)
}

// MARK: - Driver

final class PowermateControllerDriver: NSObject, ObservableObject {
  @Published var isActive: Bool = false
  @AppStorage("swapDirection") var swapDirection: Bool = false
  @AppStorage("lineCount") var lineCount: Int = 1

    // MARK: BLE
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controller: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    weak var delegate: PowermateControllerDelegate?

    // MARK: State
    private(set) var connected: Bool = false
    private var errorReason: String = ""

    // MARK: Init

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
        if let peripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }

      // MARK: UUID helpers
    static var serviceUUID: CBUUID {
        CBUUID(string: PowermateConstants.serviceUUID)
    }

    static func name(for state: PowermateInputState) -> String {
        String(describing: state)
    }

    // MARK: Connection

    func startScan() {
        manager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: nil
        )
    }

    private func updateConnectionState(_ state: Bool) {
        connected = state
        delegate?.controller(self, didChangeState: state)
    }

    // MARK: Event processing

    private func process(_ value: UInt8) {
        if let state = PowermateInputState(rawValue: value) {
            let name = Self.name(for: state)
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name(PowermateConstants.knobNotification),
                object: name
            )
        }
    }

    // MARK: LED control via distributed notifications

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
            print("Unknown LED command")
        }
    }

    // MARK: LED implementation

    private func setLedRawValue(_ brightness: UInt8) {
        guard let controller, let writeCharacteristic else { return }

        var value = brightness
        let data = Data(bytes: &value, count: 1)

        controller.writeValue(
            data,
            for: writeCharacteristic,
            type: .withResponse
        )
    }

    private func setLedBrightness(_ intensity: Float) {
        var brightness = UInt8((0xBF - 0xA1) * intensity + 0xA1)

        if intensity <= 0 { brightness = 0x80 }
        if intensity >= 1 { brightness = 0xBF }

        setLedRawValue(brightness)
    }

     func setLedOn() {
        setLedRawValue(0x81)
    }

     func setLedOff() {
        setLedRawValue(0x80)
    }

     func quickBlinkLed() {
        setLedRawValue(0xA0)
    }

    private func blinkLed(atSpeed speed: Int) {
        let clamped = min(speed, 31)
        setLedRawValue(0xDF - UInt8(clamped))
    }

    // MARK: CGEvent scroll helper

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
}

// MARK: - CBPeripheralDelegate

extension PowermateControllerDriver: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
              [
              CBUUID(string: PowermateConstants.readCharacteristicUUID),
              CBUUID(string: PowermateConstants.ledCharacteristicUUID)],
                                               for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        guard let chars = service.characteristics else { return }

        for char in chars {
          let uuidString = char.uuid.uuidString.uppercased()
          print("string: \(uuidString)")
          if uuidString == PowermateConstants.readCharacteristicUUID {
            print("ecog: \(uuidString)")
                peripheral.setNotifyValue(true, for: char)
          } else if uuidString == PowermateConstants.ledCharacteristicUUID {
            print("recog: \(uuidString)")
                writeCharacteristic = char
                setLedOff()
            } else {
              print("did not recog: \(uuidString)")
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

        // legacy scroll behavior
        if value == UInt8(ascii: "g") {
          postScroll(delta: Int32(swapDirection ?  lineCount * -1 : lineCount))
        } else if value == UInt8(ascii: "h") {
          postScroll(delta: Int32(swapDirection ?  lineCount : lineCount * -1))
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PowermateControllerDriver: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {

        case .poweredOn:
            errorReason = ""
            startScan()

        case .poweredOff:
            errorReason = "Bluetooth is currently powered off."

        case .unauthorized:
            errorReason = "App not authorized for Bluetooth."

        case .unsupported:
            errorReason = "BLE not supported."

        case .unknown:
            errorReason = "Bluetooth state unknown."

        case .resetting:
          errorReason = "BLE state is resetting."
        @unknown default:
            errorReason = "Unknown Bluetooth error."
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
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
        isActive = true
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {

        updateConnectionState(false)
        startScan()
      isActive = false
    }
}

