import Vapor

struct LoanDTO: Content {
    let id: UUID?
    let gameID: UUID
    let memberID: UUID
    let borrowedAt: Date
    let dueAt: Date
    let returnedAt: Date?
}

extension Loan {
    func toDTO() -> LoanDTO {
        LoanDTO(
            id: id,
            gameID: $game.id,
            memberID: $member.id,
            borrowedAt: borrowedAt,
            dueAt: dueAt,
            returnedAt: returnedAt
        )
    }
}
