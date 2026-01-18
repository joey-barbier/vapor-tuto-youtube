# Chapitre 4 - Middleware

## Objectifs d'apprentissage
- Comprendre le concept de middleware
- Créer des middlewares personnalisés
- Configurer CORS
- Gérer les erreurs de façon centralisée
- Servir des fichiers statiques
- Implémenter l'authentification basique

---

## 1. Concept de Middleware

### Qu'est-ce qu'un Middleware?

Un middleware est un composant qui intercepte les requêtes HTTP avant qu'elles n'atteignent le handler, et/ou les réponses avant qu'elles ne soient envoyées au client.

```
Client → Middleware A → Middleware B → Handler → Middleware B → Middleware A → Client
           (entrée)       (entrée)                  (sortie)       (sortie)
```

### Cas d'Usage Courants
- **Logging** : Enregistrer les requêtes/réponses
- **Authentification** : Vérifier les credentials
- **Autorisation** : Vérifier les permissions
- **CORS** : Gérer les requêtes cross-origin
- **Rate Limiting** : Limiter le nombre de requêtes
- **Compression** : Compresser les réponses
- **Error Handling** : Centraliser la gestion des erreurs

---

## 2. Créer un Middleware Personnalisé

### Structure de Base

```swift
import Vapor

struct LoggingMiddleware: AsyncMiddleware {
    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // AVANT le handler
        request.logger.info("👋🏻 Request received: \(request.method) \(request.url.path)")
        let start = Date()

        // Appel du handler (ou du middleware suivant)
        let response = try await next.respond(to: request)

        // APRÈS le handler
        let duration = Date().timeIntervalSince(start)
        request.logger.info("✅ Response: \(response.status.code) in \(String(format: "%.3f", duration))s")

        return response
    }
}
```

### Enregistrement Global (configure.swift)

```swift
import Vapor

func configure(_ app: Application) async throws {
    // Les middlewares s'exécutent dans l'ordre d'ajout
    app.middleware.use(LoggingMiddleware())

    try routes(app)
}
```

### Enregistrement sur un Groupe de Routes

```swift
func boot(routes: any RoutesBuilder) throws {
    // Middleware appliqué uniquement à ce groupe
    let protected = routes.grouped(AuthMiddleware())

    protected.get("profile", use: profile)
    protected.get("settings", use: settings)
}
```

---

## 3. Middleware de Logging

### Version Complète

```swift
struct LoggingMiddleware: AsyncMiddleware {
    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // Générer un ID unique pour tracer la requête
        let requestId = UUID().uuidString.prefix(8)

        // Log de la requête entrante
        request.logger.info("""
            [\(requestId)] → \(request.method) \(request.url.path)
            Headers: \(request.headers.description)
            Query: \(request.url.query ?? "none")
            """)

        let start = Date()

        do {
            let response = try await next.respond(to: request)

            // Log de la réponse
            let duration = Date().timeIntervalSince(start) * 1000
            request.logger.info("""
                [\(requestId)] ← \(response.status.code) \(response.status.reasonPhrase)
                Duration: \(String(format: "%.2f", duration))ms
                """)

            return response
        } catch {
            // Log des erreurs
            let duration = Date().timeIntervalSince(start) * 1000
            request.logger.error("""
                [\(requestId)] ✗ Error: \(error.localizedDescription)
                Duration: \(String(format: "%.2f", duration))ms
                """)
            throw error
        }
    }
}
```

---

## 4. CORS Middleware

### Configuration CORS

```swift
import Vapor

func configure(_ app: Application) async throws {
    // Configuration CORS
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,  // ou .custom("https://example.com")
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS, .PATCH],
        allowedHeaders: [
            .accept,
            .authorization,
            .contentType,
            .origin,
            .xRequestedWith,
            .init("X-Custom-Header")  // Headers personnalisés
        ],
        allowCredentials: true,
        cacheExpiration: 600  // Cache preflight pendant 10 minutes
    )

    app.middleware.use(CORSMiddleware(configuration: corsConfig))
}
```

### Options AllowedOrigin

```swift
// Tous les domaines (développement uniquement!)
.all

// Un domaine spécifique
.custom("https://example.com")

// Aucun (désactive CORS)
.none

// Origines multiples avec logique personnalisée
.originBased  // Lit l'header Origin de la requête

// Custom logic
.any(["https://app.example.com", "https://admin.example.com"])
```

#### Bonnes Pratiques - CORS
- Ne jamais utiliser `.all` en production
- Lister explicitement les origines autorisées
- Limiter les méthodes au strict nécessaire
- Documenter les headers personnalisés

---

## 5. Middleware de Gestion des Erreurs

### Erreurs Personnalisées

