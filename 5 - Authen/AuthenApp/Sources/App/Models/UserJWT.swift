//
//  File.swift
//  
//
//  Created by Orka on 08/10/2024.
//

import Vapor
import JWT

// Modèle JWT pour le payload du token
struct UserJWT: JWTPayload {
    var sub: SubjectClaim
    var role: User.Role
    
    // Obligatoire pour valider le JWT
    func verify(using signer: JWTSigner) throws {
        // Ajoutez toute vérification supplémentaire ici si nécessaire
    }
}

extension UserJWT {
    // Route pour générer un JWT après connexion de l'utilisateur
    static func generateToken(for user: User, req: Request) throws -> String {
        // Créez le payload du JWT
        let userJWT = UserJWT(sub: .init(value: user.id.uuidString),
                              role: user.role)
                
        // Générez le token en signant le JWT
        let jwt = try req.application.jwt.signers.sign(userJWT)
        
        // Retournez le token signé
        return jwt
    }
}
