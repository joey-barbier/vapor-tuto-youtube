//
//  TodoController.swift
//
//
//  Created by Orka on 26/09/2024.
//

import Vapor

struct TodoController: RouteCollection {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let base = routes.grouped("api", "todos")
        let details = base.grouped(":todoId")

        base.get(use: read)
        base.grouped(AuthMiddleware(), 
                     User.guardMiddleware()).post(use: create)
        
        details.get(use: find)
        details.delete(use: delete)
    }
}

extension TodoController {
    @Sendable
    func read(req: Request) -> [Todo] {
        [
            .init(id: 1, title: "👀 Rejoins moi sur twitch.tv/horka_tv ! 🫶🏻", user: .horka),
            .init(id: 2, title: "Merci encore pour le soutien 🙏🏻", user: .horka),
            .init(id: 3, title: "Vapor c'est trop bien 🔥", user: .horka),
        ]
    }
    
    @Sendable
    func create(req: Request) -> HTTPStatus {
        .ok
    }
    
    @Sendable
    func find(req: Request) throws -> Todo {
        return .init(id: 1, title: "👀 Rejoins moi sur twitch.tv/horka_tv ! 🫶🏻", user: .horka)
    }
    
    @Sendable
    func delete(req: Request) throws -> HTTPStatus {
        throw Failed.idNotFound
    }
}

