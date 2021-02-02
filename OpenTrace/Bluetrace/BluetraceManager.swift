import UIKit
import CoreData
import CoreBluetooth
import Herald

/// Bluetrace protocol powered by Herald
class BluetraceManager: SensorDelegate {
    /// Bluetrace singleton
    static let shared = BluetraceManager()
    /// Bluetrace callback for BLE state update
    /// - Using adapter to trigger callback from SensorDelegate:didUpdateState calls
    var bluetoothDidUpdateStateCallback: ((CBManagerState) -> Void)?

    // MARK:- Herald integration
    private let logger: SensorLogger = ConcreteSensorLogger(subsystem: "HeraldIntegration", category: "BluetraceManager")
    // Herald sensor array and externalising state to support Bluetrace manager callback
    private let sensorArray: SensorArray
    private var sensorArrayState: CBManagerState = .poweredOff
    
    // Enable test mode that uses a fixed payload for instrumentation
    public static var testMode: Bool = true
    private let testPayloadData: PayloadData = BluetraceManager.testPayloadData()
    private var testDelegates: [SensorDelegate] = []

    private init() {
        sensorArray = SensorArray(BluetracePayloadDataSupplier())
        sensorArray.add(delegate: self)
        // Add logging delegates if test mode is enabled
        if BluetraceManager.testMode {
            testDelegates.append(ContactLog(filename: "contacts.csv"))
            testDelegates.append(StatisticsLog(filename: "statistics.csv", payloadData: testPayloadData))
            testDelegates.append(DetectionLog(filename: "detection.csv", payloadData: testPayloadData))
            _ = BatteryLog(filename: "battery.csv")
            if BLESensorConfiguration.payloadDataUpdateTimeInterval != .never {
                testDelegates.append(EventTimeIntervalLog(filename: "statistics_didRead.csv", payloadData: testPayloadData, eventType: .read))
            }
        }
        logger.debug("device (os=\(UIDevice.current.systemName)\(UIDevice.current.systemVersion),model=\(deviceModel()))")
        logger.info("DEVICE (payloadPrefix=\(testPayloadData.shortName),description=\(SensorArray.deviceDescription))")
    }
    
    // MARK:- Bluetrace manager API

    func initialConfiguration() {

    }

    func presentBluetoothAlert(_ bluetoothStateString: String) {
        #if DEBUG
        let alert = UIAlertController(title: "Bluetooth Issue: "+bluetoothStateString+" on "+DeviceInfo.getModel()+" iOS: "+UIDevice.current.systemVersion, message: "Please screenshot this message and send to support!", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))

        DispatchQueue.main.async {
            var topController: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
            while topController?.presentedViewController != nil {
                topController = topController?.presentedViewController
            }

            topController?.present(alert, animated: true)
        }
        #endif

