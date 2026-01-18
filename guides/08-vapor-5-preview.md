# Chapitre 8 - Vapor 5 : Ce qui arrive (Preview)

> **Statut** : Vapor 5 est en développement. Ce guide est basé sur les annonces officielles et peut évoluer avant la release finale.

## Objectifs d'apprentissage
- Comprendre les changements majeurs de Vapor 5
- Anticiper la migration depuis Vapor 4
- Découvrir les améliorations Sendable/Concurrency
- Connaître le nouvel écosystème Swift Server

---

## 1. Timeline et Support

| Version | Statut | Support |
|---------|--------|---------|
| Vapor 4 | Stable | Maintenu 6+ mois après Vapor 5 |
| Vapor 5 | En développement | 3 ans minimum de support |

**Prérequis Vapor 5** : Swift 6.0+

---

## 2. Changement Majeur : Fin des EventLoopFuture

### Vapor 4 (Actuel)
```swift
// Mélange de syntaxes : futures ET async/await
func getUser(req: Request) -> EventLoopFuture<User> {
    return User.find(id, on: req.db).unwrap(or: Abort(.notFound))
}

// Ou en async (ajouté progressivement)
func getUser(req: Request) async throws -> User {
    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound)
    }
    return user
}
```

### Vapor 5 (À venir)
```swift
// 100% async/await, plus de EventLoopFuture
func getUser(req: Request) async throws -> User {
    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound)
    }
    return user
}
```

**Impact** :
- Code plus lisible et maintenable
- Meilleure gestion des erreurs avec `try/catch`
- Fini les `.map`, `.flatMap`, `.whenComplete` sur les futures
- Performance améliorée grâce à la structured concurrency native

---

## 3. Sendable : La Vraie Solution

### Le Problème Actuel (Vapor 4 / Fluent 4)

Les modèles Fluent nécessitent `@unchecked Sendable` à cause d'une limitation Swift :

```swift
// Vapor 4 - Obligatoire mais "ugly"
final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    // ...
}
```

**Pourquoi ?** Les property wrappers (`@ID`, `@Field`, etc.) ont des setters mutables. Swift ne peut pas vérifier automatiquement que c'est thread-safe, même si Fluent garantit la sécurité en interne.

### La Solution Fluent 5

```swift
// Fluent 5 - Plus besoin de @unchecked Sendable!
final class User: Model, Content {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    // Sendable sera géré automatiquement par le framework
}
```

**Ce qui change** :
- Fluent 5 résoudra le problème à la source
- Plus de warnings de concurrence sur les modèles
- Code plus propre et idiomatique Swift 6

> **Note** : Fluent 5 est un projet séparé. FluentKit 4 restera compatible avec Vapor 5 pendant la transition.

---

## 4. Nouvel Écosystème Swift Server

Vapor 5 adopte les packages officiels Swift Server :

### Avant (Vapor 4)
```swift
// Implémentations custom Vapor
import Vapor  // HTTP server custom
```

### Après (Vapor 5)
```swift
// Packages Swift officiels
import HTTPTypes           // Apple's HTTP Types
import ServiceLifecycle    // Swift Service Lifecycle
import Hummingbird         // Nouveau HTTP server (base)
```

### Packages Intégrés

| Package | Rôle |
|---------|------|
| **Swift Service Lifecycle** | Gestion du cycle de vie (startup, shutdown) |
| **HTTP Types** | Types HTTP standardisés (Apple) |
| **Swift Middleware** | Middleware standardisé cross-frameworks |
| **Swift Metrics/Logging/Tracing** | Observabilité native |
| **FoundationEssentials** | Foundation moderne et cross-platform |

**Avantages** :
- Interopérabilité avec d'autres frameworks (Hummingbird, etc.)
- Maintenance partagée avec la communauté Swift Server
- Performance optimisée par Apple et la communauté

---

## 5. Nouvelles Fonctionnalités

### OpenAPI First-Class
```swift
// Génération automatique de documentation OpenAPI
// ET génération de routes depuis un spec OpenAPI
app.openAPI.document  // Spec générée automatiquement
```

### WebSockets Repensés
```swift
// Vapor 4
socket.onText { ws, text in
    // Callback-based
}

// Vapor 5 (syntaxe aspirationnelle)
for await message in websocket {
    // Async iteration native!
    switch message {
    case .text(let string):
        // ...
    case .binary(let data):
        // ...
    }
}
```

### Streaming Amélioré
```swift
// Multipart streaming pour gros fichiers
// Intégration NIOFileSystem
for await chunk in request.body.stream {
    try await file.write(chunk)
}
```

