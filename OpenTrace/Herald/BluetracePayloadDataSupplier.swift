import Foundation
import Herald

class BluetracePayloadDataSupplier: PayloadDataSupplier {
    private let logger: SensorLogger = ConcreteSensorLogger(subsystem: "Herald", category: "BluetracePayloadDataSupplier")
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
        EncounterMessageManager.shared.getTempId { result in
            guard let newTempId = result else {
                return
            }
            if newTempId != self.tempId {
                self.logger.debug("tempId updated (from=\(self.tempId ?? "nil"),to=\(newTempId))")
                self.tempId = newTempId
            }
        }
    }

    // MARK: - PayloadDataSupplier

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
        return BluetracePayload(tempId: tempId, modelC: DeviceInfo.getModel(), txPower: txPower, rssi: rssi).heraldPayloadData
    }

    public func legacyPayload(_ timestamp: PayloadTimestamp = PayloadTimestamp(), device: Device?) -> LegacyPayloadData? {
        guard let device = device as? BLEDevice, let rssi = device.rssi, let tempId = tempId,
              let service = UUID(uuidString: BLESensorConfiguration.interopOpenTraceServiceUUID.uuidString) else {
            return nil
        }
        do {
            let dataToWrite = CentralWriteDataV2(
                mc: DeviceInfo.getModel(),
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

    func payload(_ data: Data) -> [Herald.PayloadData] {
        var payloads: [Herald.PayloadData] = []
        var index = 0
        repeat {
            if let innerPayloadLength = data.uint16(index + 5) {
                let extractedPayload = Herald.PayloadData(data.subdata(in: index..<index+7+Int(innerPayloadLength)))
                if extractedPayload.count > 0 {
                    payloads.append(extractedPayload)
                    index += extractedPayload.count
                } else {
                    break
                }
            } else {
                break
            }
        } while(true)
        return payloads
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
            var rssi: Int8 = 0
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
