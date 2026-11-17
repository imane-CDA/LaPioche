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
        let search = req.query[String.self, at: "q"]

        let playersString = req.query[String.self, at: "players"]
        let players = playersString.flatMap { Int($0) }

        let maxDurationString = req.query[String.self, at: "maxDuration"]
        let maxDuration = maxDurationString.flatMap { Int($0) }

        if playersString != nil && (players == nil || players! <= 0) {
            throw Abort(.badRequest, reason: "Players must be a positive integer")
        }

        if maxDurationString != nil && (maxDuration == nil || maxDuration! <= 0) {
            throw Abort(.badRequest, reason: "Max duration must be a positive integer")
        }

        var query = Game.query(on: req.db)

        if let search, !search.isEmpty {
            query = query.filter(
                \.$title ~~ search
            )
        }

        if let players {
            query = query
                .filter(\.$minPlayers <= players)
                .filter(\.$maxPlayers >= players)
        }

        if let maxDuration {
            query = query
                .filter(\.$durationMinutes <= maxDuration)
        }

        let games = try await query
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

        try CreateGameDTO.validate(content: req)
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
