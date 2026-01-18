# Chapitre 6 - API Avancée

## Objectifs d'apprentissage
- Maîtriser les relations entre modèles
- Implémenter la pagination
- Créer des requêtes complexes avec filtres et tri
- Gérer le eager loading
- Initialiser la base avec des seeders

---

## 1. Relations Entre Modèles

### Types de Relations

| Relation | Côté Parent | Côté Enfant |
|----------|-------------|-------------|
| One-to-Many | `@Children` | `@Parent` |
| Many-to-One | `@Parent` | - |
| One-to-One | `@OptionalChild` | `@Parent` |
| Many-to-Many | `@Siblings` | `@Siblings` |

---

## 2. Relation One-to-Many

### Modèle Parent (User)

```swift
import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "email")
    var email: String

    // Relation vers les enfants (todos)
    @Children(for: \.$user)
    var todos: [Todo]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

### Modèle Enfant (Todo)

```swift
import Fluent
import Vapor

final class Todo: Model, Content, @unchecked Sendable {
    static let schema = "todos"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "is_completed")
    var isCompleted: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // Relation vers le parent (user)
    @Parent(key: "user_id")
    var user: User

    init() {}

    init(id: UUID? = nil, title: String, isCompleted: Bool = false, userID: UUID) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.$user.id = userID
    }
}
```

### Migration avec Foreign Key

```swift
import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("name", .string, .required)
            .field("email", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(User.schema).delete()
    }
}

struct CreateTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .id()
            .field("title", .string, .required)
            .field("is_completed", .bool, .required)
            .field("created_at", .datetime)
            .field("user_id", .uuid, .required,
                .references(User.schema, "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Todo.schema).delete()
    }
}
```

### Options onDelete

```swift
.references("users", "id", onDelete: .cascade)    // Supprime les enfants
.references("users", "id", onDelete: .restrict)   // Empêche la suppression
.references("users", "id", onDelete: .setNull)    // Met à NULL (si optionnel)
.references("users", "id", onDelete: .setDefault) // Remet la valeur par défaut
.references("users", "id", onDelete: .noAction)   // Pas d'action
```

---

## 3. Relation Many-to-Many

### Exemple : Users et Tags

```swift
// Tag.swift
final class Tag: Model, Content, @unchecked Sendable {
    static let schema = "tags"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Siblings(through: TodoTag.self, from: \.$tag, to: \.$todo)
    var todos: [Todo]

    init() {}
}

// Table pivot
final class TodoTag: Model, @unchecked Sendable {
    static let schema = "todo_tags"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "todo_id")
    var todo: Todo

    @Parent(key: "tag_id")
    var tag: Tag

    init() {}

    init(todoID: UUID, tagID: UUID) {
        self.$todo.id = todoID
        self.$tag.id = tagID
    }
}

// Dans Todo.swift, ajouter:
@Siblings(through: TodoTag.self, from: \.$todo, to: \.$tag)
var tags: [Tag]
```

### Manipulation des Relations Many-to-Many

```swift
// Ajouter un tag à un todo
func addTag(req: Request) async throws -> HTTPStatus {
    let todoID = try req.parameters.require("todoId", as: UUID.self)
    let tagID = try req.parameters.require("tagId", as: UUID.self)

    guard let todo = try await Todo.find(todoID, on: req.db),
          let tag = try await Tag.find(tagID, on: req.db) else {
        throw Abort(.notFound)
    }

    try await todo.$tags.attach(tag, on: req.db)
    return .ok
}

// Retirer un tag
func removeTag(req: Request) async throws -> HTTPStatus {
    // ...
    try await todo.$tags.detach(tag, on: req.db)
    return .ok
}

// Récupérer les tags d'un todo
func getTags(req: Request) async throws -> [Tag] {
    let todo = try await Todo.find(todoID, on: req.db)!
    return try await todo.$tags.get(on: req.db)
}
```

---

## 4. Eager Loading

### Problème N+1

```swift
// ❌ Mauvais: N+1 requêtes
let todos = try await Todo.query(on: req.db).all()
for todo in todos {
    let user = try await todo.$user.get(on: req.db)  // 1 requête par todo!
    print("\(todo.title) - \(user.name)")
}
```

### Solution: with()

```swift
// ✅ Bon: 2 requêtes (todos + users)
let todos = try await Todo.query(on: req.db)
    .with(\.$user)  // Eager load
    .all()

