//
//  File.swift
//  
//
//  Created by Orka on 08/10/2024.
//

import Vapor

struct LoginController: RouteCollection {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        routes.grouped("login").get(use: login)
        
        routes.grouped("profile")
            .grouped(JWTAuthMiddleware(),
                     User.guardMiddleware())
            .get(use: profile)
        
        routes.grouped("admin")
            .grouped(JWTAuthMiddleware(),
                     User.guardMiddleware(),
                     RoleMiddleware(requiredRole: .admin))
            .get(use: adminDashboard)
    }
}

extension LoginController {
    @Sendable
    func login(req: Request) throws -> TokenDto {
        let user = User.Horka
        let token = try UserJWT.generateToken(for: user, req: req)
        
        return .init(jwt: token)
    }
    
    @Sendable
    func profile(req: Request) throws -> String {
        let user = try req.auth.require(User.self)
        return "Bienvenue, \(user.username) !"
    }
    
    @Sendable
    func adminDashboard(req: Request) throws -> String {
        let user = try req.auth.require(User.self)
        return "Dashboard Admin, (\(user.username)) !"
    }
}
