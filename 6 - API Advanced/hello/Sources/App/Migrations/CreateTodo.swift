import Fluent

struct CreateTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .id()
            .field("title", .string, .required)
            .field("is_completed", .bool, .required)
            .field("created_at", .date, .required)
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Todo.schema).delete()
    }
}
