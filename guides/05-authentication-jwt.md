# Chapitre 5 - Authentification avec JWT

## Objectifs d'apprentissage
- Comprendre le fonctionnement des JWT
- Configurer JWT dans Vapor
- Créer un système de login/register
- Implémenter un middleware d'authentification JWT
- Gérer les rôles et permissions

---

## 1. Introduction aux JWT

### Qu'est-ce qu'un JWT?

**J**SON **W**eb **T**oken est un standard (RFC 7519) pour transmettre des informations de façon sécurisée entre parties.

### Structure d'un JWT

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwicm9sZSI6ImFkbWluIn0.signature
│──────────── Header ────────────│──────────── Payload ──────────────│── Signature ──│
```

1. **Header** : Algorithme + type de token
2. **Payload** : Les claims (données)
3. **Signature** : Vérifie l'intégrité

### Avantages des JWT
- **Stateless** : Pas besoin de stocker les sessions côté serveur
- **Scalable** : Fonctionne avec plusieurs serveurs
- **Cross-domain** : Peut être utilisé entre différents domaines
- **Mobile-friendly** : Parfait pour les apps mobiles et SPA

---

## 2. Configuration JWT

### Dépendances (Package.swift)

> **Note** : Ce guide utilise JWT 4.x. La version 5.x existe avec une API légèrement différente (basée sur JWTKit). Les concepts restent identiques.

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
    .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),  // ou "5.0.0" pour la dernière version
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "JWT", package: "jwt"),
        ]
    )
]
```

### Configuration (configure.swift)

```swift
import Vapor
import JWT

func configure(_ app: Application) async throws {
    // Configuration de la clé de signature
    // IMPORTANT: Utiliser une variable d'environnement en production!
    let secretKey = Environment.get("JWT_SECRET") ?? "supersecretkey-change-in-production"

    app.jwt.signers.use(
        .hs256(key: secretKey),
        kid: .init(string: "basic")
    )

    try routes(app)
}
```

### Algorithmes de Signature Disponibles

```swift
// Symétrique (même clé pour signer et vérifier)
.hs256(key: "secret")  // HMAC-SHA256
.hs384(key: "secret")  // HMAC-SHA384
.hs512(key: "secret")  // HMAC-SHA512

// Asymétrique (clé privée pour signer, publique pour vérifier)
.rs256(key: .private(pem: privateKeyPEM))  // RSA-SHA256
.es256(key: .private(pem: privateKeyPEM))  // ECDSA-SHA256
```

#### Bonnes Pratiques - Configuration
- Clé secrète d'au moins 256 bits (32 caractères)
- Toujours utiliser des variables d'environnement
- En production, préférer les algorithmes asymétriques (RS256, ES256)
- Garder le `kid` (key ID) pour permettre la rotation des clés

---

## 3. Modèle User

```swift
import Vapor

struct User: Content, Authenticatable {
    var id: UUID
    var username: String
    var role: Role

    enum Role: String, Content, Codable {
        case admin
        case user
        case guest
    }

    // Utilisateur de test
    static let horka = User(
        id: UUID(),
        username: "horka",
        role: .admin
    )
}
```

### Version avec Base de Données

```swift
import Fluent
import Vapor

final class User: Model, Content, Authenticatable, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Enum(key: "role")
    var role: Role

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    enum Role: String, Codable {
        case admin
        case user
        case guest
    }

    init() {}

    init(id: UUID? = nil, username: String, email: String, passwordHash: String, role: Role = .user) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.role = role
    }
}
```

---

## 4. JWT Payload

### Définition du Payload

```swift
import JWT
import Vapor

struct UserJWT: JWTPayload {
    // Claims standards
    var sub: SubjectClaim        // Subject (user ID)
    var exp: ExpirationClaim     // Expiration
    var iat: IssuedAtClaim       // Issued at

    // Claims personnalisés
    var role: User.Role
    var username: String

    // Validation du token
    func verify(using signer: JWTSigner) throws {
        // Vérifie que le token n'est pas expiré
        try self.exp.verifyNotExpired()
    }

    // Génération d'un token
    static func generateToken(for user: User, req: Request) throws -> String {
        let payload = UserJWT(
            sub: .init(value: user.id.uuidString),
            exp: .init(value: Date().addingTimeInterval(3600)), // 1 heure
            iat: .init(value: Date()),
            role: user.role,
            username: user.username
        )

        return try req.application.jwt.signers.sign(payload)
    }
}
```

