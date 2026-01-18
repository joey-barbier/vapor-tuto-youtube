# Chapitre 3 - Base de Données avec Fluent

## Objectifs d'apprentissage
- Configurer Fluent avec PostgreSQL
- Créer des modèles (Models)
- Gérer les migrations
- Effectuer des opérations CRUD
- Utiliser les DTOs (Data Transfer Objects)

---

## 1. Configuration de la Base de Données

### Dépendances (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
    .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
    .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "Fluent", package: "fluent"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
        ]
    )
]
```

### Autres Drivers Disponibles
```swift
// SQLite (idéal pour le développement)
.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0")

// MySQL/MariaDB
.package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0")

// MongoDB
.package(url: "https://github.com/vapor/fluent-mongo-driver.git", from: "1.0.0")
```

---

## 2. Configuration dans configure.swift

```swift
import Vapor
import Fluent
import FluentPostgresDriver

func configure(_ app: Application) async throws {
    // Configuration PostgreSQL
    app.databases.use(
        DatabaseConfigurationFactory.postgres(
            configuration: .init(
                hostname: Environment.get("DATABASE_HOST") ?? "localhost",
                port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
                username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
                password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
                database: Environment.get("DATABASE_NAME") ?? "vapor_database",
                tls: .prefer(try .init(configuration: .clientDefault))
            )
        ),
        as: .psql
    )

    // Enregistrement des migrations
    app.migrations.add(CreateTodo())
    app.migrations.add(TodoAddSubtitle())

    // ⚠️ autoMigrate() exécute les migrations automatiquement au démarrage
    // Pratique en dev, utilisable en prod si vous comprenez les implications:
    // - Migrations exécutées à chaque démarrage (idempotent si bien écrites)
    // - Pas de contrôle manuel du timing
    // Alternative prod: swift run App migrate (contrôle manuel)
    try await app.autoMigrate()

    // Routes
    try routes(app)
}
```

### Configuration SQLite (Alternative pour le Dev)

```swift
import FluentSQLiteDriver

// En mémoire (données perdues à chaque restart)
app.databases.use(.sqlite(.memory), as: .sqlite)

// Fichier persistant
app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
```

#### Bonnes Pratiques - Configuration
- Toujours utiliser des variables d'environnement pour les credentials
- `autoMigrate()` uniquement en développement
- En production, utiliser `vapor migrate` manuellement
- Activer TLS pour les connexions en production

---

## 3. Création de Modèles

### Structure d'un Modèle Fluent

```swift
import Fluent
import Vapor

final class Todo: Model, Content, @unchecked Sendable {
    // Nom de la table en base de données
    static let schema = "todos"

    // Clé primaire (UUID par défaut)
    @ID(key: .id)
    var id: UUID?

    // Champ texte obligatoire
    @Field(key: "title")
    var title: String

    // Champ texte optionnel
    @Field(key: "subtitle")
    var subtitle: String?

    // Champ booléen
    @Field(key: "is_completed")
    var isCompleted: Bool

    // Timestamp automatique à la création
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // Timestamp automatique à la mise à jour
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // Constructeur vide requis par Fluent
    init() {}

    // Constructeur pratique
    init(id: UUID? = nil, title: String, subtitle: String? = nil, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isCompleted = isCompleted
    }
}
```

### Property Wrappers Disponibles

| Wrapper | Usage |
|---------|-------|
| `@ID` | Clé primaire |
| `@Field` | Champ standard |
| `@OptionalField` | Champ optionnel explicite |
| `@Timestamp` | Date automatique (.create, .update, .delete) |
| `@Parent` | Relation vers le parent (foreign key) |
| `@Children` | Relation vers les enfants |
| `@Siblings` | Relation many-to-many |
| `@OptionalParent` | Relation parent optionnelle |
| `@Enum` | Champ énumération |

#### Bonnes Pratiques - Modèles
- Toujours implémenter `@unchecked Sendable` (requis pour la concurrence)
- Utiliser `Content` pour la sérialisation JSON automatique
- Préférer `UUID` comme type d'ID
- Utiliser snake_case pour les noms de colonnes
- Toujours avoir un constructeur `init()` vide

---

## 4. Migrations

### Migration de Création

```swift
import Fluent

