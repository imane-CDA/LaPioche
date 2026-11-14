@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // modifier un utilisateur
    func testUpdateMemberReturnsUpdatedMember() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille Updated",
                    email: "camille.updated@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updatedMember = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updatedMember.id, id)
                XCTAssertEqual(updatedMember.name, "Camille Updated")
                XCTAssertEqual(updatedMember.email, "camille.updated@example.com")
            })
        }
    }
    
    // garder son propre email
    func testUpdateMemberWithSameEmailDoesNotReturnConflict() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille Updated",
                    email: member.email
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }
    
    // Refuser un email déjà utilisée
    func testUpdateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            let existingMember = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Autre",
                    email: "autre@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)

                let anotherMember = try res.content.decode(MemberDTO.self)
                let id = try XCTUnwrap(anotherMember.id)

                try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                    try req.content.encode(CreateMemberDTO(
                        name: "Autre Updated",
                        email: existingMember.email
                    ))
                }, afterResponse: { updateResponse async throws in
                    XCTAssertEqual(updateResponse.status, .conflict)
                })
            })
        }
    }
    
    // refuser un body invalide
    func testUpdateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille",
                    email: "not-an-email"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    // Refuser un id inexistant
    func testUpdateUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille",
                    email: "camille@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // refuser un id mal formé
    func testUpdateMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/not-a-uuid", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille",
                    email: "camille@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    // supprimer un utilisateur
    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // Refuser la suppression d'un membre ayant un historique d'emprunts
    func testDeleteMemberWithLoanHistoryReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            let borrowedAt = Date()
            let dueAt = try XCTUnwrap(
                Calendar.current.date(
                    byAdding: .day,
                    value: 14,
                    to: borrowedAt
                )
            )

            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: borrowedAt,
                dueAt: dueAt
            )

            try await app.test(.DELETE, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }
    
    // Refuser la suppression d'un membre inexistant
    func testDeleteUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    // Refuser un id mal formé
    func testDeleteMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testDeleteMemberWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60),
                dueAt: Date(timeIntervalSinceNow: -16 * 24 * 60 * 60),
                returnedAt: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
            )

            try await app.test(
                .DELETE,
                "members/\(memberID)",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }}