### Claims Standards Disponibles

| Claim | Type | Description |
|-------|------|-------------|
| `sub` | SubjectClaim | Identifiant du sujet (user ID) |
| `exp` | ExpirationClaim | Date d'expiration |
| `iat` | IssuedAtClaim | Date de création |
| `nbf` | NotBeforeClaim | Pas valide avant cette date |
| `iss` | IssuerClaim | Émetteur du token |
| `aud` | AudienceClaim | Audience cible |
| `jti` | IDClaim | Identifiant unique du token |

### Exemple avec Plus de Claims

```swift
struct UserJWT: JWTPayload {
    var sub: SubjectClaim
    var exp: ExpirationClaim
    var iat: IssuedAtClaim
    var nbf: NotBeforeClaim?
    var iss: IssuerClaim
    var aud: AudienceClaim

    var role: User.Role
    var permissions: [String]

    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()

        // Vérifier l'émetteur
        guard iss.value == "my-vapor-app" else {
            throw JWTError.claimVerificationFailure(
                failedClaim: iss,
                reason: "Émetteur invalide"
            )
        }

        // Vérifier l'audience
        guard aud.value.contains("my-api") else {
            throw JWTError.claimVerificationFailure(
                failedClaim: aud,
                reason: "Audience invalide"
            )
        }
    }
}
```

---

## 5. Middleware d'Authentification JWT

### Implémentation

```swift
import Vapor
import JWT

struct JWTAuthMiddleware: AsyncJWTAuthenticator {
    typealias Payload = UserJWT

    func authenticate(
        jwt: UserJWT,
        for request: Request
    ) async throws {
        // Extraire l'ID utilisateur du token
        guard let userID = UUID(uuidString: jwt.sub.value) else {
            throw Abort(.unauthorized, reason: "Token invalide: ID utilisateur manquant")
        }

        // Option 1: Créer un User à partir du payload (stateless)
        let user = User(
            id: userID,
            username: jwt.username,
            role: jwt.role
        )

        // Option 2: Charger depuis la DB (plus sécurisé mais plus lent)
        // guard let user = try await User.find(userID, on: request.db) else {
        //     throw Abort(.unauthorized, reason: "Utilisateur non trouvé")
        // }

        // Authentifier l'utilisateur
        request.auth.login(user)
    }
}
```

### Utilisation dans les Routes

```swift
import Vapor

struct LoginController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Route publique - Login
        routes.post("login", use: login)
        routes.post("register", use: register)

        // Routes protégées par JWT
        let protected = routes.grouped(
            JWTAuthMiddleware(),
            User.guardMiddleware()
        )

        protected.get("profile", use: profile)
        protected.put("profile", use: updateProfile)

        // Routes admin (JWT + rôle admin)
        let admin = routes.grouped(
            JWTAuthMiddleware(),
            User.guardMiddleware(),
            RoleMiddleware(requiredRole: .admin)
        )

        admin.get("admin", "dashboard", use: adminDashboard)
        admin.get("admin", "users", use: listUsers)
    }

    // Handlers...
}
```

---

## 6. Endpoints d'Authentification

### DTOs

```swift
// Requête de login
struct LoginDTO: Content {
    let email: String
    let password: String
}

// Requête d'inscription
struct RegisterDTO: Content, Validatable {
    let username: String
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: .count(3...50))
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}

// Réponse avec token
struct TokenDTO: Content {
    let token: String
    let expiresAt: Date
    let user: UserPublicDTO
}

// User sans données sensibles
struct UserPublicDTO: Content {
    let id: UUID
    let username: String
    let email: String
    let role: User.Role
}
```

### Controller d'Authentification