### gRPC et SSE
```swift
// Support natif gRPC
app.grpc.register(MyService())

// Server-Sent Events simplifié
app.get("events") { req async throws -> AsyncStream<String> in
    // ...
}
```

### Observabilité Native
```swift
// Logging, Metrics, Tracing intégrés
import Logging
import Metrics
import Tracing

// Traces distribuées automatiques
app.trace("user-request") { span in
    span.attributes["user.id"] = userId
    // ...
}
```

---

## 6. Migration Vapor 4 → Vapor 5

### Changements Breaking Attendus

| Domaine | Vapor 4 | Vapor 5 |
|---------|---------|---------|
| Futures | `EventLoopFuture<T>` | Supprimé, 100% async |
| Models | `@unchecked Sendable` requis | Sendable natif (Fluent 5) |
| HTTP Server | Custom Vapor | Basé sur Hummingbird |
| Middleware | Protocol Vapor | Swift Middleware standard |
| Lifecycle | Custom | Swift Service Lifecycle |

### Checklist de Préparation

Dès maintenant sur Vapor 4 :

- [ ] Convertir tous les handlers en `async throws`
- [ ] Remplacer `.map`/`.flatMap` par `await`
- [ ] Utiliser `@Sendable` sur toutes les closures
- [ ] Activer `StrictConcurrency` dans Package.swift
- [ ] Éviter les `EventLoopFuture` dans le nouveau code

```swift
// Package.swift - Activer dès maintenant
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency")
]
```

### Exemple de Conversion

```swift
// ❌ Vapor 4 style (à éviter pour nouveau code)
func getUsers(req: Request) -> EventLoopFuture<[User]> {
    return User.query(on: req.db).all()
}

// ✅ Style compatible Vapor 5
@Sendable
func getUsers(req: Request) async throws -> [User] {
    try await User.query(on: req.db).all()
}
```

---

## 7. Ce Qui Ne Change Pas

Certains concepts restent identiques :

- **Routing** : Même syntaxe `app.get`, `app.post`, etc.
- **Controllers** : `RouteCollection` protocol
- **Fluent Basics** : `@ID`, `@Field`, `@Parent`, `@Children` (mais sans `@unchecked Sendable`)
- **Migrations** : Même approche `AsyncMigration`
- **Content** : Protocol pour JSON encoding/decoding
- **Abort** : Gestion des erreurs HTTP

---

## 8. Quand Migrer ?

### Recommandations

| Situation | Recommandation |
|-----------|----------------|
| Nouveau projet | Attendre Vapor 5 stable ou commencer en Vapor 4 avec style async |
| Projet existant stable | Rester sur Vapor 4, préparer progressivement |
| Projet avec beaucoup de futures | Commencer la migration async dès maintenant |

### Timeline Estimée

1. **Maintenant** : Préparer le code (async, Sendable)
2. **Alpha Vapor 5** : Tester sur un projet non-critique
3. **Beta Vapor 5** : Commencer migration projets secondaires
4. **Release stable** : Migration projets production

---

## Questions Fréquentes

### Q: Dois-je attendre Vapor 5 pour commencer un projet ?
**R:** Non. Commencez avec Vapor 4 en utilisant le style async/await partout. La migration sera minimale.

### Q: Fluent 5 sera-t-il obligatoire avec Vapor 5 ?
**R:** Non, FluentKit 4 restera compatible. Fluent 5 arrivera séparément avec les améliorations Sendable.

### Q: Mes packages Vapor 4 fonctionneront-ils ?
**R:** Pas directement. Les packages devront être mis à jour pour supporter les nouveaux protocols (Middleware, etc.).

### Q: Y aura-t-il un guide de migration officiel ?
**R:** Oui, l'équipe Vapor prévoit une documentation de migration complète.

---

## Ressources

- [The Future of Vapor (Blog officiel)](https://blog.vapor.codes/posts/the-future-of-vapor/)
- [Fluent Models and Sendable](https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- [Vapor Next Steps](https://blog.vapor.codes/posts/vapor-next-steps/)
- [Swift Server Ecosystem](https://www.swift.org/blog/swift-on-the-server-ecosystem/)
- [GitHub Vapor Releases](https://github.com/vapor/vapor/releases)

---

## Checklist de Préparation

- [ ] Comprendre les changements EventLoopFuture → async
- [ ] Savoir pourquoi `@unchecked Sendable` existe (et disparaîtra)
- [ ] Connaître les nouveaux packages Swift Server
- [ ] Écrire du code Vapor 4 "Vapor 5-ready" (async, Sendable)
- [ ] Suivre le blog Vapor pour les annonces
