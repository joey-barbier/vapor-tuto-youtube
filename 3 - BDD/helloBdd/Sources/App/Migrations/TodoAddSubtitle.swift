import Fluent

struct TodoAddSubtitle: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .field("subtitle", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .deleteField("subtitle")
            .update()
    }
}
