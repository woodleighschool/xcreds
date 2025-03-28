//
//  LicenseChecker.swift
//  XCreds
//
//  Created by Timothy Perfitt on 3/28/23.
//

import Cocoa

class LicenseChecker: NSObject {
    enum LicenseState {
        case valid(Int)
        case invalid
        case trial(Int)
        case trialExpired
        case expired

    }

    func currentLicenseState() -> LicenseState {
        let trialDays = 14

        if UserDefaults.standard.value(forKey: "tts") == nil {
            UserDefaults.standard.setValue(Date(), forKey: "tts")
        }
        let firstLaunchDate = UserDefaults.standard.value(forKey: "tts") as? Date

        let check = TCSLicenseCheck()
        let status = check.checkLicenseStatus("com.twocanoes.xcreds", withExtension: "")
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFractionalSeconds, .withFullDate]

        return .valid(0)

    }

}
