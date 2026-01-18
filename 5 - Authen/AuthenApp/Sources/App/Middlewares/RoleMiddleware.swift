//
//  File.swift
//  
//
//  Created by Orka on 09/10/2024.
//

import Vapor

// Middleware pour vérifier les rôles
struct RoleMiddleware: AsyncMiddleware {
    let requiredRole: User.Role

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let user = try request.auth.require(User.self)
        
        guard user.role == requiredRole else {
            throw Abort(.forbidden, reason: "Accès refusé")
        }

        return try await next.respond(to: request)
    }
}
