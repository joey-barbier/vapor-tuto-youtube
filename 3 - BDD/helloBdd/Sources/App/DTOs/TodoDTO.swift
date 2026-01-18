import Fluent
import Vapor

struct TodoDTO: Content {
    var id: UUID?
    var title: String?
    var subtitle: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
    }
    
    func toModel() -> Todo {
        let model = Todo()
        
        model.id = self.id ?? UUID()
        if let title = self.title {
            model.title = title
        }
        model.subtitle = subtitle
        
        return model
    }
}
