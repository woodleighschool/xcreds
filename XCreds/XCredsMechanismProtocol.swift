//
//  XCredsMechanismProtocol.swift
//  XCreds
//
//  Created by Timothy Perfitt on 12/24/23.
//

protocol XCredsMechanismProtocol {
    func allowLogin()
    func denyLogin(message:String?)
    func setHints(_ hints:[HintType:Any])
    func setContextStrings(_ contentStrings: [String : String])
    func setContextString(type: String, value: String)
    func setStickyContextString(type: String, value: String)

    func setHint(type: HintType, hint: Any)
    func reload()
    func run()
}
