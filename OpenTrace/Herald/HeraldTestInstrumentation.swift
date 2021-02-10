import Foundation
import Herald

class HeraldTestInstrumentation: SensorDelegate {
    private let logger: SensorLogger = ConcreteSensorLogger(subsystem: "Herald", category: "HeraldTestInstrumentation")
    private var delegates: [SensorDelegate] = []
    public static let payloadData = HeraldTestInstrumentation.deviceSpecificPayloadData()

    init() {
        logger.debug("device (os=\(UIDevice.current.systemName)\(UIDevice.current.systemVersion),model=\(HeraldTestInstrumentation.deviceModel()))")
        delegates.append(ContactLog(filename: "contacts.csv"))
        delegates.append(StatisticsLog(filename: "statistics.csv", payloadData: HeraldTestInstrumentation.payloadData))
        delegates.append(DetectionLog(filename: "detection.csv", payloadData: HeraldTestInstrumentation.payloadData))
        _ = BatteryLog(filename: "battery.csv")
        if BLESensorConfiguration.payloadDataUpdateTimeInterval != .never {
            delegates.append(EventTimeIntervalLog(filename: "statistics_didRead.csv", payloadData: HeraldTestInstrumentation.payloadData, eventType: .read))
        }
        logger.info("DEVICE (payloadPrefix=\(HeraldTestInstrumentation.payloadData.shortName),description=\(SensorArray.deviceDescription))")
    }

    static func deviceModel() -> String {
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
    static func deviceSpecificPayloadData() -> PayloadData {
        // Generate unique identifier based on phone name
        let text = UIDevice.current.name + ":" + UIDevice.current.model + ":" + UIDevice.current.systemName + ":" + UIDevice.current.systemVersion
        var hash = UInt64(5381)
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

    /// Parse payload data to distinguish legacy OpenTrace payload (JSON) and
    /// Herald encoded OpenTrace payload (binary).
    func parsePayloadData(_ payloadData: PayloadData) -> PayloadData? {
        if payloadData is LegacyPayloadData {
            return payloadData
        }
        guard let bluetracePayload = BluetracePayload.parse(heraldPayloadData: payloadData),
              let embeddedPayloadData = Herald.PayloadData(base64Encoded: bluetracePayload.tempId) else {
            return nil
        }
        return embeddedPayloadData
    }

    // MARK: - SensorDelegate

    func sensor(_ sensor: SensorType, didUpdateState: SensorState) {
        logger.debug("\(sensor.rawValue),didUpdateState=\(didUpdateState.rawValue)")
        delegates.forEach({ $0.sensor(sensor, didUpdateState: didUpdateState) })
    }

    func sensor(_ sensor: SensorType, didDetect: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didDetect=\(didDetect.description)")
        delegates.forEach({ $0.sensor(sensor, didDetect: didDetect) })
    }

    func sensor(_ sensor: SensorType, didRead: PayloadData, fromTarget: TargetIdentifier) {
        guard let payloadData = parsePayloadData(didRead) else {
            logger.fault("\(sensor.rawValue),didRead=\(didRead.base64EncodedString()),fromTarget=\(fromTarget.description),error=failedToParse")
            return
        }
        logger.debug("\(sensor.rawValue),didRead=\(payloadData.shortName),fromTarget=\(fromTarget.description)")
        delegates.forEach({ $0.sensor(sensor, didRead: payloadData, fromTarget: fromTarget) })
    }

    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description)")
        delegates.forEach({ $0.sensor(sensor, didMeasure: didMeasure, fromTarget: fromTarget) })
    }

    func sensor(_ sensor: SensorType, didShare: [PayloadData], fromTarget: TargetIdentifier) {
        let didSharePayloadData: [PayloadData] = didShare.map({
            if let payloadData = parsePayloadData($0) {
                return payloadData
            } else {
                return $0
            }
        })
        logger.debug("\(sensor.rawValue),didShare=\(didSharePayloadData.description),fromTarget=\(fromTarget.description)")
        delegates.forEach({ $0.sensor(sensor, didShare: didSharePayloadData, fromTarget: fromTarget) })
    }

    func sensor(_ sensor: SensorType, didVisit: Location?) {
        logger.debug("\(sensor.rawValue),didVisit=\(String(describing: didVisit))")
        delegates.forEach({ $0.sensor(sensor, didVisit: didVisit) })
    }

    func sensor(_ sensor: SensorType, didReceive: Data, fromTarget: TargetIdentifier) {
        logger.debug("\(sensor.rawValue),didReceive=\(didReceive.description),fromTarget=\(fromTarget.description)")
        delegates.forEach({ $0.sensor(sensor, didReceive: didReceive, fromTarget: fromTarget) })
    }

    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: PayloadData) {
        guard let payloadData = parsePayloadData(withPayload) else {
            logger.fault("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(withPayload.base64EncodedString()),error=failedToParse")
            return
        }
        logger.debug("\(sensor.rawValue),didMeasure=\(didMeasure.description),fromTarget=\(fromTarget.description),withPayload=\(payloadData.shortName)")
        delegates.forEach({ $0.sensor(sensor, didMeasure: didMeasure, fromTarget: fromTarget, withPayload: payloadData) })
    }
}
