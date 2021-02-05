//
//  OnboardingManager.swift
//  OpenTrace


import Foundation
import FirebaseAuth

class OnboardingManager {

    static let shared = OnboardingManager()

    func returnCurrentLaunchPage() -> String {
        // Herald test mode bypasses onboarding and authentication
        // to enable full offline operation for instrumented tests
        guard !HeraldIntegration.testMode else {
            return HeraldIntegration.onboardingManager_returnCurrentLaunchPage()
        }
        // OpenTrace
        if !completedIWantToHelp {
            return "intro"
        } else if Auth.auth().currentUser == nil {
            return "phoneNumber"
        } else if !hasConsented {
            return "consent"
        } else if !allowedPermissions {
            return "permissions"
        } else if !completedBluetoothOnboarding {
            return "turnOnBluetooth"
        } else {
            return "main"
        }
    }
}

extension OnboardingManager {

    var completedIWantToHelp: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "completedIWantToHelp")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "completedIWantToHelp")
        }
    }

    var completedBluetoothOnboarding: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "completedBluetoothOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "completedBluetoothOnboarding")
        }
    }

    var hasConsented: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "hasConsented")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasConsented")
        }
    }

    var allowedPermissions: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "allowedPermissions")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "allowedPermissions")
        }
    }
}
