import Vapor

struct CreateGameDTO: Content, Validatable {
    let title: String
    let minPlayers: Int
    let maxPlayers: Int
    let durationMinutes: Int

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: !.empty)
        validations.add("minPlayers", as: Int.self, is: .range(1...))
        validations.add("maxPlayers", as: Int.self, is: .range(1...))
        validations.add("durationMinutes", as: Int.self, is: .range(1...))
    }

    func ensureConsistentPlayerCount() throws {
        guard minPlayers <= maxPlayers else {
            throw Abort(.badRequest, reason: "minPlayers must not exceed maxPlayers")
        }
    }

    func toModel() -> Game {
        Game(title: title, minPlayers: minPlayers, maxPlayers: maxPlayers, durationMinutes: durationMinutes)
    }
}