```swift
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        auth.post("register", use: register)
        auth.post("login", use: login)

        // Refresh token
        auth.grouped(JWTAuthMiddleware(), User.guardMiddleware())
            .post("refresh", use: refresh)
    }

    @Sendable
    func register(req: Request) async throws -> TokenDTO {
        // Validation
        try RegisterDTO.validate(content: req)
        let dto = try req.content.decode(RegisterDTO.self)

        // Vérifier si l'email existe déjà
        if try await User.query(on: req.db)
            .filter(\.$email == dto.email)
            .first() != nil {
            throw Abort(.conflict, reason: "Cet email est déjà utilisé")
        }

        // Créer l'utilisateur
        let user = User(
            username: dto.username,
            email: dto.email,
            passwordHash: try Bcrypt.hash(dto.password)
        )
        try await user.save(on: req.db)

        // Générer le token
        return try generateTokenResponse(for: user, req: req)
    }

    @Sendable
    func login(req: Request) async throws -> TokenDTO {
        let dto = try req.content.decode(LoginDTO.self)

        // Trouver l'utilisateur
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == dto.email)
            .first() else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        // Vérifier le mot de passe
        guard try Bcrypt.verify(dto.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        // Générer le token
        return try generateTokenResponse(for: user, req: req)
    }

    @Sendable
    func refresh(req: Request) async throws -> TokenDTO {
        let user = try req.auth.require(User.self)
        return try generateTokenResponse(for: user, req: req)
    }

    private func generateTokenResponse(for user: User, req: Request) throws -> TokenDTO {
        let expiresAt = Date().addingTimeInterval(3600) // 1 heure

        let payload = UserJWT(
            sub: .init(value: user.id!.uuidString),
            exp: .init(value: expiresAt),
            iat: .init(value: Date()),
            role: user.role,
            username: user.username
        )

        let token = try req.application.jwt.signers.sign(payload)

        return TokenDTO(
            token: token,
            expiresAt: expiresAt,
            user: UserPublicDTO(
                id: user.id!,
                username: user.username,
                email: user.email,
                role: user.role
            )
        )
    }
}
```

---

## 7. Middleware de Rôles

### Implémentation

```swift
import Vapor

struct RoleMiddleware: AsyncMiddleware {
    let requiredRole: User.Role

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // Récupérer l'utilisateur authentifié
        let user = try request.auth.require(User.self)

        // Vérifier le rôle
        guard user.role == requiredRole else {
            throw Abort(.forbidden, reason: "Accès refusé: rôle '\(requiredRole.rawValue)' requis")
        }

        return try await next.respond(to: request)
    }
}
```

### Version avec Hiérarchie de Rôles

```swift
extension User.Role: Comparable {
    private var level: Int {
        switch self {
        case .guest: return 0
        case .user: return 1
        case .admin: return 2
        }
    }

    static func < (lhs: User.Role, rhs: User.Role) -> Bool {
        lhs.level < rhs.level
    }
}

struct MinimumRoleMiddleware: AsyncMiddleware {
    let minimumRole: User.Role

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let user = try request.auth.require(User.self)

        guard user.role >= minimumRole else {
            throw Abort(.forbidden, reason: "Niveau d'accès insuffisant")
        }

        return try await next.respond(to: request)
    }
}

// Utilisation
routes.grouped(MinimumRoleMiddleware(minimumRole: .user))
    .get("user-area", use: userArea)  // user et admin peuvent accéder
```

---

## 8. Refresh Tokens

### Concept

- **Access Token** : Courte durée (15min - 1h), utilisé pour les requêtes API
- **Refresh Token** : Longue durée (7-30 jours), stocké en DB, permet de renouveler l'access token

### Modèle Refresh Token

```swift
import Fluent
import Vapor

final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token")
    var token: String

    @Parent(key: "user_id")
    var user: User

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "is_revoked")
    var isRevoked: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userID: UUID, expiresAt: Date) {
        self.$user.id = userID
        self.token = [UInt8].random(count: 32).base64
        self.expiresAt = expiresAt
        self.isRevoked = false
    }
}
```

### Endpoint de Refresh

```swift
struct RefreshDTO: Content {
    let refreshToken: String
}

@Sendable
func refreshToken(req: Request) async throws -> TokenDTO {
    let dto = try req.content.decode(RefreshDTO.self)

    // Trouver le refresh token
    guard let refreshToken = try await RefreshToken.query(on: req.db)
        .filter(\.$token == dto.refreshToken)
        .with(\.$user)
        .first() else {
        throw Abort(.unauthorized, reason: "Refresh token invalide")
    }

    // Vérifications
    guard !refreshToken.isRevoked else {
        throw Abort(.unauthorized, reason: "Token révoqué")
    }

    guard refreshToken.expiresAt > Date() else {
        throw Abort(.unauthorized, reason: "Token expiré")
    }

    // Révoquer l'ancien token
    refreshToken.isRevoked = true
    try await refreshToken.save(on: req.db)

    // Créer un nouveau refresh token
    let newRefreshToken = RefreshToken(
        userID: refreshToken.$user.id,
        expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30) // 30 jours
    )
    try await newRefreshToken.save(on: req.db)

    // Générer les tokens
    let user = refreshToken.user
    let accessToken = try UserJWT.generateToken(for: user, req: req)

    return TokenDTO(
        accessToken: accessToken,
        refreshToken: newRefreshToken.token,
        expiresAt: Date().addingTimeInterval(3600)
    )
}
```

