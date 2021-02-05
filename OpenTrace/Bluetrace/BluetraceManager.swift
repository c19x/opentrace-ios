import UIKit
import CoreData
import CoreBluetooth
import FirebaseAuth

/// Bluetrace protocol powered by Herald
class BluetraceManager {
    /// Bluetrace singleton
    static let shared = BluetraceManager()
    /// Bluetrace callback for BLE state update
    /// - Using adapter to trigger callback from SensorDelegate:didUpdateState calls
    var bluetoothDidUpdateStateCallback: ((CBManagerState) -> Void)?
    private var heraldIntegration: HeraldIntegration!

    private init() {
        heraldIntegration = HeraldIntegration(self)
    }

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
        heraldIntegration.bluetraceManager_turnOn()
    }

    func turnOff() {
        heraldIntegration.bluetraceManager_turnOff()
    }

    func getCentralStateText() -> String {
        return BluetraceUtils.managerStateToString(heraldIntegration.cbManagerState)
    }

    func getPeripheralStateText() -> String {
        return BluetraceUtils.managerStateToString(heraldIntegration.cbManagerState)
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
        switch heraldIntegration.cbManagerState {
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
        return heraldIntegration.cbManagerState == .poweredOn
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
}
