import Fluent
import Vapor

struct LoanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let loans = routes.grouped("loans")
        loans.post(use: create)
        loans.get("overdue", use: overdue)

        let loansID = loans.grouped(":loanID")
        loansID.post("return", use: returnLoan)
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CreateLoanDTO.self)

        guard let game = try await Game.find(dto.gameID, on: req.db) else {
            throw Abort(.notFound, reason: "Game not found")
        }

        guard let member = try await Member.find(dto.memberID, on: req.db)
        else {
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

    @Sendable
    func returnLoan(req: Request) async throws -> LoanDTO {
        guard let loanID = req.parameters.get("loanID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid loan id")
        }

        guard let loan = try await Loan.find(loanID, on: req.db) else {
            throw Abort(.notFound, reason: "Loan not found")
        }

        guard loan.returnedAt == nil else {
            throw Abort(.conflict, reason: "Loan has already been returned")
        }

        loan.returnedAt = Date()

        try await loan.save(on: req.db)

        return loan.toDTO()
    }

    @Sendable
    func overdue(req: Request) async throws -> [OverdueLoanDTO] {
        let now = Date()

        let overdueLoans = try await Loan.query(on: req.db)
            .filter(\.$returnedAt == nil)
            .filter(\.$dueAt < now)
            .with(\.$game)
            .with(\.$member)
            .all()

        return overdueLoans.map { $0.toOverdueLoanDTO() }
    }
}
