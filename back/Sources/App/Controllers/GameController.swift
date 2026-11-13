import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        
           let gameID = games.grouped(":gameID")
            gameID.get(use: show)
            gameID.put(use: update)
            gameID.delete(use: delete)
        }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let games = try await Game.query(on: req.db)
            .with(\.$loans)
            .all()
        return games.map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = dto.toModel()
        try await game.save(on: req.db)
        let response = try await game.toDTO().encodeResponse(
            status: .created,
            for: req
        )

        print("Statut :", response.status)

        return response
    }

    @Sendable
    func show(req: Request) async throws -> GameDTO {
        try await findGame(req).toDTO()
    }

    private func findGame(_ req: Request) async throws -> Game {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }
        return game
    }
    
    @Sendable
    func update(req: Request) async throws -> GameDTO {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }

        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }

        let dto = try req.content.decode(CreateGameDTO.self)

        try dto.ensureConsistentPlayerCount()

        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes

        try await game.update(on: req.db)

        return game.toDTO()
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }
        
        guard game.loans.isEmpty else {
            throw Abort(.conflict, reason: "This game has borrowing history")
        }
        
        try await game.delete(on: req.db)

        return .noContent
    }
}
