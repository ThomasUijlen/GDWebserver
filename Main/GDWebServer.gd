extends Node

var httpServer : HttpServer

func _ready():
	httpServer = HttpServer.new()
	httpServer.register_router("/getlivedata", GetLiveData.new())
	httpServer.register_router("/getdailydata", GetDailyData.new())
	add_child(httpServer)
	httpServer.start()
