@testable import App
import XCTVapor

final class LoanTests: XCTestCase {
    private func borrow(
        _ app: Application,
        gameID: UUID,
        memberID: UUID,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "loans", beforeRequest: { req in
            try req.content.encode(CreateLoanDTO(gameID: gameID, memberID: memberID))
        }, afterResponse: afterResponse)
    }

    func testBorrowGameReturnsCreated() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                XCTAssertEqual(res.status, .created)
                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(loan.gameID, game.id)
                XCTAssertEqual(loan.memberID, member.id)
                XCTAssertNil(loan.returnedAt)
            }
        }
    }

    func testDueDateIsFourteenDaysAfterBorrowDate() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let days = calendar.dateComponents([.day], from: loan.borrowedAt, to: loan.dueAt).day
                XCTAssertEqual(days, 14)
            }
        }
    }

    func testBorrowedGameIsNoLongerAvailable() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id)) { _ in }

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            })
        }
    }

    func testBorrowingAGameAlreadyOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let first = try await createMember(app, email: "first@example.com")
            let second = try await createMember(app, name: "Alex", email: "second@example.com")
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(first.id)) { _ in }
            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(second.id)) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testBorrowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await borrow(app, gameID: UUID(), memberID: try XCTUnwrap(member.id)) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testBorrowWithUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            let game = try await createGame(app)

            try await borrow(app, gameID: try XCTUnwrap(game.id), memberID: UUID()) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    
    func testReturnLoanReturnsUpdatedLoan() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await borrow(
                app,
                gameID: gameID,
                memberID: memberID
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                let loanID = try XCTUnwrap(loan.id)

                try await app.test(
                    .POST,
                    "loans/\(loanID)/return",
                    afterResponse: { returnResponse async throws in
                        XCTAssertEqual(returnResponse.status, .ok)

                        let returnedLoan = try returnResponse.content.decode(LoanDTO.self)
                        XCTAssertEqual(returnedLoan.id, loanID)
                        XCTAssertNotNil(returnedLoan.returnedAt)
                    }
                )
            }
        }
    }

    func testReturnUnknownLoanReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans/\(UUID())/return",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testReturnAlreadyReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let now = Date()
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: now.addingTimeInterval(-86400),
                dueAt: now.addingTimeInterval(13 * 86400),
                returnedAt: now
            )

            let loan = try await Loan.query(on: app.db).first()
            let loanID = try XCTUnwrap(loan?.id)

            try await app.test(
                .POST,
                "loans/\(loanID)/return",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testReturnedGameBecomesAvailableAgain() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await borrow(
                app,
                gameID: gameID,
                memberID: memberID
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                let loanID = try XCTUnwrap(loan.id)

                try await app.test(
                    .POST,
                    "loans/\(loanID)/return",
                    afterResponse: { returnResponse async throws in
                        XCTAssertEqual(returnResponse.status, .ok)
                    }
                )
            }

            try await app.test(
                .GET,
                "games/\(gameID)",
                afterResponse: { res async throws in
                    let updatedGame = try res.content.decode(GameDTO.self)
                    XCTAssertTrue(updatedGame.isAvailable)
                }
            )
        }
    }

    func testGetOverdueLoansReturnsOverdueLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: now.addingTimeInterval(-20 * 86400),
                dueAt: now.addingTimeInterval(-6 * 86400)
            )

            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([OverdueLoanDTO].self)

                    XCTAssertEqual(loans.count, 1)
                    XCTAssertEqual(loans[0].gameTitle, game.title)
                    XCTAssertEqual(loans[0].memberName, member.name)
                }
            )
        }
    }

    func testGetOverdueLoansExcludesReturnedLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-20 * 86400),
                dueAt: now.addingTimeInterval(-6 * 86400),
                returnedAt: now
            )

            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([OverdueLoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }

    func testGetOverdueLoansExcludesLoansNotYetDue() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-5 * 86400),
                dueAt: now.addingTimeInterval(9 * 86400)
            )

            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([OverdueLoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }

    func testGetOverdueLoansReturnsEmptyArrayWhenNoLoansAreOverdue() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([OverdueLoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }

}
