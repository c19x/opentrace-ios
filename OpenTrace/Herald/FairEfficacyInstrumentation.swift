//
//  FairEfficacyInstrumentation.swift
//
//  Copyright 2020 VMware, Inc.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import UIKit

public class FairEfficacyInstrumentation {
    // Singleton
    public static let shared = FairEfficacyInstrumentation()
    
    // Parameters
    public static var logLevel: SensorLoggerLevel = .debug
    public static var testMode: Bool = true

    // Internals
    private let logger = ConcreteSensorLogger(subsystem: "Sensor", category: "Data.FairEfficacyInstrumentation")
    private let deviceDescription = "\(UIDevice.current.name) (iOS \(UIDevice.current.systemVersion))"
    private var delegates: [SensorDelegate] = []
    
    public let payloadData: PayloadData = FairEfficacyInstrumentation.generatePayloadData()
    
    init() {
        logger.debug("device (os=\(UIDevice.current.systemName)\(UIDevice.current.systemVersion),model=\(deviceModel()))")

        // Log contacts and battery usage
        delegates.append(ContactLog(filename: "contacts.csv"))
        delegates.append(DetectionLog(filename: "detection.csv", payloadData: payloadData))
        _ = BatteryLog(filename: "battery.csv")
        
        logger.info("DEVICE (payloadPrefix=\(payloadData.shortName),description=\(deviceDescription))")
    }
    
    // MARK:- Device information and consistent payload
    
    private func deviceModel() -> String {
        var deviceInformation = utsname()
        uname(&deviceInformation)
        let mirror = Mirror(reflecting: deviceInformation.machine)
        return mirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return identifier
            }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    /// Generate unique and consistent device identifier for testing detection and tracking
    private static func generatePayloadData() -> PayloadData {
        // Generate unique identifier based on phone name
        let text = UIDevice.current.name + ":" + UIDevice.current.model + ":" + UIDevice.current.systemName + ":" + UIDevice.current.systemVersion
        var hash = UInt64 (5381)
        let buf = [UInt8](text.utf8)
        for b in buf {
            hash = 127 * (hash & 0x00ffffffffffffff) + UInt64(b)
        }
        let value = Int32(hash.remainderReportingOverflow(dividingBy: UInt64(Int32.max)).partialValue)
        // Convert identifier to data
        var mutableSelf = value.bigEndian // network byte order
        let valueAsData = Data(bytes: &mutableSelf, count: MemoryLayout.size(ofValue: mutableSelf))
        // Build HERALD compatible payload data
        var payloadData = PayloadData()
        payloadData.append(Data(repeating: 0, count: 3))
        payloadData.append(valueAsData)
        return payloadData
    }
    
    // MARK:- Intrumentation functions
    
    func instrument(encounter: EncounterRecord) {
        guard let msg = encounter.msg, let payloadData = PayloadData(base64Encoded: msg), let rssi = encounter.rssi else {
            return
        }
        let timestamp = encounter.timestamp ?? Date()
        logger.debug("instrument (encounter,timestamp=\(timestamp),payload=\(payloadData.shortName),rssi=\(rssi))")
        let targetIdentifer = msg
        let proximity = Proximity(unit: .RSSI, value: rssi)
        delegates.forEach({ $0.sensor(.BLE, didDetect: targetIdentifer) })
        delegates.forEach({ $0.sensor(.BLE, didRead: payloadData, fromTarget: targetIdentifer) })
        delegates.forEach({ $0.sensor(.BLE, didMeasure: proximity, fromTarget: targetIdentifer) })
        delegates.forEach({ $0.sensor(.BLE, didMeasure: proximity, fromTarget: targetIdentifer, withPayload: payloadData) })
    }

    
}

public typealias PayloadData = Data

public extension PayloadData {
    var shortName: String {
        guard count > 0 else {
            return ""
        }
        guard count > 3 else {
            return base64EncodedString()
        }
        return String(subdata(in: 3..<count).base64EncodedString().prefix(6))
    }
}

