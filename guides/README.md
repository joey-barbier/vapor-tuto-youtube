# Guides Vapor - Formation Complète

Ce dossier contient les guides de bonnes pratiques pour apprendre Vapor de A à Z.

## Chapitres

| # | Chapitre | Description |
|---|----------|-------------|
| 1 | [Installation](./01-installation.md) | Configuration initiale, structure de projet, Package.swift |
| 2 | [Controllers & Routes](./02-controllers-routes.md) | RouteCollection, groupement, paramètres, HTTP methods |
| 3 | [Base de Données](./03-database-fluent.md) | Fluent ORM, modèles, migrations, CRUD, DTOs |
| 4 | [Middleware](./04-middleware.md) | CORS, logging, erreurs, authentification, fichiers statiques |
| 5 | [Authentification JWT](./05-authentication-jwt.md) | JWT, login/register, rôles, refresh tokens |
| 6 | [API Avancée](./06-api-advanced.md) | Relations, pagination, filtres, tri, eager loading, seeders |
| 7 | [Production](./07-production-deployment.md) | Docker, CI/CD, sécurité, monitoring, déploiement |
| 8 | [Vapor 5 Preview](./08-vapor-5-preview.md) | Ce qui arrive : async natif, Sendable, nouvel écosystème |

## Utilisation pour l'IA Professeur

Ces guides sont conçus pour être utilisés comme base de connaissances par une IA pédagogique. Chaque guide contient :

- **Objectifs d'apprentissage** clairs
- **Exemples de code** complets et fonctionnels
- **Bonnes pratiques** et patterns recommandés
- **Questions fréquentes** avec réponses
- **Checklist** de validation des acquis

## Structure de chaque guide

```
# Titre du Chapitre

## Objectifs d'apprentissage
- Point 1
- Point 2

## Sections principales
### Sous-section
Code + explications

#### Bonnes Pratiques
- Recommandation 1
- Recommandation 2

## Questions Fréquentes
### Q: Question courante?
**R:** Réponse détaillée

## Checklist du Chapitre
- [ ] Compétence 1
- [ ] Compétence 2
```

## Prérequis

- Swift 5.10+ (Swift 6.0 recommandé pour la concurrence stricte)
- macOS 13+
- Xcode ou VS Code avec extension Swift
- Docker (pour le chapitre Production)

## Ordre recommandé

1. Commencer par l'**Installation** pour comprendre la structure
2. Maîtriser les **Controllers & Routes** pour créer des endpoints
3. Ajouter une **Base de données** avec Fluent
4. Implémenter les **Middlewares** pour la logique transversale
5. Sécuriser avec l'**Authentification JWT**
6. Enrichir avec les fonctionnalités **API Avancée**
7. Finalement, **Déployer en production**

## Conventions de code

```swift
// Annotations @Sendable pour Swift 6
@Sendable
func handler(req: Request) async throws -> Response

// Models avec @unchecked Sendable
final class User: Model, @unchecked Sendable

// DTOs pour les entrées/sorties
struct CreateUserDTO: Content, Validatable

// Namespaces avec enum
enum App {
    enum Controllers {}
}
```

## Ressources complémentaires

- [Documentation officielle Vapor](https://docs.vapor.codes)
- [API Reference](https://api.vapor.codes)
- [Discord Vapor](https://discord.gg/vapor)
- [GitHub Vapor](https://github.com/vapor/vapor)
