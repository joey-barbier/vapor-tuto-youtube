# Chapitre 7 - Mise en Production

## Objectifs d'apprentissage
- Créer une image Docker optimisée
- Configurer un pipeline CI/CD
- Déployer avec Docker Compose
- Appliquer les bonnes pratiques de production
- Configurer la sécurité et le monitoring

---

## 1. Dockerfile Multi-Stage

### Structure Recommandée

```dockerfile
# ================================
# Build image
# ================================
FROM swift:6.0-jammy AS build

# Installer jemalloc pour une meilleure gestion mémoire
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copier et résoudre les dépendances d'abord (cache Docker)
COPY ./Package.* ./
RUN swift package resolve

# Copier le code source
COPY . .

# Build en mode release avec optimisations
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc

# Préparer le dossier de staging
WORKDIR /staging

# Copier l'exécutable
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./

# Copier les ressources
RUN cp -r /build/Public ./Public 2>/dev/null || true
RUN cp -r /build/Resources ./Resources 2>/dev/null || true

# ================================
# Run image
# ================================
FROM ubuntu:jammy

# Installer les dépendances runtime minimales
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

# Créer un utilisateur non-root pour la sécurité
RUN useradd --user-group --create-home --system \
    --skel /dev/null --home-dir /app vapor

WORKDIR /app

# Copier depuis le build stage
COPY --from=build --chown=vapor:vapor /staging /app

# Configurer le backtrace Swift pour le debugging
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no

# Exécuter en tant qu'utilisateur non-root
USER vapor:vapor

# Exposer le port
EXPOSE 8080

# Point d'entrée
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
```

### Explications des Optimisations

