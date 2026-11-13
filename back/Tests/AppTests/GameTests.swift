@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }
    
    // Modifier un jeu avec succès
    func testUpdateGameReturnsUpdatedGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan Updated",
                    minPlayers: 2,
                    maxPlayers: 5,
                    durationMinutes: 120
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updatedGame = try res.content.decode(GameDTO.self)

                XCTAssertEqual(updatedGame.id, id)
                XCTAssertEqual(updatedGame.title, "Catan Updated")
                XCTAssertEqual(updatedGame.minPlayers, 2)
                XCTAssertEqual(updatedGame.maxPlayers, 5)
                XCTAssertEqual(updatedGame.durationMinutes, 120)
            })
        }
    }
    
    // Refuser une modification invalide
    func testUpdateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 5,
                    maxPlayers: 2,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    // Modifier un jeu inexistant
    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 3,
                    maxPlayers: 4,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // Supprimer un jeu avec succès
    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // Refuser la suppression d'un jeu ayant un historique d'emprunts
    func testDeleteGameWithLoanHistoryReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            let borrowedAt = Date()
            let dueAt = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: borrowedAt
            )!

            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            try await app.test(.DELETE, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }
    
    // Supprimer un jeu inexistant
    func testDeleteUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
}
