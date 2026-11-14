import Vapor

struct GameDTO: Content {
    let id: UUID?
    let title: String
    let minPlayers: Int
    let maxPlayers: Int
    let durationMinutes: Int
    let isAvailable: Bool
    let activeLoanID: UUID?
}

extension Game {
    func toDTO() -> GameDTO {
        
        let activeLoan = ($loans.value ?? []).first {
            $0.returnedAt == nil
        }
        
        return GameDTO(
            id: id,
            title: title,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            durationMinutes: durationMinutes,
            isAvailable: isAvailable,
            activeLoanID: activeLoan?.id
        )
    }
}
