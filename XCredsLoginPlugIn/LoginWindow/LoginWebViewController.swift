//
//  WebView.swift
//  xCreds
//
//  Created by Timothy Perfitt on 4/5/22.
//

import Foundation
import Cocoa
import WebKit
import OIDCLite
import OpenDirectory

class LoginWebViewController: WebViewController, DSQueryable {

    let uiLog = "uiLog"
//    var internalDelegate:XCredsMechanismProtocol?
    var mechanismDelegate:XCredsMechanismProtocol?
//    }
    var loginProgressWindowController:LoginProgressWindowController?
    @IBOutlet weak var backgroundImageView: NSImageView!

    override func viewDidAppear() {
        TCSLogWithMark("loading page")
        loadPage()

    }


    override func showErrorMessageAndDeny(_ message:String){

            mechanismDelegate?.denyLogin(message:message)
            return
        }

    
//    override func tokenError(_ err: String) {
//        TCSLogErrorWithMark("authFailure: \(err)")
//        //TODO: need to post this?
//        NotificationCenter.default.post(name: Notification.Name("TCSTokensUpdated"), object: self, userInfo:[:])
//
//    }

//    override func setHints(_ hints: [HintType : Any]) {
//        mechanismDelegate?.setHints(hints)
//
//    }
//
//    override func setContextStrings(_ contentStrings: [String : String]) {
//        mechanismDelegate?.setContextStrings(contentStrings)
//    }
    override func credentialsUpdated(_ credentials:Creds){
        //if we have tokens, that means that authentication was successful.
         //we have to check the password here so we can prompt.

        var username:String?
        var passwordHintSet = false
        guard let mechanismDelegate = mechanismDelegate else {
            TCSLogErrorWithMark("invalid mechanism delegate")
            return
        }
        let defaultsUsername = DefaultsOverride.standardOverride.string(forKey: PrefKeys.username.rawValue)

        guard let idToken = credentials.idToken else {
            TCSLogErrorWithMark("invalid idToken")
            mechanismDelegate.denyLogin(message:"The identity token is invalid")
            return
        }

        let array = idToken.components(separatedBy: ".")

        if array.count != 3 {
            TCSLogErrorWithMark("idToken is invalid")

            mechanismDelegate.denyLogin(message:"The identity token is incorrect length.")
        }
        let body = array[1]
        TCSLogWithMark("base64 encoded IDToken: \(body)");
        guard let data = base64UrlDecode(value:body ) else {
            TCSLogErrorWithMark("error decoding id token base64")

            mechanismDelegate.denyLogin(message:"The identity token could not be decoded from base64.")
            return
        }
        if let decodedTokenString = String(data: data, encoding: .utf8) {
            TCSLogWithMark("IDToken:\(decodedTokenString)")

        }
        let decoder = JSONDecoder()
        var idTokenObject:IDToken
        do {
            idTokenObject = try decoder.decode(IDToken.self, from: data)

        }
        catch {
            TCSLogErrorWithMark("error decoding idtoken::")
            TCSLogErrorWithMark("Token:\(body)")

            mechanismDelegate.denyLogin(message:"The identity token could not be decoded from json.")
            return

        }

        let idTokenInfo = jwtDecode(value: idToken)  //dictionary for mapping
        guard let idTokenInfo = idTokenInfo else {

            mechanismDelegate.denyLogin(message:"No idTokenInfo found.")
            return
        }

        //groups
        if let mapValue = idTokenInfo["groups"] as? Array<String> {
            TCSLogWithMark("setting groups: \(mapValue)")
            mechanismDelegate.setHint(type: .groups, hint:mapValue)
        }
        else {

            TCSLogWithMark("No groups found")
        }


        guard let subValue = idTokenInfo["sub"] as? String, let issuerValue = idTokenInfo["iss"] as? String else {

            mechanismDelegate.denyLogin(message:"OIDC token does not contain both a sub and iss value.")
            return

        }
        let standardUsers = try? getAllStandardUsers()
        let existingUser = try? getUserRecord(sub: subValue, iss: issuerValue)

        let aliasClaim = DefaultsOverride.standardOverride.string(forKey: PrefKeys.aliasName.rawValue)
        if let aliasClaim = aliasClaim, let aliasClaimValue = idTokenInfo[aliasClaim] {
            TCSLogWithMark("found alias claim: \(aliasClaim):\(aliasClaimValue)")

            mechanismDelegate.setHint(type: .aliasName, hint: aliasClaimValue)
        }
        else {
            TCSLogWithMark("no alias claim: \(aliasClaim ?? "none")")
        }

        let shouldPromptForMigration = DefaultsOverride.standardOverride.bool(forKey: PrefKeys.shouldPromptForMigration.rawValue)

        if  let existingUser = existingUser, let odUsername = existingUser.recordName  {
                TCSLogWithMark("prior local user found. using.")
                username = odUsername
        }
        else if let standardUsers = standardUsers, standardUsers.count>0, shouldPromptForMigration == true, let password = password {

            TCSLogWithMark("Preference set to prompt for migration and there are no standard users, so prompting")

            switch SelectLocalAccountWindowController.selectLocalAccountAndUpdate(newPassword: password) {

            case .successful(let userAccountSelected):
                username = userAccountSelected
            case .canceled:
                TCSLogWithMark("User cancelled. closing")
                return
            case .createNewAccount:
                break;
            case .error(let errorMessage):
                TCSLogWithMark("error:\(errorMessage)")

                return
            }
        }
        if username == nil {
            // username static map
            if let defaultsUsername = defaultsUsername {
                username = defaultsUsername
            }
            else if let mapKey = DefaultsOverride.standardOverride.object(forKey: "map_username")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String, let leftSide = mapValue.components(separatedBy: "@").first{

                username = leftSide.replacingOccurrences(of: " ", with: "_").stripped
                TCSLogWithMark("mapped username found: \(mapValue) clean version:\(username ?? "")")
            }
            else {
                var emailString:String

                if let email = idTokenObject.email  {
                    emailString=email.lowercased()
                }
                else if let uniqueName=idTokenObject.unique_name {
                    emailString=uniqueName
                }

                else {
                    TCSLogWithMark("no username found. Using sub.")
                    emailString=idTokenObject.sub
                }
                guard let tUsername = emailString.components(separatedBy: "@").first?.lowercased() else {
                    TCSLogErrorWithMark("email address invalid")

                    mechanismDelegate.denyLogin(message:"The email address from the identity token is invalid")
                    return

                }

                TCSLogWithMark("username found: \(tUsername)")
                username = tUsername
            }

            //full name
            TCSLogWithMark("checking map_fullname")

            if let mapKey = DefaultsOverride.standardOverride.object(forKey: "map_fullname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
                //we have a mapping so use that.
                TCSLogWithMark("full name mapped to: \(mapKey)")

                mechanismDelegate.setHint(type: .fullName, hint: "\(mapValue)")

            }

            else if let firstName = idTokenObject.given_name, let lastName = idTokenObject.family_name {
                TCSLogWithMark("firstName: \(firstName)")
                TCSLogWithMark("lastName: \(lastName)")
                mechanismDelegate.setHint(type: .fullName, hint: "\(firstName) \(lastName)")

            }

            //first name
            if let mapKey = DefaultsOverride.standardOverride.object(forKey: "map_firstname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
                //we have a mapping for username, so use that.
                TCSLogWithMark("first name mapped to: \(mapKey)")


                mechanismDelegate.setHint(type: .firstName, hint:mapValue)
            }

            else if let firstName = idTokenObject.given_name {
                TCSLogWithMark("firstName from token: \(firstName)")

                mechanismDelegate.setHint(type: .firstName, hint:firstName)

            }
            //last name
            TCSLogWithMark("checking map_lastname")

            if let mapKey = DefaultsOverride.standardOverride.object(forKey: "map_lastname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
                //we have a mapping for lastName, so use that.
                TCSLogWithMark("last name mapped to: \(mapKey)")

                mechanismDelegate.setHint(type: .lastName, hint:mapValue)
            }

            else if let lastName = idTokenObject.family_name {
                TCSLogWithMark("lastName from token: \(lastName)")

                mechanismDelegate.setHint(type: .lastName, hint:lastName)

            }
        }
        guard let username = username, let password = password, password.count>0 else {
            TCSLogErrorWithMark("username or password are not set")

            mechanismDelegate.denyLogin(message:"username or password are not set")
            return
        }
        if passwordHintSet == false {

            TCSLogWithMark("checking local password for username:\(username) and password length: \(password.count)");

            let  passwordCheckStatus =  PasswordUtils.isLocalPasswordValid(userName: username, userPass: password)

            switch passwordCheckStatus {
            case .success:
                TCSLogWithMark("Local password matches cloud password ")
            case .incorrectPassword:

                TCSLogWithMark("Sync password called.")

                let promptPasswordWindowController = VerifyLocalPasswordWindowController()

                promptPasswordWindowController.showResetText=true
                promptPasswordWindowController.showResetButton=true

                switch  promptPasswordWindowController.promptForLocalAccountAndChangePassword(username: username, newPassword: password, shouldUpdatePassword: true) {

                case .success(_):
                    mechanismDelegate.allowLogin()

                case .resetKeychainRequested(let usernamePasswordCredentials):
                    if let adminUsername = usernamePasswordCredentials?.username, let adminPassword = usernamePasswordCredentials?.password {
                        mechanismDelegate.setHint(type: .adminUsername, hint:adminUsername )
                        mechanismDelegate.setHint(type: .adminPassword, hint: adminPassword)
                        mechanismDelegate.setHint(type: .passwordOverwrite, hint: true)

                    }
                    mechanismDelegate.allowLogin()


                case .userCancelled:
                    loadPage()
                    return
                case .error(let errMsg):
                    TCSLogWithMark("Error prompting: \(errMsg)")
                    loadPage()
                    return
                }

                break
            case .accountDoesNotExist:
                TCSLogWithMark("user account doesn't exist yet")

            case .other(let mesg):
                TCSLogWithMark("password check error:\(mesg)")

                mechanismDelegate.denyLogin(message:mesg)
                return
            }
        }
        TCSLogWithMark("passing username:\(username), password, and tokens")
        TCSLogWithMark("setting kAuthorizationEnvironmentUsername")
        mechanismDelegate.setContextString(type: kAuthorizationEnvironmentUsername, value: username)
        TCSLogWithMark("setting kAuthorizationEnvironmentPassword")

        mechanismDelegate.setContextString(type: kAuthorizationEnvironmentPassword, value: password)
        TCSLogWithMark("setting username")

        mechanismDelegate.setHint(type: .user, hint: username)
        TCSLogWithMark("setting tokens.password")

        mechanismDelegate.setHint(type: .pass, hint: password)

        TCSLogWithMark("setting tokens")

        mechanismDelegate.setHint(type: .tokens, hint: [credentials.idToken ?? "",credentials.refreshToken ?? "",credentials.accessToken ?? ""])
        TCSLogWithMark("calling allowLogin")
        passwordHintSet=true
        mechanismDelegate.allowLogin()
//        if hints.count>0 {
//            feedbackDelegate?.setHints(hints)
//        }
//        if contextStrings.count>0 {
//            feedbackDelegate?.setContextStrings(contextStrings)
//        }

        //xyzzy bad bad bad
//        if let controller = self.view.window?.windowController as? MainLoginWindowController {
//            controller.loginTransition {
//                self.mechanism?.allowLogin()
//            }
//        }
    }

}



extension String {

    var stripped: String {
        let okayChars = Set("abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLKMNOPQRSTUVWXYZ1234567890+-._")
        return self.filter {okayChars.contains($0) }
    }
}
