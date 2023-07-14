extends Node

var httpServer : HttpServer

func _ready():
	httpServer = HttpServer.new()
	httpServer.register_router("/connect", ConnectRouter.new())
	add_child(httpServer)
	httpServer.start()
