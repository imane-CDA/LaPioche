//
//  OverdueLoanDTO.swift
//  LaPioche
//
//  Created by Apprenant131 on 16/11/2026.
//

import Vapor

struct OverdueLoanDTO: Content {
    let id: UUID?
    let gameTitle: String
    let memberName: String
    let borrowedAt: Date
    let dueAt: Date
}

extension Loan {
    func toOverdueLoanDTO() -> OverdueLoanDTO {
        OverdueLoanDTO(
            id: id,
            gameTitle: game.title,
            memberName: member.name,
            borrowedAt: borrowedAt,
            dueAt: dueAt
        )
    }
}