```swift
import Vapor

// Définition des erreurs métier
enum AppError: Error {
    case idNotFound
    case databaseConnection
    case invalidInput(String)
    case unauthorized
    case forbidden

    var httpStatus: HTTPStatus {
        switch self {
        case .idNotFound: return .notFound
        case .databaseConnection: return .serviceUnavailable
        case .invalidInput: return .badRequest
        case .unauthorized: return .unauthorized
        case .forbidden: return .forbidden
        }
    }

    var reason: String {
        switch self {
        case .idNotFound:
            return "La ressource demandée n'existe pas"
        case .databaseConnection:
            return "Erreur de connexion à la base de données"
        case .invalidInput(let field):
            return "Champ invalide: \(field)"
        case .unauthorized:
            return "Authentification requise"
        case .forbidden:
            return "Accès non autorisé"
        }
    }
}
```

### Middleware de Gestion

```swift
struct ErrorResponse: Content {
    let error: Bool
    let code: UInt
    let message: String
}

struct CustomErrorMiddleware: AsyncMiddleware {
    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as AppError {
            return try await handleAppError(error, request: request)
        } catch let error as AbortError {
            return try await handleAbortError(error, request: request)
        } catch {
            return try await handleUnknownError(error, request: request)
        }
    }

    private func handleAppError(_ error: AppError, request: Request) async throws -> Response {
        request.logger.warning("App Error: \(error.reason)")

        let errorResponse = ErrorResponse(
            error: true,
            code: error.httpStatus.code,
            message: error.reason
        )

        let response = Response(status: error.httpStatus)
        try response.content.encode(errorResponse)
        return response
    }

    private func handleAbortError(_ error: AbortError, request: Request) async throws -> Response {
        request.logger.warning("Abort Error: \(error.reason)")

        let errorResponse = ErrorResponse(
            error: true,
            code: error.status.code,
            message: error.reason
        )

        let response = Response(status: error.status)
        try response.content.encode(errorResponse)
        return response
    }

    private func handleUnknownError(_ error: Error, request: Request) async throws -> Response {
        // En production, ne pas exposer les détails de l'erreur
        request.logger.error("Unexpected Error: \(error.localizedDescription)")

        let errorResponse = ErrorResponse(
            error: true,
            code: 500,
            message: "Une erreur inattendue s'est produite"
        )

        let response = Response(status: .internalServerError)
        try response.content.encode(errorResponse)
        return response
    }
}
```

### Utilisation dans les Controllers

```swift
func getUser(req: Request) async throws -> User {
    guard let id = req.parameters.get("id", as: UUID.self) else {
        throw AppError.invalidInput("id")
    }

    guard let user = try await User.find(id, on: req.db) else {
        throw AppError.idNotFound
    }

    return user
}
```

---

## 6. Authentification avec Bearer Token

### Modèle User Authenticatable

```swift
import Vapor

struct User: Content, Authenticatable {
    var id: UUID
    var username: String
    var role: Role

    enum Role: String, Content {
        case admin
        case user
    }

    // Utilisateur de test
    static let horka = User(
        id: UUID(),
        username: "horka",
        role: .admin
    )
}
```

### Middleware Bearer Token

```swift
import Vapor

struct AuthMiddleware: AsyncBearerAuthenticator {
    func authenticate(
        bearer: BearerAuthorization,
        for request: Request
    ) async throws {
        // Vérification du token
        // En production, validez contre une DB ou un service JWT
        guard bearer.token == "MonSuperToken" else {
            throw Abort(.unauthorized, reason: "Token invalide")
        }

        // Authentifier l'utilisateur
        request.auth.login(User.horka)
    }
}
```

### Utilisation dans les Routes

```swift
func boot(routes: any RoutesBuilder) throws {
    let todos = routes.grouped("api", "todos")

    // Routes publiques
    todos.get(use: index)
    todos.get(":id", use: show)

    // Routes protégées
    let protected = todos.grouped(
        AuthMiddleware(),
        User.guardMiddleware()  // Vérifie qu'un User est authentifié
    )

    protected.post(use: create)
    protected.put(":id", use: update)
    protected.delete(":id", use: delete)
}
```

### Accéder à l'Utilisateur Authentifié

```swift
func create(req: Request) async throws -> Todo {
    // Récupérer l'utilisateur authentifié
    let user = try req.auth.require(User.self)

    // Utiliser les infos de l'utilisateur
    req.logger.info("Todo créé par: \(user.username)")

    let dto = try req.content.decode(CreateTodoDTO.self)
    let todo = dto.toModel()
    try await todo.save(on: req.db)
    return todo
}
```

---

## 7. FileMiddleware - Servir des Fichiers Statiques

### Configuration

```swift
import Vapor

func configure(_ app: Application) async throws {
    // Servir les fichiers du dossier Public/
    app.middleware.use(FileMiddleware(
        publicDirectory: app.directory.publicDirectory
    ))

    try routes(app)
}
```