---

## 9. Sécurité JWT

### Bonnes Pratiques

```swift
// 1. Durée d'expiration courte
let exp = ExpirationClaim(value: Date().addingTimeInterval(900)) // 15 min

// 2. Clé secrète forte (256+ bits)
let secret = Environment.get("JWT_SECRET")!
guard secret.count >= 32 else {
    fatalError("JWT_SECRET doit faire au moins 32 caractères")
}

// 3. Vérification complète dans le payload
func verify(using signer: JWTSigner) throws {
    try exp.verifyNotExpired()

    guard iss.value == "my-app" else {
        throw JWTError.claimVerificationFailure(
            failedClaim: iss,
            reason: "Issuer invalide"
        )
    }
}

// 4. Blacklist pour révocation (optionnel)
struct TokenBlacklist {
    static var revokedTokens: Set<String> = []

    static func revoke(_ token: String) {
        revokedTokens.insert(token)
    }

    static func isRevoked(_ token: String) -> Bool {
        revokedTokens.contains(token)
    }
}
```

### Ce Qu'il Ne Faut PAS Faire

```swift
// ❌ NE PAS stocker de données sensibles
struct BadJWT: JWTPayload {
    var password: String       // JAMAIS!
    var creditCard: String     // JAMAIS!
    var secretKey: String      // JAMAIS!
}

// ❌ NE PAS utiliser un secret faible
app.jwt.signers.use(.hs256(key: "secret"))  // Trop court!

// ❌ NE PAS ignorer l'expiration
func verify(using signer: JWTSigner) throws {
    // Oublier de vérifier exp = token valide indéfiniment!
}

// ❌ NE PAS transmettre le token dans l'URL
// GET /api/data?token=eyJ... (visible dans les logs!)
```

---

## 10. Test de l'Authentification

### Requête de Login
```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password123"}'
```

### Requête Authentifiée
```bash
curl http://localhost:8080/profile \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Test Unitaire

```swift
func testLogin() async throws {
    let app = try await Application.make(.testing)
    try await configure(app)
    defer { app.shutdown() }

    // Créer un utilisateur de test
    let user = User(
        username: "testuser",
        email: "test@example.com",
        passwordHash: try Bcrypt.hash("password123")
    )
    try await user.save(on: app.db)

    // Tester le login
    try await app.test(.POST, "auth/login", beforeRequest: { req in
        try req.content.encode(LoginDTO(
            email: "test@example.com",
            password: "password123"
        ))
    }, afterResponse: { res async in
        XCTAssertEqual(res.status, .ok)

        let tokenResponse = try res.content.decode(TokenDTO.self)
        XCTAssertFalse(tokenResponse.token.isEmpty)
    })
}
```

---

## Questions Fréquentes

### Q: Où stocker le JWT côté client?
**R:**
- **SPA** : `localStorage` ou `sessionStorage` (attention aux XSS)
- **Mobile** : Keychain (iOS) ou EncryptedSharedPreferences (Android)
- **Cookies** : HttpOnly + Secure + SameSite (protection CSRF/XSS)

### Q: Que faire si un token est compromis?
**R:** Implémentez une liste noire de tokens révoqués ou utilisez des refresh tokens avec rotation.

### Q: JWT vs Sessions?
**R:**
- **JWT** : Stateless, scalable, idéal pour APIs/microservices
- **Sessions** : Stateful, plus simple à révoquer, mieux pour apps web classiques

### Q: Pourquoi mon token est rejeté?
**R:** Vérifiez : expiration, signature (même clé?), format du header `Authorization: Bearer <token>`.

---

## Checklist du Chapitre

- [ ] Configurer JWT avec une clé secrète forte
- [ ] Créer un payload JWT avec les claims appropriés
- [ ] Implémenter les endpoints login/register
- [ ] Créer le middleware d'authentification JWT
- [ ] Implémenter un middleware de rôles
- [ ] Comprendre la différence access/refresh tokens
- [ ] Appliquer les bonnes pratiques de sécurité
- [ ] Savoir tester l'authentification
