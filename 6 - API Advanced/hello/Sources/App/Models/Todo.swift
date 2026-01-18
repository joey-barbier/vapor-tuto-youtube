import Fluent
import Foundation
import Vapor

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class Todo: Content, Model, @unchecked Sendable {
    static let schema = "todos"
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String
    
    @Field(key: "is_completed")
    var isCompleted: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Parent(key: "user_id")
    var user: User

    init() { }

    init(id: UUID? = nil, title: String, isCompleted: Bool = false, userID: UUID) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.$user.id = userID
    }
}
