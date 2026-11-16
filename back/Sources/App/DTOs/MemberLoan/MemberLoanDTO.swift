//
//  MemberLoanDTO.swift
//  LaPioche
//
//  Created by Apprenant131 on 16/11/2026.
//

import Vapor

struct MemberLoanDTO: Content {
    let id: UUID?
    let gameTitle: String
    let borrowedAt: Date
    let dueAt: Date
    let returnedAt: Date?
}

extension Loan {
    func toMemberLoanDTO() -> MemberLoanDTO {
        MemberLoanDTO(
            id: id,
            gameTitle: game.title,
            borrowedAt: borrowedAt,
            dueAt: dueAt,
            returnedAt: returnedAt
        )
    }
}
