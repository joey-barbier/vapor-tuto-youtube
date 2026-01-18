# Chapitre 2 - Controllers et Routes

## Objectifs d'apprentissage
- Comprendre le pattern Controller dans Vapor
- Maîtriser le système de routing
- Organiser son code avec des namespaces
- Gérer les paramètres de route et query strings

---

## 1. Architecture des Controllers

### Le Protocol RouteCollection

Un Controller dans Vapor implémente `RouteCollection`, ce qui permet de grouper des routes logiquement.

```swift
import Vapor

struct HelloWorldController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Toutes les routes de ce controller sont définies ici
        let users = routes.grouped("api", "users")

        users.get("list", use: list)
        users.get("admin", use: admin)
        users.get(":id", use: getById)
    }

    // Handlers
    @Sendable
    func list(req: Request) async throws -> String {
        return "Liste des utilisateurs"
    }

    @Sendable
    func admin(req: Request) async throws -> String {
        return "Page admin"
    }

    @Sendable
    func getById(req: Request) async throws -> String {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "ID manquant")
        }
        return "Utilisateur #\(id)"
    }
}
```

#### Bonnes Pratiques - Controllers
- Un controller = une ressource ou un domaine fonctionnel
- Utiliser `@Sendable` pour les handlers (requis en Swift 6)
- Garder les handlers courts (déléguer aux services pour la logique métier)
- Préférer `async throws` pour tous les handlers

---

## 2. Enregistrement des Controllers

### Dans routes.swift
```swift
import Vapor

func routes(_ app: Application) throws {
    // Enregistrement d'un seul controller
    try app.register(collection: HelloWorldController())

    // Enregistrement de plusieurs controllers
    try app.register(collection: UserController())
    try app.register(collection: TodoController())
    try app.register(collection: AuthController())
}
```

### Enregistrement automatique via Protocol
```swift
// Protocol pour l'enregistrement centralisé
protocol ControllersRegister {
    static func allCases() -> [RouteCollection]
    static func register(app: Application) throws
}

extension ControllersRegister {
    static func register(app: Application) throws {
        for controller in allCases() {
            try app.register(collection: controller)
        }
    }
}

// Implémentation
extension App.Bonus {
    enum Controllers: ControllersRegister {
        static func allCases() -> [RouteCollection] {
            [
                ControllerA(),
                ControllerB(),
                ControllerC()
            ]
        }
    }
}

// Utilisation dans routes.swift
func routes(_ app: Application) throws {
    try App.Bonus.Controllers.register(app: app)
}
```

---

## 3. Organisation avec Namespaces

### Pattern de Namespace Recommandé

```swift
// App.swift - Définition du namespace principal
enum App {}

extension App {
    // Sous-namespaces par domaine
    enum Bonus {
        enum Controllers {}
        enum Services {}
        enum Migrations {}
        enum Jobs {}
    }

    enum Core {
        enum Controllers {}
        enum Services {}
    }
}
```

### Exemple d'utilisation
```swift
// ControllerA.swift
extension App.Bonus.Controllers {
    struct ControllerA: RouteCollection {
        func boot(routes: any RoutesBuilder) throws {
            routes.grouped("bonus", "a").post(use: handle)
        }

        @Sendable
        func handle(req: Request) async throws -> HTTPStatus {
            return .ok
        }
    }
}
```

#### Bonnes Pratiques - Organisation
- Utiliser des `enum` vides comme namespaces (pas de state possible)
- Organiser par domaine fonctionnel, pas par type technique
- Garder une hiérarchie peu profonde (max 3 niveaux)
- Documenter la structure dans le README

---

## 4. Système de Routing

### Méthodes HTTP

```swift
func boot(routes: any RoutesBuilder) throws {
    let api = routes.grouped("api")

    // GET - Lecture
    api.get("users", use: getUsers)

    // POST - Création
    api.post("users", use: createUser)

    // PUT - Mise à jour complète
    api.put("users", ":id", use: updateUser)

    // PATCH - Mise à jour partielle
    api.patch("users", ":id", use: patchUser)

    // DELETE - Suppression
    api.delete("users", ":id", use: deleteUser)

    // HEAD - Métadonnées uniquement
    api.on(.HEAD, "users", use: headUsers)

    // OPTIONS - Méthodes supportées (utile pour CORS)
    api.on(.OPTIONS, "users", use: optionsUsers)
}
```

