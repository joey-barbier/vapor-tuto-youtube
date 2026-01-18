//
//  File.swift
//  
//
//  Created by Orka on 27/09/2024.
//

import Fluent

struct CreateBonus: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("bonus")
            .id()
            .field("title", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bonus").delete()
    }
}