| Option | Description |
|--------|-------------|
| `--static-swift-stdlib` | Inclut la stdlib Swift dans le binaire (pas besoin de Swift sur l'image finale) |
| `-Xlinker -ljemalloc` | Utilise jemalloc pour une meilleure gestion mémoire |
| `-c release` | Compilation optimisée pour la production |
| Multi-stage | Image finale légère (~80MB vs ~2GB) |
| User non-root | Sécurité renforcée |

---

## 2. Docker Compose

### Configuration Production

```yaml
version: '3.8'

services:
  app:
    image: ${CI_REGISTRY_IMAGE:-my-vapor-app}:${TAG:-latest}
    container_name: vapor-app
    restart: unless-stopped
    environment:
      # Configuration de l'application
      LOG_LEVEL: ${LOG_LEVEL:-info}
      DATABASE_HOST: db
      DATABASE_PORT: 5432
      DATABASE_USERNAME: ${DB_USER:-vapor}
      DATABASE_PASSWORD: ${DB_PASSWORD}
      DATABASE_NAME: ${DB_NAME:-vapor_db}
      JWT_SECRET: ${JWT_SECRET}
    ports:
      - '8080:8080'
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    networks:
      - app-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

  db:
    image: postgres:16-alpine
    container_name: vapor-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER:-vapor}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME:-vapor_db}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-vapor}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  postgres-data:
```

### Fichier .env (NE PAS COMMITER!)

```env
# Database
DB_USER=vapor_user
DB_PASSWORD=super_secret_password_change_me
DB_NAME=vapor_production

# Application
LOG_LEVEL=info
JWT_SECRET=your-256-bit-secret-key-minimum-32-characters

# Docker Registry
CI_REGISTRY_IMAGE=registry.example.com/my-app
TAG=v1.0.0
```

---

## 3. Pipeline CI/CD (GitLab)

### .gitlab-ci.yml Complet

```yaml
stages:
  - test
  - build
  - push
  - deploy

variables:
  DOCKER_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG
  ARTIFACT_DIR: docker-image
  ARTIFACT_NAME: vapor-app.tar

# ================================
# Stage: Test
# ================================
test:
  stage: test
  image: swift:6.0-jammy
  script:
    - swift test --parallel
  only:
    - merge_requests
    - main
  cache:
    key: swift-packages
    paths:
      - .build/

# ================================
# Stage: Build
# ================================
build:
  stage: build
  image: quay.io/buildah/stable:v1.21.0
  before_script:
    - buildah version
  script:
    # Build l'image Docker
    - buildah bud --format docker -t "$DOCKER_IMAGE" .

    # Sauvegarder comme artifact
    - mkdir -p "$ARTIFACT_DIR"
    - buildah push "$DOCKER_IMAGE" docker-archive:"$ARTIFACT_DIR/$ARTIFACT_NAME"
  artifacts:
    expire_in: 6h
    paths:
      - "$ARTIFACT_DIR/"
  only:
    - main
    - tags

# ================================
# Stage: Push
# ================================
push:
  stage: push
  image: quay.io/buildah/stable:v1.21.0
  script:
    # Charger l'image depuis l'artifact
    - buildah pull docker-archive:$ARTIFACT_DIR/$ARTIFACT_NAME

    # Login au registry
    - echo "$CI_REGISTRY_PASSWORD" | buildah login -u "$CI_REGISTRY_USER" --password-stdin $CI_REGISTRY

    # Tag avec le SHA du commit
    - buildah tag $DOCKER_IMAGE $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

    # Tag avec 'latest' si c'est main
    - |
      if [ "$CI_COMMIT_BRANCH" = "main" ]; then
        buildah tag $DOCKER_IMAGE $CI_REGISTRY_IMAGE:latest
      fi

    # Tag avec le tag Git si présent
    - |
      if [ -n "$CI_COMMIT_TAG" ]; then
        buildah tag $DOCKER_IMAGE $CI_REGISTRY_IMAGE:$CI_COMMIT_TAG
      fi

    # Push toutes les versions
    - buildah push --all $CI_REGISTRY_IMAGE
  dependencies:
    - build
  only:
    - main
    - tags

# ================================
# Stage: Deploy
# ================================
deploy:
  stage: deploy
  tags:
    - prod  # Runner sur le serveur de production
  before_script:
    - cd /var/www/my-vapor-app
  script:
    # Login au registry
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin $CI_REGISTRY

    # Pull la nouvelle image
    - docker-compose pull

    # Arrêter l'ancien container
    - docker-compose down

    # Démarrer le nouveau
    - docker-compose up -d

    # Nettoyer les anciennes images
    - docker image prune -f
  environment:
    name: production
    url: https://api.example.com
  when: manual  # Déploiement manuel pour plus de contrôle
  only:
    - main
    - tags
```

---

## 4. Configuration de l'Application pour la Production

### configure.swift

```swift
import Vapor
import Fluent
import FluentPostgresDriver

func configure(_ app: Application) async throws {
    // Configuration selon l'environnement
    switch app.environment {
    case .production:
        configureProduction(app)
    case .development:
        configureDevelopment(app)
    default:
        break
    }

    // Configuration commune
    try configureDatabase(app)
    try configureMiddleware(app)
    try routes(app)

    // Migrations
    if app.environment != .testing {
        try await app.autoMigrate()
    }
}

private func configureProduction(_ app: Application) {
    // Log level depuis l'environnement
    app.logger.logLevel = Logger.Level(
        rawValue: Environment.get("LOG_LEVEL") ?? "info"
    ) ?? .info

    // Désactiver les erreurs détaillées
    app.http.server.configuration.reportMetrics = false
}

private func configureDevelopment(_ app: Application) {
    app.logger.logLevel = .debug
}

private func configureDatabase(_ app: Application) throws {
    guard let hostname = Environment.get("DATABASE_HOST"),
          let username = Environment.get("DATABASE_USERNAME"),
          let password = Environment.get("DATABASE_PASSWORD"),
          let database = Environment.get("DATABASE_NAME") else {
        throw Abort(.internalServerError, reason: "Missing database configuration")
    }

    let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432

    app.databases.use(
        DatabaseConfigurationFactory.postgres(
            configuration: .init(
                hostname: hostname,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: app.environment == .production
                    ? .prefer(try .init(configuration: .clientDefault))
                    : .disable
            )
        ),
        as: .psql
    )
}

private func configureMiddleware(_ app: Application) throws {
    // CORS restrictif en production
    let allowedOrigin: CORSMiddleware.AllowOriginSetting = app.environment == .production
        ? .custom(Environment.get("ALLOWED_ORIGIN") ?? "https://example.com")
        : .all

    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: allowedOrigin,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig))

    // Error middleware
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    // Fichiers statiques
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
}
```

---

## 5. Endpoint de Health Check

```swift
import Vapor

struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: healthCheck)
        routes.get("health", "ready", use: readinessCheck)
        routes.get("health", "live", use: livenessCheck)
    }

    // Check basique
    @Sendable
    func healthCheck(req: Request) async throws -> HTTPStatus {
        return .ok
    }

    // Check de disponibilité (DB, services externes)
    @Sendable
    func readinessCheck(req: Request) async throws -> HealthResponse {
        var checks: [String: Bool] = [:]

        // Check base de données
        do {
            _ = try await req.db.query("SELECT 1").first()
            checks["database"] = true
        } catch {
            checks["database"] = false
        }

        // Ajouter d'autres checks si nécessaire (Redis, S3, etc.)

        let allHealthy = checks.values.allSatisfy { $0 }
        let response = HealthResponse(
            status: allHealthy ? "healthy" : "unhealthy",
            checks: checks
        )

        // Retourner 503 si un check échoue
        if !allHealthy {
            throw Abort(.serviceUnavailable, reason: "Service unhealthy")
        }

        return response
    }

    // Check de vie (le process tourne)
    @Sendable
    func livenessCheck(req: Request) async throws -> HTTPStatus {
        return .ok
    }
}

struct HealthResponse: Content {
    let status: String
    let checks: [String: Bool]
}
```

---

## 6. Logging en Production

### Configuration

```swift
import Vapor
import Logging

func configure(_ app: Application) async throws {
    // Format de log structuré
    app.logger.logLevel = .info

    // Log de démarrage
    app.logger.info("Application starting", metadata: [
        "environment": .string(app.environment.name),
        "version": .string(Environment.get("APP_VERSION") ?? "unknown")
    ])
}
```

### Bonnes Pratiques de Logging

```swift
// ✅ Bon: Logs structurés avec contexte
req.logger.info("User logged in", metadata: [
    "userId": .string(user.id?.uuidString ?? "unknown"),
    "ip": .string(req.remoteAddress?.ipAddress ?? "unknown")
])

// ✅ Bon: Niveaux appropriés
req.logger.trace("Entering function")      // Très détaillé
req.logger.debug("Variable value: \(x)")   // Debug
req.logger.info("User created")            // Info importante
req.logger.warning("Rate limit approaching") // Attention
req.logger.error("Database connection failed") // Erreur
req.logger.critical("Application crash")   // Critique

// ❌ Mauvais: Données sensibles dans les logs
req.logger.info("User \(password) logged in") // JAMAIS!
```

---

## 7. Variables d'Environnement

### Liste des Variables Essentielles

```env
# Application
LOG_LEVEL=info
APP_ENV=production
APP_VERSION=1.0.0

# Base de données
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USERNAME=vapor
DATABASE_PASSWORD=secure_password
DATABASE_NAME=vapor_production

# Sécurité
JWT_SECRET=minimum-32-characters-secret-key
ALLOWED_ORIGIN=https://myapp.com

# Optionnel
REDIS_URL=redis://localhost:6379
SMTP_HOST=smtp.example.com
S3_BUCKET=my-bucket
```

### Validation au Démarrage

```swift
func configure(_ app: Application) async throws {
    // Valider les variables requises
    let requiredVars = [
        "DATABASE_HOST",
        "DATABASE_USERNAME",
        "DATABASE_PASSWORD",
        "DATABASE_NAME",
        "JWT_SECRET"
    ]

    for varName in requiredVars {
        guard Environment.get(varName) != nil else {
            app.logger.critical("Missing required environment variable: \(varName)")
            throw Abort(.internalServerError, reason: "Missing configuration: \(varName)")
        }
    }

    // Valider la longueur du JWT secret
    guard let jwtSecret = Environment.get("JWT_SECRET"),
          jwtSecret.count >= 32 else {
        throw Abort(.internalServerError, reason: "JWT_SECRET must be at least 32 characters")
    }
}
```

---

## 8. Sécurité en Production

### Checklist de Sécurité

```swift
// 1. Headers de sécurité
struct SecurityHeadersMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)

        response.headers.add(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.add(name: "X-Frame-Options", value: "DENY")
        response.headers.add(name: "X-XSS-Protection", value: "1; mode=block")
        response.headers.add(name: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains")

        return response
    }
}

// 2. Rate limiting (voir chapitre Middleware)

// 3. Validation des entrées (voir chapitre Controllers)

// 4. HTTPS uniquement (configurer le reverse proxy)
```

### Configuration Nginx (Reverse Proxy)

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    # Configuration SSL sécurisée
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Redirection HTTP → HTTPS
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}
```

---

## 9. Monitoring et Métriques

### Endpoint de Métriques

```swift
struct MetricsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("metrics", use: getMetrics)
    }

    @Sendable
    func getMetrics(req: Request) async throws -> MetricsResponse {
        let processInfo = ProcessInfo.processInfo

        return MetricsResponse(
            uptime: processInfo.systemUptime,
            memoryUsage: getMemoryUsage(),
            activeConnections: await getActiveConnections(req: req),
            requestsPerMinute: await getRequestRate()
        )
    }

    private func getMemoryUsage() -> UInt64 {
        // Note: Cette implémentation est spécifique à macOS/iOS
        // Pour Linux (Docker), utilisez /proc/self/status ou une lib comme swift-metrics
        #if os(macOS) || os(iOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
        #else
        // Linux: lire /proc/self/status ou utiliser swift-metrics
        return 0
        #endif
    }
}

