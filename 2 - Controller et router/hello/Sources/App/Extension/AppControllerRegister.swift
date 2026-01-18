//
//  File.swift
//  
//
//  Created by Orka on 19/09/2024.
//

import Vapor

protocol ControllersRegister {
    static func allCases() -> [RouteCollection]
    static func register(app: Application) throws
}

extension ControllersRegister {
    static func register(app: Application) throws {
        try allCases().forEach({ try app.register(collection: $0) })
    }
}