for todo in todos {
    print("\(todo.title) - \(todo.user.name)")  // Pas de requête supplémentaire
}
```

### Eager Loading Imbriqué

```swift
// Charger les todos avec leurs users et les tags
let todos = try await Todo.query(on: req.db)
    .with(\.$user)
    .with(\.$tags)
    .all()

// Charger les users avec leurs todos et les tags de chaque todo
let users = try await User.query(on: req.db)
    .with(\.$todos) { todo in
        todo.with(\.$tags)
    }
    .all()
```

### Eager Loading Conditionnel

```swift
// Eager loading basé sur un query parameter
@Sendable
func index(req: Request) async throws -> [Todo] {
    var query = Todo.query(on: req.db)

    // ?withUser=true
    if let withUser: Bool = try? req.query.get(at: "withUser"), withUser {
        query = query.with(\.$user)
    }

    // ?withTags=true
    if let withTags: Bool = try? req.query.get(at: "withTags"), withTags {
        query = query.with(\.$tags)
    }

    return try await query.all()
}
```

---

## 5. Pagination

### Pagination Native de Fluent

```swift
import Fluent
import Vapor

@Sendable
func index(req: Request) async throws -> Page<Todo> {
    // Retourne automatiquement une page paginée
    // ?page=1&per=10
    return try await Todo.query(on: req.db)
        .sort(\.$createdAt, .descending)
        .paginate(for: req)
}
```

### Structure Page<T>

```swift
// La structure Page de Fluent contient:
struct Page<T: Codable>: Content {
    let items: [T]           // Les éléments de la page
    let metadata: PageMetadata

    struct PageMetadata: Content {
        let page: Int        // Page actuelle
        let per: Int         // Éléments par page
        let total: Int       // Total d'éléments
    }
}
```

### Réponse JSON

```json
{
    "items": [
        { "id": "...", "title": "Todo 1", ... },
        { "id": "...", "title": "Todo 2", ... }
    ],
    "metadata": {
        "page": 1,
        "per": 10,
        "total": 42
    }
}
```

### Pagination Personnalisée

```swift
struct PaginationDTO: Content {
    let page: Int
    let perPage: Int

    var offset: Int { (page - 1) * perPage }
}

@Sendable
func customPaginate(req: Request) async throws -> [Todo] {
    let page = req.query[Int.self, at: "page"] ?? 1
    let perPage = min(req.query[Int.self, at: "perPage"] ?? 20, 100) // Max 100

    return try await Todo.query(on: req.db)
        .sort(\.$createdAt, .descending)
        .range((page - 1) * perPage ..< page * perPage)
        .all()
}
```

---

## 6. Filtrage Avancé

### Controller avec Filtres

```swift
@Sendable
func index(req: Request) async throws -> Page<Todo> {
    var query = Todo.query(on: req.db)

    // Filtre par statut: ?isCompleted=true
    if let isCompleted: Bool = try? req.query.get(at: "isCompleted") {
        query = query.filter(\.$isCompleted == isCompleted)
    }

    // Filtre par titre (recherche): ?search=vapor
    if let search: String = req.query["search"], !search.isEmpty {
        query = query.filter(\.$title ~~ search)  // LIKE %search%
    }

    // Filtre par date: ?from=2024-01-01&to=2024-12-31
    if let fromStr: String = req.query["from"],
       let from = ISO8601DateFormatter().date(from: fromStr) {
        query = query.filter(\.$createdAt >= from)
    }

    if let toStr: String = req.query["to"],
       let to = ISO8601DateFormatter().date(from: toStr) {
        query = query.filter(\.$createdAt <= to)
    }

    // Filtre par user (avec join): ?username=john
    if let username: String = req.query["username"], !username.isEmpty {
        query = query
            .join(User.self, on: \Todo.$user.$id == \User.$id)
            .filter(User.self, \.$name == username)
    }

    return try await query.paginate(for: req)
}
```

### Filtres Multiples avec DTO

```swift
struct TodoFilterDTO: Content {
    var isCompleted: Bool?
    var search: String?
    var username: String?
    var fromDate: Date?
    var toDate: Date?
    var tagIds: [UUID]?
}

