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


// MARK: - Constants

let kPowermateServiceUUID = "25598CF7-4240-40A6-9910-080F19F91EBC".uppercased()
let kPowermateReadCharacteristicUUID = "9cf53570-ddd9-47f3-ba63-09acefc60415".uppercased()
let kPowermateLedCharacteristicUUID = "847d189e-86ee-4bd2-966f-800832b1259d".uppercased()

let kPowermateKnobNotification = "kPowermateKnobNotification"
let kPowermateLEDNotification = "kPowermateLEDNotification"

let kPowermateLEDOn = "kPowermateLEDOn"
let kPowermateLEDOff = "kPowermateLEDOff"
let kPowermateLEDFlash = "kPowermateLEDFlash"
let kPowermateLEDLevel = "kPowermateLEDLevel"

// MARK: - Input States

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

final class PowermateControllerDriver: NSObject {
  @AppStorage("swapDirection") var swapDirection: Bool = false

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
            name: NSNotification.Name(kPowermateLEDNotification),
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
        CBUUID(string: kPowermateServiceUUID)
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
                name: NSNotification.Name(kPowermateKnobNotification),
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

        case kPowermateLEDOn:
            setLedOn()

        case kPowermateLEDOff:
            setLedOff()

        case kPowermateLEDFlash:
            let level = message["level"] as? Int ?? 0
            if level == 32 {
                quickBlinkLed()
            } else {
                blinkLed(atSpeed: level)
            }

        case kPowermateLEDLevel:
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
              CBUUID(string: kPowermateReadCharacteristicUUID),
              CBUUID(string: kPowermateLedCharacteristicUUID)],
                                               for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        guard let chars = service.characteristics else { return }

        for char in chars {
          let uuidString = char.uuid.uuidString.uppercased()
          if uuidString == kPowermateReadCharacteristicUUID{
                peripheral.setNotifyValue(true, for: char)
          } else if uuidString == kPowermateLedCharacteristicUUID {
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
          postScroll(delta: swapDirection ?  -1 : 1)
        } else if value == UInt8(ascii: "h") {
          postScroll(delta: swapDirection ?  1 : -1)
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
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {

        updateConnectionState(false)
        startScan()
    }
}
