//
//  File.swift
//  hello
//
//  Created by Orka on 15/10/2024.
//

import Foundation
import Fluent

struct TodoSeeder {
    static func seed(on db: Database) async throws {
        // Récupérer les utilisateurs pour les lier aux todos
        let users = try await User.query(on: db).all()

        // Générer des todos avec différents titres, statuts et utilisateurs
        let todos = [
            Todo(title: "Learn Vapor", isCompleted: true, userID: users[0].id!),
            Todo(title: "Complete project", isCompleted: false, userID: users[0].id!),
            Todo(title: "Go for a walk", isCompleted: true, userID: users[1].id!),
            Todo(title: "Read Swift documentation", isCompleted: false, userID: users[1].id!),
            Todo(title: "Prepare dinner", isCompleted: true, userID: users[2].id!),
            Todo(title: "Write blog post", isCompleted: false, userID: users[2].id!),
            Todo(title: "Do laundry", isCompleted: true, userID: users[3].id!),
            Todo(title: "Work out", isCompleted: false, userID: users[3].id!)
        ]

        for todo in todos {
            try await todo.save(on: db)
        }
        
        print("Seeded todos: \(todos.map { $0.title })")
    }
}