struct CreateTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .id()
            .field("title", .string, .required)
            .field("subtitle", .string)
            .field("is_completed", .bool, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Todo.schema).delete()
    }
}
```

### Migration de Modification

```swift
struct TodoAddSubtitle: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .field("subtitle", .string)  // Ajout d'une colonne
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Todo.schema)
            .deleteField("subtitle")
            .update()
    }
}
```

### Types de Champs Disponibles

```swift
.bool           // Boolean
.int            // Integer
.int8, .int16, .int32, .int64
.uint8, .uint16, .uint32, .uint64
.double         // Double precision float
.string         // Text (VARCHAR)
.date           // Date only
.datetime       // Date + Time
.time           // Time only
.uuid           // UUID
.json           // JSON/JSONB
.data           // Binary data
.array(of: .string)  // Array de strings
.dictionary     // Key-value pairs
.enum(...)      // Enumeration
```

### Contraintes

```swift
try await database.schema("todos")
    .id()
    .field("title", .string, .required)              // NOT NULL
    .field("email", .string, .required)
    .unique(on: "email")                              // UNIQUE
    .field("user_id", .uuid, .required,
           .references("users", "id", onDelete: .cascade))  // Foreign Key
    .create()
```

#### Bonnes Pratiques - Migrations
- Une migration = une modification atomique
- Toujours implémenter `revert()` pour pouvoir rollback
- Nommer les migrations de façon descriptive
- Ne jamais modifier une migration déjà exécutée en production
- Créer une nouvelle migration pour chaque changement

---

## 5. Opérations CRUD

### Controller CRUD Complet

```swift
import Fluent
import Vapor

struct TodoController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let todos = routes.grouped("api", "todos")

        todos.get(use: index)           // GET /api/todos
        todos.get(":id", use: show)     // GET /api/todos/:id
        todos.post(use: create)         // POST /api/todos
        todos.put(":id", use: update)   // PUT /api/todos/:id
        todos.delete(":id", use: delete) // DELETE /api/todos/:id
    }

    // READ - Liste tous les todos
    @Sendable
    func index(req: Request) async throws -> [Todo] {
        try await Todo.query(on: req.db).all()
    }

    // READ - Un seul todo par ID
    @Sendable
    func show(req: Request) async throws -> Todo {
        guard let todo = try await Todo.find(
            req.parameters.get("id"),
            on: req.db
        ) else {
            throw Abort(.notFound, reason: "Todo non trouvé")
        }
        return todo
    }

    // CREATE - Nouveau todo
    @Sendable
    func create(req: Request) async throws -> Todo {
        let dto = try req.content.decode(TodoDTO.self)
        let todo = dto.toModel()
        try await todo.save(on: req.db)
        return todo
    }

    // UPDATE - Mise à jour complète
    @Sendable
    func update(req: Request) async throws -> Todo {
        guard let todo = try await Todo.find(
            req.parameters.get("id"),
            on: req.db
        ) else {
            throw Abort(.notFound)
        }

        let dto = try req.content.decode(TodoDTO.self)
        todo.title = dto.title ?? todo.title
        todo.subtitle = dto.subtitle
        todo.isCompleted = dto.isCompleted ?? todo.isCompleted

        try await todo.save(on: req.db)
        return todo
    }

    // DELETE - Suppression
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let todo = try await Todo.find(
            req.parameters.get("id"),
            on: req.db
        ) else {
            throw Abort(.notFound)
        }

        try await todo.delete(on: req.db)
        return .noContent
    }
}
```

---

## 6. Data Transfer Objects (DTOs)

### Pourquoi utiliser des DTOs?

1. **Sécurité** : Ne pas exposer tous les champs du modèle
2. **Validation** : Valider les entrées avant conversion
3. **Flexibilité** : Différentes représentations pour différents endpoints
4. **Découplage** : Séparer la logique API de la logique DB

### Exemple de DTO

```swift
import Vapor

struct TodoDTO: Content {
    var id: UUID?
    var title: String?
    var subtitle: String?
    var isCompleted: Bool?

    // Conversion DTO -> Model
    func toModel() -> Todo {
        let model = Todo()
        model.id = self.id
        if let title = self.title {
            model.title = title
        }
        model.subtitle = self.subtitle
        if let isCompleted = self.isCompleted {
            model.isCompleted = isCompleted
        }
        return model
    }
}

// Extension sur le Model pour la conversion inverse
extension Todo {
    func toDTO() -> TodoDTO {
        TodoDTO(
            id: self.id,
            title: self.title,
            subtitle: self.subtitle,
            isCompleted: self.isCompleted
        )
    }
}
```

### DTO avec Validation

```swift
struct CreateTodoDTO: Content, Validatable {
    let title: String
    let subtitle: String?

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: !.empty && .count(1...255))
    }

    func toModel() -> Todo {
        Todo(title: title, subtitle: subtitle)
    }
}
```

---

## 7. Requêtes Avancées

### Query Builder

```swift
// Tous les todos
let allTodos = try await Todo.query(on: req.db).all()

// Premier résultat
let firstTodo = try await Todo.query(on: req.db).first()

// Filtrage
let completedTodos = try await Todo.query(on: req.db)
    .filter(\.$isCompleted == true)
    .all()

// Tri
let sortedTodos = try await Todo.query(on: req.db)
    .sort(\.$createdAt, .descending)
    .all()

