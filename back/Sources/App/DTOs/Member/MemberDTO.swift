import Vapor

struct MemberDTO: Content {
    let id: UUID?
    let name: String
    let email: String
}

extension Member {
    func toDTO() -> MemberDTO {
        MemberDTO(id: id, name: name, email: email)
    }
}