struct MetricsResponse: Content {
    let uptime: TimeInterval
    let memoryUsage: UInt64
    let activeConnections: Int
    let requestsPerMinute: Double
}
```

---

## 10. Commandes de Déploiement

### Script de Déploiement Manuel

```bash
#!/bin/bash
set -e

# Variables
REGISTRY="registry.example.com"
IMAGE_NAME="my-vapor-app"
TAG="${1:-latest}"
SERVER="user@production-server.com"
DEPLOY_PATH="/var/www/my-vapor-app"

echo "🔨 Building image..."
docker build -t "$REGISTRY/$IMAGE_NAME:$TAG" .

echo "📤 Pushing to registry..."
docker push "$REGISTRY/$IMAGE_NAME:$TAG"

echo "🚀 Deploying to production..."
ssh $SERVER << EOF
    cd $DEPLOY_PATH
    export TAG=$TAG
    docker-compose pull
    docker-compose down
    docker-compose up -d
    docker image prune -f
EOF

echo "✅ Deployment complete!"
```

### Rollback

```bash
#!/bin/bash
# rollback.sh

PREVIOUS_TAG="${1:-previous}"
SERVER="user@production-server.com"
DEPLOY_PATH="/var/www/my-vapor-app"

ssh $SERVER << EOF
    cd $DEPLOY_PATH
    export TAG=$PREVIOUS_TAG
    docker-compose pull
    docker-compose down
    docker-compose up -d
