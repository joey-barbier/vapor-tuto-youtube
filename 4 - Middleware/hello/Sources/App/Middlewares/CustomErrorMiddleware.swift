//
//  File.swift
//  
//
//  Created by Orka on 27/09/2024.
//

import Vapor

struct ErrorDescription: Codable {
    let code: UInt
    let description: String
}

enum Failed: Error {
    case idNotFound
    case bddConnection
    
    func convert() -> HTTPStatus {
        switch self {
        case .idNotFound:
            return .badRequest
        case .bddConnection:
            return .internalServerError
        }
    }
}

struct CustomErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            // Passe la requête au prochain middleware ou handler
            return try await next.respond(to: request)
        } catch let error as Failed {
            // Si c'est une erreur spécifique, renvoie une réponse HTTP personnalisée
            let customError = error.convert()
            let code = customError.code
            let description = customError.description + " (throw: \(error))"

            do {
                let errorDescription = ErrorDescription(code: code,
                                                        description: description)
                let body = try Response.Body(data: JSONEncoder().encode(errorDescription))
                return Response(status: customError, body: body)
            } catch {
                return Response(status: .internalServerError, body: .init(string: "Error encoding response"))
            }
        } catch {
            // Sinon, renvoie une erreur générique
            // return Response(status: .internalServerError, body: .init(string: "Une erreur est survenue."))
            return try await next.respond(to: request)
        }
    }
}