### Groupement de Routes

```swift
func boot(routes: any RoutesBuilder) throws {
    // Groupement simple
    let api = routes.grouped("api")

    // Groupement imbriqué
    let v1 = api.grouped("v1")
    let users = v1.grouped("users")

    // Résultat: /api/v1/users/...
    users.get(use: list)           // GET /api/v1/users
    users.post(use: create)        // POST /api/v1/users
    users.get(":id", use: getById) // GET /api/v1/users/:id
}
```

---

## 5. Paramètres de Route

### Paramètres de Chemin (Path Parameters)

```swift
// Route: GET /users/:id
func getById(req: Request) async throws -> User {
    // Extraction du paramètre
    guard let idString = req.parameters.get("id"),
          let id = UUID(uuidString: idString) else {
        throw Abort(.badRequest, reason: "ID invalide")
    }

    // Utilisation
    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound, reason: "Utilisateur non trouvé")
    }

    return user
}
```

### Paramètres Typés

```swift
// Vapor peut convertir automatiquement certains types
func getById(req: Request) async throws -> User {
    // Conversion automatique en UUID
    let id = try req.parameters.require("id", as: UUID.self)

    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound)
    }

    return user
}
```

### Query Parameters

```swift
// Route: GET /users?name=John&age=25&active=true

func search(req: Request) async throws -> [User] {
    // Paramètre optionnel
    let name: String? = req.query["name"]

    // Paramètre avec valeur par défaut
    let page = req.query[Int.self, at: "page"] ?? 1
    let perPage = req.query[Int.self, at: "perPage"] ?? 20

    // Paramètre requis (lève une erreur si absent)
    let sortBy = try req.query.get(String.self, at: "sortBy")

    // Paramètre booléen
    let active: Bool? = try? req.query.get(at: "active")

    // Construction de la requête
    var query = User.query(on: req.db)

    if let name = name {
        query = query.filter(\.$name == name)
    }

    if let active = active {
        query = query.filter(\.$isActive == active)
    }

    return try await query
        .sort(\.$createdAt, .descending)
        .range((page - 1) * perPage ..< page * perPage)
        .all()
}
```

---

## 6. Corps de Requête (Request Body)

### Décoder du JSON

```swift
// DTO pour la création
struct CreateUserDTO: Content {
    let name: String
    let email: String
    let password: String
}

func create(req: Request) async throws -> User {
    // Décodage automatique du JSON
    let dto = try req.content.decode(CreateUserDTO.self)

    // Validation (optionnel mais recommandé)
    guard !dto.name.isEmpty else {
        throw Abort(.badRequest, reason: "Le nom est requis")
    }

    guard dto.email.contains("@") else {
        throw Abort(.badRequest, reason: "Email invalide")
    }

    // Création de l'entité
    let user = User(
        name: dto.name,
        email: dto.email,
        passwordHash: try Bcrypt.hash(dto.password)
    )

    try await user.save(on: req.db)
    return user
}
```

### Validation avec Validatable

```swift
struct CreateUserDTO: Content, Validatable {
    let name: String
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty)
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}

func create(req: Request) async throws -> User {
    // Validation automatique
    try CreateUserDTO.validate(content: req)

    let dto = try req.content.decode(CreateUserDTO.self)
    // ...
}
```

---

## 7. Réponses HTTP

### Types de Retour

```swift
// Retourner du texte
func getText(req: Request) async throws -> String {
    return "Hello, World!"
}

// Retourner du JSON (Content)
func getUser(req: Request) async throws -> User {
    return try await User.find(id, on: req.db)!
}

// Retourner un statut HTTP
func delete(req: Request) async throws -> HTTPStatus {
    try await user.delete(on: req.db)
    return .noContent  // 204
}

// Retourner une réponse personnalisée
func custom(req: Request) async throws -> Response {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    headers.add(name: "X-Custom-Header", value: "value")

    return Response(
        status: .created,
        headers: headers,
        body: .init(string: "{\"success\": true}")
    )
}

// Retourner une vue Leaf
func page(req: Request) async throws -> View {
    return try await req.view.render("index", ["title": "Accueil"])
}
```