@Sendable
func filtered(req: Request) async throws -> Page<Todo> {
    let filters = try req.query.decode(TodoFilterDTO.self)

    var query = Todo.query(on: req.db)

    if let isCompleted = filters.isCompleted {
        query = query.filter(\.$isCompleted == isCompleted)
    }

    if let search = filters.search, !search.isEmpty {
        query = query.group(.or) { group in
            group.filter(\.$title ~~ search)
            // Ajouter d'autres champs si nécessaire
        }
    }

    if let username = filters.username, !username.isEmpty {
        query = query
            .join(User.self, on: \Todo.$user.$id == \User.$id)
            .filter(User.self, \.$name ~~ username)
    }

    if let from = filters.fromDate {
        query = query.filter(\.$createdAt >= from)
    }

    if let to = filters.toDate {
        query = query.filter(\.$createdAt <= to)
    }

    return try await query
        .with(\.$user)
        .paginate(for: req)
}
```

---

## 7. Tri Dynamique

```swift
@Sendable
func index(req: Request) async throws -> Page<Todo> {
    // ?sortBy=title&direction=desc
    let sortBy = req.query[String.self, at: "sortBy"] ?? "createdAt"
    let directionStr = req.query[String.self, at: "direction"] ?? "asc"
    let direction: DatabaseQuery.Sort.Direction = directionStr == "desc" ? .descending : .ascending

    var query = Todo.query(on: req.db)

    // Tri dynamique basé sur le paramètre
    switch sortBy {
    case "title":
        query = query.sort(\.$title, direction)
    case "isCompleted":
        query = query.sort(\.$isCompleted, direction)
    case "createdAt":
        query = query.sort(\.$createdAt, direction)
    default:
        query = query.sort(\.$createdAt, .descending)
    }

    return try await query.paginate(for: req)
}
```

### Tri Multiple

```swift
// ?sort=createdAt:desc,title:asc
@Sendable
func multiSort(req: Request) async throws -> [Todo] {
    let sortParam = req.query[String.self, at: "sort"] ?? "createdAt:desc"

    var query = Todo.query(on: req.db)

    for sort in sortParam.split(separator: ",") {
        let parts = sort.split(separator: ":")
        let field = String(parts[0])
        let direction: DatabaseQuery.Sort.Direction = parts.count > 1 && parts[1] == "desc"
            ? .descending
            : .ascending

        switch field {
        case "title":
            query = query.sort(\.$title, direction)
        case "isCompleted":
            query = query.sort(\.$isCompleted, direction)
        case "createdAt":
            query = query.sort(\.$createdAt, direction)
        default:
            break
        }
    }

    return try await query.all()
}
```

---

## 8. Seeders

### Configuration (configure.swift)

```swift
import Vapor
import Fluent

func configure(_ app: Application) async throws {
    // ... database config ...

    // Migrations
    app.migrations.add(CreateUser())
    app.migrations.add(CreateTodo())

    try await app.autoMigrate()

    // Seeding (seulement si la base est vide)
    if try await User.query(on: app.db).count() == 0 {
        try await UserSeeder.seed(on: app.db)
        try await TodoSeeder.seed(on: app.db)
        app.logger.info("Database seeded successfully")
    }

    try routes(app)
}
```

### User Seeder

```swift
import Fluent

struct UserSeeder {
    static func seed(on db: Database) async throws {
        let users = [
            User(name: "John Doe", email: "john@example.com"),
            User(name: "Jane Smith", email: "jane@example.com"),
            User(name: "Alice Johnson", email: "alice@example.com"),
            User(name: "Bob Brown", email: "bob@example.com")
        ]

        for user in users {
            try await user.save(on: db)
        }
    }
}
```

### Todo Seeder (avec Relations)

```swift
import Fluent

