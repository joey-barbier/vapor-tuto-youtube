//
//  File.swift
//  
//
//  Created by Orka on 19/09/2024.
//

import Vapor

extension App.Bonus.Controllers {
    struct ControllerB: RouteCollection {
        func boot(routes: RoutesBuilder) throws {
            let apiRelease = routes.grouped("api").grouped("test")
            apiRelease.on(.POST, use: self.demoBis)
        }
    }
}

extension App.Bonus.Controllers.ControllerB {
    @Sendable
    func demoBis(req: Request) async throws -> HTTPStatus {
        .accepted
    }
}
