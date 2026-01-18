//
//  File.swift
//  
//
//  Created by Orka on 27/09/2024.
//

import Vapor

struct AuthMiddleware: AsyncBearerAuthenticator {
    func authenticate(bearer: Vapor.BearerAuthorization, for request: Vapor.Request) async throws {
        guard bearer.token == "MonSuperToken" else {
            throw Abort(.unauthorized)
        }
        request.auth.login(User.horka)
    }
}
