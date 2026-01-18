import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: HelloWorldController())
    
    try App.Bonus.Controllers.register(app: app) // on register tout en une ligne 🧑🏻‍🎓
}