### Structure du Dossier Public

```
MonProjet/
├── Public/
│   ├── css/
│   │   └── style.css
│   ├── js/
│   │   └── app.js
│   ├── images/
│   │   └── logo.png
│   └── favicon.ico
```

### Accès aux Fichiers

```
GET /css/style.css      → Public/css/style.css
GET /js/app.js          → Public/js/app.js
GET /images/logo.png    → Public/images/logo.png
```

#### Bonnes Pratiques - Fichiers Statiques
- Utiliser un CDN en production pour les assets
- Configurer le cache (Cache-Control headers)
- Ne jamais exposer de fichiers sensibles
- Minifier CSS/JS en production

---

## 8. Middleware de Rate Limiting

### Implémentation Simple

```swift
import Vapor

actor RateLimiter {
    private var requests: [String: [Date]] = [:]
    private let maxRequests: Int
    private let timeWindow: TimeInterval

    init(maxRequests: Int, perSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = perSeconds
    }

    func shouldAllow(identifier: String) -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-timeWindow)

        // Nettoyer les anciennes requêtes
        requests[identifier] = requests[identifier]?.filter { $0 > windowStart } ?? []

        // Vérifier la limite
        if (requests[identifier]?.count ?? 0) >= maxRequests {
            return false
        }

        // Enregistrer la nouvelle requête
        requests[identifier, default: []].append(now)
        return true
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter

    init(maxRequests: Int = 100, perSeconds: TimeInterval = 60) {
        self.limiter = RateLimiter(maxRequests: maxRequests, perSeconds: perSeconds)
    }

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // Identifier par IP
        let identifier = request.remoteAddress?.ipAddress ?? "unknown"

        guard await limiter.shouldAllow(identifier: identifier) else {
            throw Abort(.tooManyRequests, reason: "Trop de requêtes, réessayez plus tard")
        }

        return try await next.respond(to: request)
    }
}
```

---

## 9. Ordre des Middlewares

L'ordre d'ajout des middlewares est crucial :

```swift
func configure(_ app: Application) async throws {
    // 1. Logging en premier (log toutes les requêtes)
    app.middleware.use(LoggingMiddleware())

    // 2. CORS (doit répondre aux preflight avant auth)
    app.middleware.use(CORSMiddleware(configuration: corsConfig))

    // 3. Gestion des erreurs (attrape les erreurs des middlewares suivants)
    app.middleware.use(CustomErrorMiddleware())

    // 4. Rate Limiting
    app.middleware.use(RateLimitMiddleware())

    // 5. Fichiers statiques
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Note: L'auth est généralement appliquée par groupe de routes, pas globalement
}
```

---

## 10. Middleware Conditionnel

```swift
struct ConditionalMiddleware: AsyncMiddleware {
    let condition: (Request) -> Bool
    let middleware: any AsyncMiddleware

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        if condition(request) {
            return try await middleware.respond(to: request, chainingTo: next)
        } else {
            return try await next.respond(to: request)
        }
    }
}

// Utilisation
let adminOnly = ConditionalMiddleware(
    condition: { $0.url.path.hasPrefix("/admin") },
    middleware: AdminAuthMiddleware()
)
app.middleware.use(adminOnly)
```

---

## Questions Fréquentes

### Q: Quelle est la différence entre Middleware et un simple handler?
**R:** Un middleware intercepte TOUTES les requêtes (ou celles d'un groupe), tandis qu'un handler ne traite qu'une route spécifique. Les middlewares sont parfaits pour la logique transversale (auth, logging, etc.).

### Q: Comment passer des données d'un middleware à un handler?
**R:** Utilisez `request.storage`:
```swift
extension Request {
    var customData: String? {
        get { storage[CustomDataKey.self] }
        set { storage[CustomDataKey.self] = newValue }
    }
}
private struct CustomDataKey: StorageKey {
    typealias Value = String
}
```

### Q: Les middlewares sont-ils thread-safe?
**R:** Oui, si vous utilisez `AsyncMiddleware` et évitez les états mutables partagés. Pour les états partagés, utilisez un `actor`.

### Q: Comment désactiver un middleware pour certaines routes?
**R:** Créez un groupe sans ce middleware, ou utilisez un middleware conditionnel.

---

## Checklist du Chapitre

- [ ] Comprendre le flux requête → middlewares → handler → réponse
- [ ] Créer un middleware de logging personnalisé
- [ ] Configurer CORS pour la production
- [ ] Implémenter une gestion centralisée des erreurs
- [ ] Configurer l'authentification Bearer Token
- [ ] Servir des fichiers statiques avec FileMiddleware
- [ ] Comprendre l'ordre d'exécution des middlewares
- [ ] Savoir appliquer un middleware à un groupe de routes