// Limite et offset
let paginatedTodos = try await Todo.query(on: req.db)
    .range(0..<10)  // 10 premiers
    .all()

// Combinaison
let recentCompleted = try await Todo.query(on: req.db)
    .filter(\.$isCompleted == true)
    .sort(\.$createdAt, .descending)
    .range(0..<5)
    .all()
```

### Opérateurs de Filtre

```swift
// Égalité
.filter(\.$status == .active)

// Différence
.filter(\.$status != .deleted)

// Comparaisons
.filter(\.$age > 18)
.filter(\.$age >= 18)
.filter(\.$age < 65)
.filter(\.$age <= 65)

// Contient (LIKE %value%)
.filter(\.$name ~~ "John")

// Commence par (LIKE value%)
.filter(\.$name =~ "Jo")

// Termine par (LIKE %value)
.filter(\.$name ~= "hn")

// Dans une liste (IN)
.filter(\.$status ~~ [.active, .pending])

// NULL
.filter(\.$deletedAt == nil)
```

### Agrégations

```swift
// Compter
let count = try await Todo.query(on: req.db).count()

// Somme
let total = try await Todo.query(on: req.db)
    .sum(\.$amount)

// Moyenne
let average = try await Todo.query(on: req.db)
    .average(\.$rating)

// Min/Max
let oldest = try await Todo.query(on: req.db)
    .min(\.$createdAt)
```

---

## 8. Transactions

```swift
func transferMoney(req: Request) async throws -> HTTPStatus {
    let fromId = try req.content.get(UUID.self, at: "from")
    let toId = try req.content.get(UUID.self, at: "to")
    let amount = try req.content.get(Double.self, at: "amount")

    // Transaction atomique
    try await req.db.transaction { database in
        guard let fromAccount = try await Account.find(fromId, on: database),
              let toAccount = try await Account.find(toId, on: database) else {
            throw Abort(.notFound)
        }

        guard fromAccount.balance >= amount else {
            throw Abort(.badRequest, reason: "Solde insuffisant")
        }

        fromAccount.balance -= amount
        toAccount.balance += amount

        try await fromAccount.save(on: database)
        try await toAccount.save(on: database)
    }

    return .ok
}
```

---

## 9. Soft Delete

```swift
final class Todo: Model, Content, @unchecked Sendable {
    static let schema = "todos"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    // Timestamp pour soft delete
    @Timestamp(key: "deleted_at", on: .delete)
    var deletedAt: Date?

    init() {}
}

// Utilisation
// delete() marque deleted_at au lieu de supprimer
try await todo.delete(on: req.db)

// Restaurer
try await todo.restore(on: req.db)

// Supprimer définitivement
try await todo.delete(force: true, on: req.db)

// Requêtes
// Par défaut, les éléments soft-deleted sont exclus
let activeTodos = try await Todo.query(on: req.db).all()

// Inclure les soft-deleted
let allTodos = try await Todo.query(on: req.db)
    .withDeleted()
    .all()

// Uniquement les soft-deleted
let deletedTodos = try await Todo.query(on: req.db)
    .withDeleted()
    .filter(\.$deletedAt != nil)
    .all()
```

---

## Questions Fréquentes

### Q: Quand utiliser `save()` vs `create()` vs `update()`?
**R:**
- `save()` : Crée si nouveau (pas d'id), met à jour sinon
- `create()` : Toujours crée (erreur si l'id existe déjà)
- `update()` : Toujours met à jour (erreur si n'existe pas)

### Q: Comment gérer les migrations en production?
**R:** Ne jamais utiliser `autoMigrate()` en production. Utilisez:
```bash
vapor run migrate          # Exécuter les migrations
vapor run migrate --revert # Rollback
```

### Q: Pourquoi `@unchecked Sendable`?
**R:** Les modèles Fluent ont des états mutables internes. `@unchecked Sendable` indique au compilateur que vous garantissez la thread-safety (Fluent le gère).

### Q: Comment optimiser les requêtes lentes?
**R:**
1. Ajoutez des index sur les colonnes fréquemment filtrées
2. Utilisez `with()` pour eager loading des relations
3. Limitez les colonnes sélectionnées avec `field()`
4. Utilisez la pagination pour les grandes collections

---

## Checklist du Chapitre

- [ ] Configurer Fluent avec PostgreSQL
- [ ] Comprendre les property wrappers (@ID, @Field, etc.)
- [ ] Créer des modèles conformes aux bonnes pratiques
- [ ] Écrire des migrations create et update
- [ ] Implémenter les 5 opérations CRUD
- [ ] Utiliser des DTOs pour découpler API et DB
- [ ] Maîtriser le query builder (filter, sort, range)
- [ ] Comprendre les transactions
- [ ] Implémenter le soft delete si nécessaire