EOF

echo "⏪ Rolled back to $PREVIOUS_TAG"
```

---

## Questions Fréquentes

### Q: Comment debugger en production?
**R:** Utilisez les logs structurés, un endpoint `/health/ready` détaillé, et des outils comme Sentry pour les erreurs. N'activez jamais le mode debug en production.

### Q: Quelle est la différence entre `autoMigrate()` et `vapor migrate`?
**R:**
- `autoMigrate()` : Exécute automatiquement au démarrage (dev)
- `vapor run migrate` : Commande manuelle (production)

### Q: Comment gérer les secrets?
**R:** Utilisez des variables d'environnement, jamais de fichiers commités. En production, utilisez un gestionnaire de secrets (Vault, AWS Secrets Manager, etc.).

### Q: Quelle taille de serveur pour Vapor?
**R:** Un VPS avec 1 vCPU et 1GB RAM peut gérer des centaines de requêtes/seconde. Commencez petit et scalez selon les besoins.

---

## Checklist de Mise en Production

- [ ] Dockerfile multi-stage optimisé
- [ ] Docker Compose avec healthchecks
- [ ] Pipeline CI/CD configuré
- [ ] Variables d'environnement sécurisées
- [ ] HTTPS avec certificat valide
- [ ] Headers de sécurité configurés
- [ ] Endpoint /health fonctionnel
- [ ] Logs configurés (niveau info minimum)
- [ ] Backup de base de données automatisé
- [ ] Monitoring/alerting en place
- [ ] Documentation de déploiement
- [ ] Procédure de rollback testée
