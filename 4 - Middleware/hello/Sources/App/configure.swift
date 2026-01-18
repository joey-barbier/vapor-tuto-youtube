import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    // register routes
    try routes(app)
    
    //app.middleware.use(LoggingMiddleware(), at: .end)
    app.middleware.use(LoggingMiddleware())
    
    
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all, // Permet toutes les origines
        allowedMethods: [.GET, .POST, .DELETE, .OPTIONS, .PUT], // Méthodes HTTP autorisées
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    let corsMiddleware = CORSMiddleware(configuration: corsConfig)

    app.middleware.use(corsMiddleware)
    
    
    // Middleware qui attrape toutes les erreurs et les formate en réponse HTTP
    // app.middleware.use(ErrorMiddleware.default(environment: app.environment))
     app.middleware.use(CustomErrorMiddleware())
    
    
    // Utilisation pour servir les fichiers depuis un dossier "Public"
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
}
