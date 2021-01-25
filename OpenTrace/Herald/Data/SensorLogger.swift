//
//  Logger.swift
//
//  Copyright 2020 VMware, Inc.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import UIKit
import os

protocol SensorLogger {
    init(subsystem: String, category: String)
    
    func log(_ level: SensorLoggerLevel, _ message: String)
    
    func debug(_ message: String)
    
    func info(_ message: String)
    
    func fault(_ message: String)
}

public enum SensorLoggerLevel: String {
    case off, debug, info, fault
}

class ConcreteSensorLogger: NSObject, SensorLogger {
    private let subsystem: String
    private let category: String
    private let dateFormatter = DateFormatter()
    private let log: OSLog?
    private static let logFile = TextFile(filename: "log.txt")
    
    required init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if #available(iOS 10.0, *) {
            log = OSLog(subsystem: subsystem, category: category)
        } else {
            log = nil
        }
    }
    
    private func suppress(_ level: SensorLoggerLevel) -> Bool {
        if (FairEfficacyInstrumentation.logLevel == .off) {
            return true
        }
        switch level {
        case .debug:
            return (FairEfficacyInstrumentation.logLevel == .info || FairEfficacyInstrumentation.logLevel == .fault)
        case .info:
            return (FairEfficacyInstrumentation.logLevel == .fault)
        default:
            return false
        }
    }
    
    func log(_ level: SensorLoggerLevel, _ message: String) {
        guard !suppress(level) else {
            return
        }
        // Write to unified os log if available, else print to console
        let timestamp = dateFormatter.string(from: Date())
        let csvMessage = message.replacingOccurrences(of: "\"", with: "'")
        let quotedMessage = (message.contains(",") ? "\"" + csvMessage + "\"" : csvMessage)
        let entry = timestamp + "," + level.rawValue + "," + subsystem + "," + category + "," + quotedMessage
        ConcreteSensorLogger.logFile.write(entry)
        guard let log = log else {
            print(entry)
            return
        }
        if #available(iOS 10.0, *) {
            switch (level) {
            case .debug:
                os_log("%s", log: log, type: .debug, message)
            case .info:
                os_log("%s", log: log, type: .info, message)
            case .fault:
                os_log("%s", log: log, type: .fault, message)
            default:
                return
            }
            return
        }
    }
    
    func debug(_ message: String) {
        log(.debug, message)
    }
    
    func info(_ message: String) {
        log(.info, message)
    }
    
    func fault(_ message: String) {
        log(.fault, message)
    }
    
}
