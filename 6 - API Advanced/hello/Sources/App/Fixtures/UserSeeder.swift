//
//  File.swift
//  hello
//
//  Created by Orka on 15/10/2024.
//

import Foundation
import Fluent

struct UserSeeder {
    static func seed(on db: Database) async throws {
        let users = [
            User(name: "John Doe"),
            User(name: "Jane Smith"),
            User(name: "Alice Johnson"),
            User(name: "Bob Brown")
        ]
        
        for user in users {
            try await user.save(on: db)
        }
        
        print("Seeded users: \(users.map { $0.name })")
    }
}
