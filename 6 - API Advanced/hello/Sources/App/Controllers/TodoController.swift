import Fluent
import Vapor

struct TodoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let todos = routes.grouped("todos")
        todos.get(use: self.index)
    }

    @Sendable
    func index(req: Request) async throws -> Page<Todo> {
        let sortDirection = req.query[String.self, at: "direction"] ?? "asc"
        
        let query = Todo.query(on: req.db)
            .sort(\.$createdAt, sortDirection == "asc" ? .ascending : .descending)
        
        // on vérifie si un filtre isCompleted est passé en paramètre
        let isCompleted: Bool? = try req.query.get(at: "isCompleted")
        
        // si oui, on filtre les todos en fonction de ce paramètre
        if let isCompleted {
            query
                .filter(\.$isCompleted == isCompleted)
        }
        
        // on vérifie si un filtre username est passé en paramètre
        if let username = req.query[String.self, at: "username"] {
            // si c'est le cas on ajoute une jointure avec la table User et on filtre les todos par nom d'utilisateur
            query
                .join(User.self, on: \Todo.$user.$id == \User.$id) // Jointure entre Todo et User
                .filter(User.self, \.$name == username) // Filtrer par nom d'utilisateur
        }
                
        // On souhaite récupérer l'utilisateur associé à chaque todo
        if let withUser = try? req.query.get(Bool.self, at: "withUser"), withUser {
            query
                .with(\.$user)
        }
        
        return try await query.paginate(for: req)
    }
}