struct TodoSeeder {
    static func seed(on db: Database) async throws {
        // Récupérer les users existants
        let users = try await User.query(on: db).all()

        guard users.count >= 2 else {
            throw Abort(.internalServerError, reason: "Seed users first")
        }

        let todos = [
            // Todos pour le premier user
            Todo(title: "Learn Vapor", isCompleted: true, userID: users[0].id!),
            Todo(title: "Build an API", isCompleted: false, userID: users[0].id!),
            Todo(title: "Deploy to production", isCompleted: false, userID: users[0].id!),

            // Todos pour le second user
            Todo(title: "Write documentation", isCompleted: true, userID: users[1].id!),
            Todo(title: "Add tests", isCompleted: false, userID: users[1].id!)
        ]

        for todo in todos {
            try await todo.save(on: db)
        }
    }
}
```

### Seeder avec Données Aléatoires

```swift
import Fluent

struct RandomTodoSeeder {
    static func seed(on db: Database, count: Int = 50) async throws {
        let users = try await User.query(on: db).all()
        let titles = [
            "Complete project report",
            "Review pull request",
            "Fix login bug",
            "Update dependencies",
            "Write unit tests",
            "Refactor authentication",
            "Optimize database queries",
            "Deploy staging environment"
        ]

        for _ in 0..<count {
            let todo = Todo(
                title: titles.randomElement()!,
                isCompleted: Bool.random(),
                userID: users.randomElement()!.id!
            )
            try await todo.save(on: db)
        }
    }
}
```

---

## 9. Sélection de Champs

### Limiter les Champs Retournés

```swift
// Ne charger que certains champs (optimisation)
let userNames = try await User.query(on: req.db)
    .field(\.$id)
    .field(\.$name)
    .all()
```

### DTOs pour les Réponses

```swift
struct TodoListDTO: Content {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let userName: String?
}

@Sendable
func index(req: Request) async throws -> [TodoListDTO] {
    let todos = try await Todo.query(on: req.db)
        .with(\.$user)
        .all()

    return todos.map { todo in
        TodoListDTO(
            id: todo.id!,
            title: todo.title,
            isCompleted: todo.isCompleted,
            userName: todo.user.name
        )
    }
}
```

---

## 10. Requêtes Raw SQL

### Quand l'ORM ne Suffit Pas

```swift
import FluentSQL

@Sendable
func complexQuery(req: Request) async throws -> [Todo] {
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError)
    }

    // Requête SQL brute
    let rows = try await sql.raw("""
        SELECT t.*, u.name as user_name
        FROM todos t
        INNER JOIN users u ON t.user_id = u.id
        WHERE t.is_completed = false
        AND t.created_at > NOW() - INTERVAL '7 days'
        ORDER BY t.created_at DESC
        LIMIT 10
    """).all(decoding: TodoWithUser.self)

    return rows
}

struct TodoWithUser: Content {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let userName: String
}
```

#### Bonnes Pratiques - SQL Raw
- Utiliser uniquement quand l'ORM ne peut pas exprimer la requête
- Toujours paramétrer pour éviter les injections SQL
- Documenter pourquoi le SQL brut est nécessaire

---

## Questions Fréquentes

### Q: Comment éviter les dépendances circulaires entre modèles?
**R:** Utilisez `@OptionalParent` ou des protocoles. Évitez les références bidirectionnelles profondes.

### Q: Quelle est la différence entre `with()` et `join()`?
**R:**
- `with()` : Eager loading, charge les relations en requêtes séparées
- `join()` : SQL JOIN, permet de filtrer sur les relations mais ne les charge pas automatiquement

### Q: Comment optimiser les requêtes lentes?
**R:**
1. Ajoutez des index sur les colonnes filtrées fréquemment
2. Utilisez `with()` pour éviter le N+1
3. Limitez les champs avec `field()`
4. Utilisez la pagination

### Q: Les seeders doivent-ils être exécutés en production?
**R:** Non, les seeders sont pour le développement/test. En production, utilisez des migrations pour les données initiales nécessaires.

---

## Checklist du Chapitre

- [ ] Implémenter une relation One-to-Many
- [ ] Comprendre les foreign keys et onDelete
- [ ] Utiliser le eager loading avec `with()`
- [ ] Implémenter la pagination native
- [ ] Créer des filtres dynamiques sur les requêtes
- [ ] Implémenter le tri dynamique
- [ ] Créer des seeders pour les données de test
- [ ] Combiner filtres, tri et pagination
- [ ] Optimiser les requêtes (N+1, champs sélectifs)
