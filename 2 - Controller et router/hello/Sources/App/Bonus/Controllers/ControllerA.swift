//
//  File.swift
//  
//
//  Created by Orka on 19/09/2024.
//

import Vapor

extension App.Bonus.Controllers {
    struct ControllerA: RouteCollection {
        func boot(routes: RoutesBuilder) throws {
            let apiRelease = routes.grouped("api").grouped("demo")
            apiRelease.on(.POST, use: self.demo)
        }
    }
}

extension App.Bonus.Controllers.ControllerA {
    @Sendable
    func demo(req: Request) async throws -> HTTPStatus {
        .accepted
    }
}
