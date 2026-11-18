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
                XCTAssertNil(game.activeLoanID)
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

    func testListGamesIncludesActiveLoanID() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            let borrowedAt = Date()
            let dueAt = try Loan.dueDate(from: borrowedAt)

            let loan = try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            let loanID = try XCTUnwrap(loan.id)

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)
                let returnedGame = try XCTUnwrap(
                    games.first { $0.id == gameID }
                )

                XCTAssertFalse(returnedGame.isAvailable)
                XCTAssertEqual(returnedGame.activeLoanID, loanID)
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

    func testListGamesFiltersByTitleCaseInsensitively() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games?q=cAtAn", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Catan")
            })
        }
    }

    func testListGamesFiltersByPlayerCount() async throws {
        try await withApp { app in
            _ = try await createGame(
                app,
                title: "Catan",
                minPlayers: 3,
                maxPlayers: 4
            )
            _ = try await createGame(
                app,
                title: "Dixit",
                minPlayers: 3,
                maxPlayers: 6
            )

            try await app.test(.GET, "games?players=5", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Dixit")
            })
        }
    }

    func testListGamesFiltersByMaximumDuration() async throws {
        try await withApp { app in
            _ = try await createGame(
                app,
                title: "Catan",
                durationMinutes: 90
            )
            _ = try await createGame(
                app,
                title: "Dixit",
                durationMinutes: 30
            )

            try await app.test(.GET, "games?maxDuration=60", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Dixit")
            })
        }
    }

    func testListGamesRejectsInvalidPlayerCount() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=abc", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGamesRejectsInvalidMaximumDuration() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?maxDuration=abc", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGamesRejectsNonPositiveFilters() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=0", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })

            try await app.test(.GET, "games?players=-2", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })

            try await app.test(.GET, "games?maxDuration=0", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })

            try await app.test(.GET, "games?maxDuration=-10", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGamesCombinesAllFilters() async throws {
        try await withApp { app in
            _ = try await createGame(
                app,
                title: "Catan",
                minPlayers: 3,
                maxPlayers: 4,
                durationMinutes: 90
            )
            _ = try await createGame(
                app,
                title: "Catan Junior",
                minPlayers: 2,
                maxPlayers: 4,
                durationMinutes: 30
            )
            _ = try await createGame(
                app,
                title: "Dixit",
                minPlayers: 3,
                maxPlayers: 6,
                durationMinutes: 30
            )

            try await app.test(.GET, "games?q=catan&players=3&maxDuration=60", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Catan Junior")
            })
        }
    }

    func testListGamesFiltersAvailableGames() async throws {
        try await withApp { app in
            let availableGame = try await createGame(app, title: "Catan")
            let borrowedGame = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)

            let borrowedAt = Date()
            let dueAt = try Loan.dueDate(from: borrowedAt)

            _ = try await insertLoan(
                app,
                gameID: try XCTUnwrap(borrowedGame.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            try await app.test(.GET, "games?available=true", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.id, availableGame.id)
                XCTAssertTrue(games.first?.isAvailable ?? false)
            })
        }
    }

    func testListGamesFiltersBorrowedGames() async throws {
        try await withApp { app in
            let availableGame = try await createGame(app, title: "Catan")
            let borrowedGame = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)

            let borrowedAt = Date()
            let dueAt = try Loan.dueDate(from: borrowedAt)

            _ = try await insertLoan(
                app,
                gameID: try XCTUnwrap(borrowedGame.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            try await app.test(.GET, "games?available=false", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.id, borrowedGame.id)
                XCTAssertFalse(games.first?.isAvailable ?? true)
            })
        }
    }

    func testListGamesRejectsInvalidAvailability() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?available=yes", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGamesCombinesAvailabilityWithTitleFilter() async throws {
        try await withApp { app in
            let availableCatan = try await createGame(app, title: "Catan")
            let borrowedCatan = try await createGame(app, title: "Catan Junior")
            _ = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)

            let borrowedAt = Date()
            let dueAt = try Loan.dueDate(from: borrowedAt)

            _ = try await insertLoan(
                app,
                gameID: try XCTUnwrap(borrowedCatan.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            try await app.test(.GET, "games?q=catan&available=true", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.id, availableCatan.id)
            })
        }
    }
}
