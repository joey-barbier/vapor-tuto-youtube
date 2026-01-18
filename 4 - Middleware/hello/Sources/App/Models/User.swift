//
//  File.swift
//  
//
//  Created by Orka on 27/09/2024.
//

import Vapor

struct User: Authenticatable, Content {
    let id: Int
    let name: String
}

extension User {
    static let horka = Self.init(id: 1, name: "Horka_TV")
}
