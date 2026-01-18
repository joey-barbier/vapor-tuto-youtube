//
//  LoggingMiddleware.swift
//
//
//  Created by Orka on 26/09/2024.
//

import Vapor

struct LoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        request.logger.info("👋🏻 Request received: \(request.description)")
        return try await next.respond(to: request)
    }
}

