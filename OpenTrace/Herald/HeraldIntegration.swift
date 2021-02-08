import Foundation
import CoreBluetooth
import Herald

class HeraldIntegration: SensorDelegate {
    private let logger: SensorLogger = ConcreteSensorLogger(subsystem: "Herald", category: "HeraldIntegration")
    private let bluetraceManager: BluetraceManager
    private let sensorArray: SensorArray
    private var sensorArrayState: SensorState = .off
    public var cbManagerState: CBManagerState { get {
        return sensorArrayState == .on ? .poweredOn : .poweredOff
    }}

    /// Enable test mode for evaluation with fair efficacy formula
    public static var testMode = true

    init(_ bluetraceManager: BluetraceManager) {
        // Enable callback to bluetraceManager.bluetoothDidUpdateStateCallback
        // on sensor:didUpdateState events
        self.bluetraceManager = bluetraceManager
        if HeraldIntegration.testMode {
            logger.info("test mode enabled")
        }
        // Enable interoperability with devices running legacy OpenTrace only protocol
        BLESensorConfiguration.interopOpenTraceEnabled = false
        if BLESensorConfiguration.interopOpenTraceEnabled {
            BLESensorConfiguration.interopOpenTraceServiceUUID = BluetraceConfig.BluetoothServiceID
            BLESensorConfiguration.interopOpenTracePayloadCharacteristicUUID = BluetraceConfig.CharacteristicServiceIDv2
            logger.info("interop enabled (protocol=OpenTrace,serviceUUID=\(BLESensorConfiguration.interopOpenTraceServiceUUID),characteristicUUID=\(BLESensorConfiguration.interopOpenTracePayloadCharacteristicUUID))")
        }
        // Enable OpenTrace protocol running over Herald transport
        sensorArray = SensorArray(BluetracePayloadDataSupplier())
        sensorArray.add(delegate: self)
        // Enable test mode intrumentation
        if HeraldIntegration.testMode {
            sensorArray.add(delegate: HeraldTestInstrumentation())
        }
    }

    // MARK: - SensorDelegate

    func sensor(_ sensor: SensorType, didUpdateState: SensorState) {
        logger.debug("\(sensor.rawValue),didUpdateState=\(didUpdateState.rawValue)")
        sensorArrayState = didUpdateState
        bluetraceManager.bluetoothDidUpdateStateCallback?(cbManagerState)
    }

    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: Herald.PayloadData) {
        guard didMeasure.unit == .RSSI else {
            return
        }
        if let interopPayload = withPayload as? LegacyPayloadData {
            if interopPayload.protocolName == .OPENTRACE {
                handleOpenTracePayload(sensor, didMeasure: didMeasure, fromTarget: fromTarget, withPayload: interopPayload)
            }
        } else {
            handleHeraldPayload(sensor, didMeasure: didMeasure, fromTarget: fromTarget, withPayload: withPayload)
        }
    }
    
    // MARK: - Interoperability
    
    func handleHeraldPayload(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: Herald.PayloadData) {
        guard let bluetracePayload = BluetracePayload.parse(heraldPayloadData: withPayload) else {
            logger.fault("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(withPayload.base64EncodedString()),protocol=herald,error=failedToParse")
            return
        }
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(withPayload.base64EncodedString()),protocol=herald")
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
    }

    func handleOpenTracePayload(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: LegacyPayloadData) {
        let rssi = didMeasure.value
        let txPower = (didMeasure.calibration?.unit == .BLETransmitPower ? didMeasure.calibration?.value ?? 0 : 0)
        if let centralWriteDataV2 = try? JSONDecoder().decode(CentralWriteDataV2.self, from: withPayload.data),
           let payloadData = PayloadData(base64Encoded: centralWriteDataV2.id) {
            logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(payloadData.shortName),protocol=openTrace,format=centralWriteDataV2")
            var encounterRecord = EncounterRecord(from: centralWriteDataV2)
            encounterRecord.txPower = txPower
            encounterRecord.saveToCoreData()
            return
        }
        if let peripheralCharacteristicsDataV2 = try? JSONDecoder().decode(PeripheralCharacteristicsDataV2.self, from: withPayload.data),
           let payloadData = PayloadData(base64Encoded: peripheralCharacteristicsDataV2.id) {
            logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(payloadData.shortName),protocol=openTrace,format=peripheralCharacteristicsDataV2")
            let centralWriteDataV2 = CentralWriteDataV2(
                mc: peripheralCharacteristicsDataV2.mp,
                rs: rssi,
                id: peripheralCharacteristicsDataV2.id,
                o: peripheralCharacteristicsDataV2.o,
                v: peripheralCharacteristicsDataV2.v)
            // TODO : Check mp and mc correctness in encounter record
            var encounterRecord = EncounterRecord(from: centralWriteDataV2)
            encounterRecord.txPower = txPower
            encounterRecord.saveToCoreData()
            return
        }
        logger.fault("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(withPayload.base64EncodedString()),protocol=openTrace,error=failedToParse")
    }

    // MARK: - OpenTrace replacement functions for normal operation

    func bluetraceManager_turnOn() {
        logger.debug("bluetraceManager_turnOn")
        sensorArray.start()
    }

    func bluetraceManager_turnOff() {
        logger.debug("bluetraceManager_turnOff")
        sensorArray.stop()
    }

    // MARK: - OpenTrace replacement functions for test mode operation

    /// OnboardingManager returnCurrentLaunchPage will always return "main"
    /// to bypass user authentication and onboarding, enabling full offline operation
    /// for instrumented tests.
    static func onboardingManager_returnCurrentLaunchPage() -> String {
        OnboardingManager.shared.completedIWantToHelp = true
        OnboardingManager.shared.hasConsented = true
        OnboardingManager.shared.completedBluetoothOnboarding = true
        if !OnboardingManager.shared.allowedPermissions {
            return "permissions"
        } else {
            return "main"
        }
    }

    /// EncounterMessageManager fetchTempIdFromFirebase will always return fixed
    /// payload data to enable evaluation with fair efficacy formula
    static func encounterMessageManager_fetchTempIdFromFirebase(onComplete: ((Error?, (String, Date)?) -> Void)?) {
        onComplete?(nil, (HeraldTestInstrumentation.payloadData.base64EncodedString(), Date.distantFuture))
    }

    /// EncounterMessageManager fetchTempIdsFromFirebase will always return fixed
    /// payload data to enable evaluation with fair efficacy formula
    static func encounterMessageManager_fetchBatchTempIdsFromFirebase(onComplete: ((Error?, ([[String: Any]], Date)?) -> Void)?) {
        var tempId: [String: Any] = [:]
        tempId["expiryTime"] = Date.distantFuture
        tempId["tempID"] = HeraldTestInstrumentation.payloadData.base64EncodedString()
        let tempIds: [[String: Any]] = [tempId]
        onComplete?(nil, (tempIds, Date.distantFuture))
    }
}
