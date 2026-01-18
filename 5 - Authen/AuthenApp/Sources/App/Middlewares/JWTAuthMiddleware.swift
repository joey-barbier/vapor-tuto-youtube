//
//  File.swift
//  
//
//  Created by Orka on 08/10/2024.
//

import Vapor
import JWT

struct JWTAuthMiddleware: AsyncJWTAuthenticator {
    typealias Payload = UserJWT
    
    func authenticate(jwt: UserJWT, for request: Vapor.Request) async throws {
        // Récupérer l'utilisateur à partir du JWT (le champ 'sub')
        guard let userID = UUID(uuidString: jwt.sub.value) else {
            throw Abort(.unauthorized, reason: "Utilisateur non valide")
        }
        
        // Authentifier l'utilisateur dans la requête
        let user = User.Horka
        request.auth.login(user)
    }
}
