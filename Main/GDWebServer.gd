extends Node

var httpServer : HttpServer

func _ready():
	httpServer = HttpServer.new()
	httpServer.register_router("/getlivedata", GetLiveData.new())
	httpServer.register_router("/getdailydata", GetDailyData.new())
	httpServer.register_router("/getkeydata", GetKeyData.new())
	httpServer.register_router("/getplandata", GetPlanData.new())
	add_child(httpServer)
	httpServer.start()
