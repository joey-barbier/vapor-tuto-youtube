//
//  HelloWorldController.swift
//
//
//  Created by Orka on 06/08/2024.
//

import Vapor

struct HelloWorldController: RouteCollection {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let usersRoute = routes.grouped("api", "users")
        let usersListRoute = usersRoute.grouped("list")
        
        usersListRoute.get(use: usersList(req:))
        usersListRoute.get(":id", use: user)
        usersRoute.get("admin", use: adminList)
        
        usersListRoute.post(use: newUser(req:))
        
        // monsite.fr/api/users/list & monsite.fr/api/users/admin?id=123
    }
}

extension HelloWorldController {
    @Sendable
    func user(req: Request) async throws -> String {
        guard let id: String = req.parameters.get("id") else { throw Abort(.badRequest) }
        return "user_id_\(id)"
    }
    
    @Sendable
    func newUser(req: Request) async throws -> String {
        guard let name: String = try req.query.get(at: "name") else { throw Abort(.badRequest) }
        return "new user: \(name)"
    }
    
    @Sendable
    func usersList(req: Request) async throws -> [String] {
        return ["userA", "userB"]
    }
    
    @Sendable
    func adminList(req: Request) async throws -> [String] {
        return ["admin1", "admin2"]
    }
}