### Codes de Statut HTTP Courants

```swift
// Succès
.ok           // 200 - Requête réussie
.created      // 201 - Ressource créée
.accepted     // 202 - Requête acceptée (traitement async)
.noContent    // 204 - Succès sans contenu

// Erreurs Client
.badRequest         // 400 - Requête malformée
.unauthorized       // 401 - Non authentifié
.forbidden          // 403 - Non autorisé
.notFound           // 404 - Ressource non trouvée
.conflict           // 409 - Conflit (ex: email déjà utilisé)
.unprocessableEntity // 422 - Validation échouée

// Erreurs Serveur
.internalServerError // 500 - Erreur interne
.serviceUnavailable  // 503 - Service indisponible
```

---

## 8. Gestion des Erreurs

### Abort pour les Erreurs HTTP

```swift
func getById(req: Request) async throws -> User {
    guard let id = req.parameters.get("id", as: UUID.self) else {
        throw Abort(.badRequest, reason: "ID invalide ou manquant")
    }

    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound, reason: "Utilisateur non trouvé")
    }

    return user
}
```

### Erreurs Personnalisées

```swift
enum UserError: AbortError {
    case emailAlreadyExists
    case invalidPassword
    case accountLocked

    var status: HTTPResponseStatus {
        switch self {
        case .emailAlreadyExists: return .conflict
        case .invalidPassword: return .unauthorized
        case .accountLocked: return .forbidden
        }
    }

    var reason: String {
        switch self {
        case .emailAlreadyExists: return "Cet email est déjà utilisé"
        case .invalidPassword: return "Mot de passe incorrect"
        case .accountLocked: return "Ce compte est verrouillé"
        }
    }
}

// Utilisation
throw UserError.emailAlreadyExists
```

---

## 9. Patterns Avancés

### Route avec Plusieurs Méthodes

```swift
func boot(routes: any RoutesBuilder) throws {
    let users = routes.grouped("users")

    // Même chemin, méthodes différentes
    users.on(.GET, ":id", use: getUser)
    users.on(.PUT, ":id", use: updateUser)
    users.on(.DELETE, ":id", use: deleteUser)
}
```

### Routes Catch-All

```swift
// Capture tout après /files/
// Ex: /files/path/to/document.pdf
routes.get("files", "**") { req -> String in
    let path = req.parameters.getCatchall().joined(separator: "/")
    return "Fichier demandé: \(path)"
}
```

### Redirection

```swift
func oldEndpoint(req: Request) async throws -> Response {
    return req.redirect(to: "/api/v2/users", redirectType: .permanent)
}
```

---

## Questions Fréquentes

### Q: Quelle est la différence entre `grouped()` et définir le chemin complet?
**R:** `grouped()` crée un builder réutilisable et permet d'ajouter des middlewares à un groupe de routes. C'est plus maintenable et évite la répétition.

### Q: Pourquoi utiliser `@Sendable`?
**R:** Swift 6 exige que les closures passées entre threads soient `@Sendable`. Cela garantit la sécurité de la concurrence.

### Q: Comment organiser un gros projet avec beaucoup de routes?
**R:** Utilisez des namespaces (`enum App { enum Controllers }`), un controller par ressource, et le pattern d'enregistrement centralisé avec un protocol.

### Q: Quand utiliser PUT vs PATCH?
**R:** PUT remplace entièrement la ressource (tous les champs requis). PATCH fait une mise à jour partielle (seuls les champs envoyés sont modifiés).

---

## Checklist du Chapitre

- [ ] Comprendre le protocol RouteCollection
- [ ] Savoir créer et enregistrer un Controller
- [ ] Maîtriser le groupement de routes
- [ ] Savoir extraire les paramètres de chemin (:id)
- [ ] Savoir extraire les query parameters (?key=value)
- [ ] Savoir décoder le corps JSON des requêtes
- [ ] Connaître les codes de statut HTTP courants
- [ ] Savoir gérer les erreurs avec Abort
- [ ] Organiser le code avec des namespaces
