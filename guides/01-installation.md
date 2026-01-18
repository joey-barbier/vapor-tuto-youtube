# Chapitre 1 - Installation et Configuration de Vapor

## Objectifs d'apprentissage
- Installer Vapor et ses dépendances
- Comprendre la structure d'un projet Vapor
- Configurer l'application de base
- Lancer et tester l'application

---

## 1. Installation de Vapor

### Prérequis
```bash
# macOS - Installer Xcode Command Line Tools
xcode-select --install

# Installer Homebrew (si pas déjà fait)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Installer Vapor Toolbox
brew install vapor
```

### Création d'un nouveau projet
```bash
# Créer un nouveau projet Vapor
vapor new MonProjet

# Ou avec des options spécifiques
vapor new MonProjet --fluent.db postgres --leaf
```

---

## 2. Structure d'un Projet Vapor

```
MonProjet/
├── Package.swift          # Dépendances et configuration Swift Package Manager
├── Sources/
│   └── App/
│       ├── entrypoint.swift    # Point d'entrée de l'application
│       ├── configure.swift     # Configuration de l'application
│       └── routes.swift        # Définition des routes
├── Resources/
│   └── Views/             # Templates Leaf (si activé)
├── Public/                # Fichiers statiques (CSS, JS, images)
└── Tests/
    └── AppTests/          # Tests unitaires et d'intégration
```

---

## 3. Fichiers Clés

### Package.swift - Gestion des Dépendances

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "hello",
    platforms: [
        .macOS(.v13)  // Version minimum de macOS
    ],
    dependencies: [
        // Framework Vapor principal
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),

        // Moteur de templates Leaf (optionnel)
        .package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        )
    ]
)

// Configuration de la concurrence stricte (recommandé)
var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("StrictConcurrency")
    ]
}
```

#### Bonnes Pratiques - Package.swift
- Toujours spécifier une version minimum de plateforme
- Activer `StrictConcurrency` pour une meilleure sécurité du code
- Grouper les dépendances par catégorie (core, database, views, etc.)
- Utiliser des versions sémantiques (`from:`) plutôt que des branches

---

### entrypoint.swift - Point d'Entrée

```swift
import Vapor
import Logging
import NIOCore
import NIOPosix

@main
enum Entrypoint {
    static func main() async throws {
        // Configuration du logging avant toute autre chose
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        // Création de l'application
        let app = try await Application.make(env)

        // Utilisation de Swift Concurrency avec NIO
        let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        app.logger.debug("Executor takeover \(executorTakeoverSuccess ? "succeeded" : "failed")")

        // Configuration
        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }

        // Démarrage du serveur
        try await app.execute()
        try await app.asyncShutdown()
    }
}
```

#### Bonnes Pratiques - entrypoint.swift
- Utiliser `@main` avec un `enum` (pas de state, pattern moderne)
- Toujours configurer le logging en premier
- Gérer les erreurs proprement avec shutdown gracieux
- Utiliser `async/await` partout (Vapor 4.x moderne)

---

### configure.swift - Configuration

```swift
import Vapor
import Leaf

func configure(_ app: Application) async throws {
    // Configuration du moteur de vues Leaf
    app.views.use(.leaf)

    // Enregistrement des routes
    try routes(app)
}
```

#### Bonnes Pratiques - configure.swift
- Garder ce fichier court et organisé
- Séparer les configurations par domaine (views, database, middleware)
- Utiliser l'injection de dépendances via `app.services`
- Documenter les configurations non évidentes

---

### routes.swift - Définition des Routes

```swift
import Vapor

func routes(_ app: Application) throws {
    // Route simple retournant du texte
    app.get("hello") { req async -> String in
        return "Hello, world!"
    }

    // Route retournant une vue Leaf
    app.get { req async throws -> View in
        return try await req.view.render("index")
    }
}
```

#### Bonnes Pratiques - routes.swift
- Garder les routes simples (déléguer la logique aux Controllers)
- Utiliser des closures `async throws` systématiquement
- Documenter les routes avec des commentaires
- Grouper les routes par domaine fonctionnel

---

## 4. Templates Leaf

### Structure d'un template (Resources/Views/index.leaf)
```html
<!DOCTYPE html>
<html>
<head>
    <title>Mon Application Vapor</title>
