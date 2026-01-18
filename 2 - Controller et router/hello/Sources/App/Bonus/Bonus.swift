//
//  File.swift
//  
//
//  Created by Orka on 19/09/2024.
//

import Vapor

extension App { // Pour avoir l'autocompletion "App." me propose tous mes modèles
    enum Bonus {
        enum Jobs {} // exemple de class qui compose "Bonus"
        enum Services {}
        enum Migrations {}
        enum Controllers {}
    }
}

// MARK: - Controllers
extension App.Bonus.Controllers: ControllersRegister { // permet d'enregistrer les controllers en une ligne 🔥 (cf. routes.swift)
    static func allCases() -> [RouteCollection] {
        [
            ControllerA(),
            ControllerB()
        ]
    }
}