        #if RELEASE
        let alert = UIAlertController(title: "App restart required for Bluetooth to restart!", message: "Press Ok to exit the app!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (_) in
            exit(0)
        }))
        DispatchQueue.main.async {
            var topController: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
            while topController?.presentedViewController != nil {
                topController = topController?.presentedViewController
            }

            if topController!.isKind(of: UIAlertController.self) {
                print("Alert has already popped up!")
            } else {
                topController?.present(alert, animated: true)
            }

        }
        #endif
    }

    func turnOn() {
        logger.debug("turnOn")
        sensorArray.start()
    }

    func turnOff() {
        logger.debug("turnOff")
        sensorArray.stop()
    }

    func getCentralStateText() -> String {
        return BluetraceUtils.managerStateToString(sensorArrayState)
    }

    func getPeripheralStateText() -> String {
        return BluetraceUtils.managerStateToString(sensorArrayState)
    }

    func isBluetoothAuthorized() -> Bool {
        if #available(iOS 13.1, *) {
            return CBManager.authorization == .allowedAlways
        } else {
            // todo: consider iOS 13.0, which has different behavior from 13.1 onwards
            return CBPeripheralManager.authorizationStatus() == .authorized
        }
    }

    func isBluetoothOn() -> Bool {
        switch sensorArrayState {
        case .poweredOff:
            print("Bluetooth is off")
        case .resetting:
            presentBluetoothAlert("Resetting State")
        case .unauthorized:
            presentBluetoothAlert("Unauth State")
        case .unknown:
            presentBluetoothAlert("Unknown State")
        case .unsupported:
            presentBluetoothAlert("Unsupported State")
        default:
            print("Bluetooth is on")
        }
        return sensorArrayState == .poweredOn

    }

    func centralDidUpdateStateCallback(_ state: CBManagerState) {
        bluetoothDidUpdateStateCallback?(state)
    }

    func toggleAdvertisement(_ state: Bool) {
        // ** This is handled internally in HERALD **
        // See "BLESensorConfiguration.advertRestartTimeInterval"
    }

    func toggleScanning(_ state: Bool) {
        // ** This is handled internally in HERALD **
        // Scanning is performed as frequently as possible to
        // support accurate distance and duration estimation
    }
    
    // MARK:- SensorDelegate
    
    func sensor(_ sensor: SensorType, didUpdateState: SensorState) {
        logger.debug("\(sensor.rawValue),didUpdateState=\(didUpdateState.rawValue)")
        switch didUpdateState {
        case .on:
            sensorArrayState = .poweredOn
            break
        default:
            sensorArrayState = .poweredOff
            break
        }
        bluetoothDidUpdateStateCallback?(self.sensorArrayState)
        testDelegates.forEach({ $0.sensor(sensor, didUpdateState: didUpdateState) })
    }
    
    func sensor(_ sensor: SensorType, didDetect: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didDetect=\(didDetect.description)")
        testDelegates.forEach({ $0.sensor(sensor, didDetect: didDetect) })
    }
    
    func sensor(_ sensor: SensorType, didRead: PayloadData, fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didRead=\(didRead.base64EncodedString()),fromTarget=\(fromTarget.description)")
        guard let bluetracePayload = BluetracePayload.parse(heraldPayloadData: didRead),
              let testPayloadData = Herald.PayloadData(base64Encoded: bluetracePayload.tempId) else {
            logger.fault("parse payload failed \(didRead.base64EncodedString()))")
            return
        }
        logger.debug("\(sensor.rawValue),didRead=\(testPayloadData.shortName),fromTarget=\(fromTarget.description)")
        testDelegates.forEach({ $0.sensor(sensor, didRead: testPayloadData, fromTarget: fromTarget) })
    }
    
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description)")
        testDelegates.forEach({ $0.sensor(sensor, didMeasure: didMeasure, fromTarget: fromTarget) })
    }
        
    func sensor(_ sensor: SensorType, didShare: [PayloadData], fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didShare=\(didShare.description),fromTarget=\(fromTarget.description)")
        testDelegates.forEach({ $0.sensor(sensor, didShare: didShare, fromTarget: fromTarget) })
    }
    
    func sensor(_ sensor: SensorType, didVisit: Location?) {
        logger.debug("\(sensor.rawValue),didVisit=\(String(describing: didVisit))")
        testDelegates.forEach({ $0.sensor(sensor, didVisit: didVisit) })
    }
    
    func sensor(_ sensor: SensorType, didReceive: Data, fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didReceive=\(didReceive.description),fromTarget=\(fromTarget.description)")
        testDelegates.forEach({ $0.sensor(sensor, didReceive: didReceive, fromTarget: fromTarget) })
    }
    
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: Herald.PayloadData) {
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(withPayload.base64EncodedString())")
        guard didMeasure.unit == .RSSI else {
            return
        }
        guard let bluetracePayload = BluetracePayload.parse(heraldPayloadData: withPayload) else {
            logger.fault("parse payload failed \(withPayload.base64EncodedString()))")
            return
        }
        let rssi = didMeasure.value
        let txPower = (didMeasure.calibration?.unit == .BLETransmitPower ? didMeasure.calibration?.value ?? 0 : 0)
        let centralWriteDataV2 = CentralWriteDataV2(
            mc: bluetracePayload.modelC,
            rs: rssi,
            id: bluetracePayload.tempId,
            o: BluetraceConfig.OrgID,
            v: BluetraceConfig.ProtocolVersion)
        var encounterRecord = EncounterRecord(from: centralWriteDataV2)
        encounterRecord.txPower = txPower
        encounterRecord.saveToCoreData()
        guard let testPayloadData = Herald.PayloadData(base64Encoded: bluetracePayload.tempId) else {
            logger.fault("parse payload failed \(bluetracePayload.tempId))")
            return
        }
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(testPayloadData.shortName)")
        testDelegates.forEach({ $0.sensor(sensor, didMeasure: didMeasure, fromTarget: fromTarget, withPayload: testPayloadData) })
    }
    
    // MARK:- Test mode functions
    
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
    public static func testPayloadData() -> PayloadData {
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
        let payloadData = PayloadData()
        payloadData.append(Data(repeating: 0, count: 3))
        payloadData.append(valueAsData)
        return payloadData
    }
}

class BluetracePayloadDataSupplier: PayloadDataSupplier {
    private let logger: SensorLogger = ConcreteSensorLogger(subsystem: "HeraldIntegration", category: "BluetracePayloadDataSupplier")
    private let deviceModel = DeviceInfo.getModel()
    private var tempId: String?

