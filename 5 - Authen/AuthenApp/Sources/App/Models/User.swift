//
//  File.swift
//  
//
//  Created by Orka on 08/10/2024.
//

import Vapor

// Modèle User
struct User: Content, Authenticatable {
    var id: UUID
    var username: String
    var role: Role
    
    enum Role: String, Content {
        case admin
        case user
    }
}

extension User {
    static let Horka = User(id: UUID(),
                            username: "Horka_TV",
                            role: .user)
}
