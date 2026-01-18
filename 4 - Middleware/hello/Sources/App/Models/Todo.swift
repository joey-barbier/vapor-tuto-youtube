//
//  Todo.swift
//  
//
//  Created by Orka on 26/09/2024.
//

import Vapor

typealias Todos = [Todo]
struct Todo: Content {
    let id: Int
    let title: String
    let user: User
}
