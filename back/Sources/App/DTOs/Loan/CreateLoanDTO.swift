import Vapor

struct CreateLoanDTO: Content {
    let gameID: UUID
    let memberID: UUID
}
