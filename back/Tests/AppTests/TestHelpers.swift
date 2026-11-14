@testable import App
import XCTVapor

func withApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await test(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

func createGame(
    _ app: Application,
    title: String = "Catan",
    minPlayers: Int = 3,
    maxPlayers: Int = 4,
    durationMinutes: Int = 90
) async throws -> GameDTO {
    var game: GameDTO?
    try await app.test(.POST, "games", beforeRequest: { req in
        try req.content.encode(CreateGameDTO(
            title: title,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            durationMinutes: durationMinutes
        ))
    }, afterResponse: { res async throws in
        game = try res.content.decode(GameDTO.self)
    })
    return try XCTUnwrap(game)
}

func createMember(
    _ app: Application,
    name: String = "Camille",
    email: String = "camille@example.com"
) async throws -> MemberDTO {
    var member: MemberDTO?
    try await app.test(.POST, "members", beforeRequest: { req in
        try req.content.encode(CreateMemberDTO(name: name, email: email))
    }, afterResponse: { res async throws in
        member = try res.content.decode(MemberDTO.self)
    })
    return try XCTUnwrap(member)
}

// The API cannot create a loan that is already late, so tests insert it directly.
// @discardableResult : Allows callers to ignore the returned loan when they don't need it
@discardableResult
func insertLoan(
    _ app: Application,
    gameID: UUID,
    memberID: UUID,
    borrowedAt: Date,
    dueAt: Date,
    returnedAt: Date? = nil
) async throws -> Loan {
    let loan = Loan(gameID: gameID, memberID: memberID, borrowedAt: borrowedAt, dueAt: dueAt)
    loan.returnedAt = returnedAt
    try await loan.save(on: app.db)
    return loan
}