</head>
<body>
    <h1>Bienvenue sur Vapor!</h1>

    <!-- Variables dynamiques -->
    <p>Bonjour, #(name)!</p>

    <!-- Conditions -->
    #if(isLoggedIn):
        <p>Vous êtes connecté</p>
    #else:
        <p>Veuillez vous connecter</p>
    #endif

    <!-- Boucles -->
    #for(item in items):
        <li>#(item)</li>
    #endfor
</body>
</html>
```

---

## 5. Tests

### Structure des Tests (XCTest)
```swift
@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        self.app = try await Application.make(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        try await self.app.asyncShutdown()
    }

    func testHelloWorld() async throws {
        try await self.app.test(.GET, "hello") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Hello, world!")
        }
    }
}
```

### Alternative : Swift Testing (Swift 6+)
```swift
@testable import App
import Testing
import XCTVapor

@Suite("App Tests")
struct AppTests {
    @Test("Hello world endpoint returns correct response")
    func helloWorld() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        try await app.test(.GET, "hello") { res async in
            #expect(res.status == .ok)
            #expect(res.body.string == "Hello, world!")
        }
    }
}
```

> **Note** : Swift Testing (`@Test`, `#expect`) est le nouveau framework de tests de Swift 6. XCTest reste supporté et plus répandu dans les projets existants.

#### Bonnes Pratiques - Tests
- Utiliser l'environnement `.testing` (pas de vraie DB, port différent)
- Toujours faire un `asyncShutdown()` dans `tearDown`
- Tester les codes de statut ET le contenu des réponses
- Organiser les tests par fonctionnalité

---

## 6. Commandes Utiles

```bash
# Lancer le serveur en mode développement
swift run App serve

# Lancer avec hot-reload (si vapor toolbox installé)
vapor run serve

# Compiler en mode release
swift build -c release

# Lancer les tests
swift test

# Mettre à jour les dépendances
swift package update

# Nettoyer le build
swift package clean
```

---

## 7. Variables d'Environnement

### Configuration par environnement
```swift
// Détection automatique
let env = try Environment.detect()

// Lecture d'une variable
let port = Environment.get("PORT") ?? "8080"
let logLevel = Environment.get("LOG_LEVEL") ?? "info"
```

### Fichier .env (développement)
```env
LOG_LEVEL=debug
PORT=8080
```

#### Bonnes Pratiques - Environnement
- Ne jamais commiter le fichier `.env` (ajouter à `.gitignore`)
- Utiliser des valeurs par défaut sensées
- Documenter toutes les variables requises dans un `.env.example`

---

## Questions Fréquentes pour les Débutants

### Q: Quelle est la différence entre `async` et `async throws`?
**R:** `async throws` permet à la fonction de lever des erreurs. Utilisez toujours `async throws` pour les routes car elles peuvent échouer (DB, réseau, etc.).

### Q: Pourquoi utiliser un `enum` pour `@main` au lieu d'une `struct`?
**R:** Un `enum` sans cases ne peut pas être instancié, ce qui est parfait pour un point d'entrée qui ne devrait jamais avoir d'état.

### Q: Comment débugger une erreur de démarrage?
**R:** Vérifiez les logs avec `LOG_LEVEL=debug swift run`. Les erreurs communes sont : port déjà utilisé, dépendances manquantes, fichiers de configuration absents.

### Q: Faut-il utiliser Leaf ou une autre solution frontend?
**R:** Leaf est idéal pour du server-side rendering simple. Pour une SPA moderne, utilisez Vapor uniquement comme API et un framework frontend séparé (React, Vue, etc.).

---

## Checklist du Chapitre

- [ ] Vapor Toolbox installé
- [ ] Projet créé avec `vapor new`
- [ ] Comprendre Package.swift et les dépendances
- [ ] Comprendre entrypoint.swift et le cycle de vie
- [ ] Savoir configurer dans configure.swift
- [ ] Savoir créer des routes basiques
- [ ] Savoir lancer et tester l'application
- [ ] Comprendre les templates Leaf (si utilisé)