    init() {
        // Bluetrace uses async method for getting tempId, whereas Herald expects
        // sync method for getting payload, so running timer task to pre-fetch
        // tempId at regular interval, ready for Herald. This wouldn't normally
        // work because the timer will become idle as the app is moved to background
        // but Herald is able to keep the app awake.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            self.updateTempId()
        }
    }
    
    // Update tempID at regular intervals for use by payload data supplier
    private func updateTempId() {
        EncounterMessageManager.shared.getTempId() { result in
            guard let newTempId = result else {
                return
            }
            if newTempId != self.tempId {
                self.logger.debug("tempId updated (from=\(self.tempId ?? "nil"),to=\(newTempId))")
                self.tempId = newTempId
            }
        }
    }
        
    // MARK:- PayloadDataSupplier
    
    func payload(_ timestamp: PayloadTimestamp, device: Device?) -> Herald.PayloadData? {
        // Get tempId
        guard let tempId = tempId else {
            logger.fault("payload, missing tempId")
            return nil
        }
        // Get device TX power, or use 0
        let txPower = UInt16((device as? BLEDevice)?.txPower ?? 0)
        // Get device RSSI, or use 0
        let rssi = Int8((device as? BLEDevice)?.rssi ?? 0)
        // Get Herald encoded Bluetrace payload
        return BluetracePayload(tempId: tempId, modelC: deviceModel, txPower: txPower, rssi: rssi).heraldPayloadData
    }
    
    func payload(_ data: Data) -> [Herald.PayloadData] {
        var payloads: [Herald.PayloadData] = []
        var index = 0
        repeat {
            if let extractedPayload = nextPayload(index: index, data: data) {
                payloads.append(extractedPayload)
                index += extractedPayload.count
            } else {
                break
            }
        } while(true)
        return payloads
    }
    
    private func nextPayload(index: Int, data: Data) -> Herald.PayloadData? {
        guard let innerPayloadLength = data.uint16(index + 5) else {
            return nil
        }
        return Herald.PayloadData(data.subdata(in: index..<index+7+Int(innerPayloadLength)))
    }

    public func legacyPayload(_ timestamp: PayloadTimestamp = PayloadTimestamp(), device: Device?) -> LegacyPayloadData? {
        guard let device = device as? BLEDevice, let rssi = device.rssi, let tempId = tempId,
              let service = UUID(uuidString: BLESensorConfiguration.interopOpenTraceServiceUUID.uuidString) else {
            return nil
        }
        do {
            let dataToWrite = CentralWriteDataV2(
                mc: deviceModel,
                rs: Double(rssi),
                id: tempId,
                o: BluetraceConfig.OrgID,
                v: BluetraceConfig.ProtocolVersion)
            let encodedData = try JSONEncoder().encode(dataToWrite)
            let legacyPayloadData = LegacyPayloadData(service: service, data: encodedData)
            return legacyPayloadData
        } catch {
        }
        return nil
    }
}


struct HeraldEnvelopeHeader {
    let protocolAndVersion: UInt8
    let countryCode: UInt16
    let stateCode: UInt16
    
    var data: Data {
        var headerData = Data()
        headerData.append(protocolAndVersion)
        headerData.append(countryCode)
        headerData.append(stateCode)
        return headerData
    }
}


struct BluetracePayload {
    let tempId: String
    let modelC: String
    let txPower: UInt16
    let rssi: Int8
    
    static let header = HeraldEnvelopeHeader(
        protocolAndVersion: 0x91,
        countryCode: 124,
        stateCode: 48
    )

    var heraldPayloadData: Herald.PayloadData {
        let payloadData = Herald.PayloadData()
        payloadData.append(BluetracePayload.header.data)
        var innerData = Data()
        _ = innerData.append(tempId, StringLengthEncodingOption.UINT16)
        let extendedData = ConcreteExtendedDataV1()
        extendedData.addSection(code: 0x40, value: rssi)
        extendedData.addSection(code: 0x41, value: txPower)
        extendedData.addSection(code: 0x42, value: modelC)
        innerData.append(extendedData.payload()!.data)
        payloadData.append(UInt16(innerData.count))
        payloadData.append(innerData)
        return payloadData
    }
    
    static func parse(heraldPayloadData: Herald.PayloadData) -> BluetracePayload? {
        if heraldPayloadData.subdata(in: 0..<5) == header.data, let tempIdLength = heraldPayloadData.data.uint16(7) {
            let decodedTempId = heraldPayloadData.data
                .string(7, StringLengthEncodingOption.UINT16)?.value ?? ""
            var modelC = ""
            var rssi: Int8 = 0;
            var txPower: UInt16 = 0
            let extendedData = ConcreteExtendedDataV1(Herald.PayloadData(heraldPayloadData.subdata(in: (9+Int(tempIdLength))..<heraldPayloadData.count)))
            for section in extendedData.getSections() {
                switch section.code {
                case 0x40:
                    rssi = section.data.int8(0)!
                case 0x41:
                    txPower = section.data.uint16(0)!
                case 0x42:
                    modelC = String(decoding: section.data, as: UTF8.self)
                default:
                    break
                }
            }
            return BluetracePayload(tempId: decodedTempId, modelC: modelC, txPower: txPower, rssi: rssi)
        }
        return nil
    }
}
