import Fluent
import Vapor

struct LoanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let loans = routes.grouped("loans")
        loans.post(use: create)
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CreateLoanDTO.self)

        guard let game = try await Game.find(dto.gameID, on: req.db) else {
            throw Abort(.notFound, reason: "Game not found")
        }
        
        guard let member = try await Member.find(dto.memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        
        let existingLoan = try await Loan.query(on: req.db)
            .filter(\.$game.$id == game.requireID())
            // le jeu n'a pas encore été rendu
            .filter(\.$returnedAt == nil)
            .first()

        guard existingLoan == nil else {
            throw Abort(.conflict, reason: "Game is already borrowed")
        }
        
        let now = Date()
        
        let loan = Loan(
            gameID: try game.requireID(),
            memberID: try member.requireID(),
            borrowedAt: now,
            dueAt: try Loan.dueDate(from: now)
        )
        
        try await loan.save(on: req.db)
        
        return try await loan.toDTO().encodeResponse(status: .created, for: req)
    }
}
