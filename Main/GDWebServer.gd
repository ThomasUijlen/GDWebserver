extends Node

var httpServer : HttpServer

func _ready():
	httpServer = HttpServer.new()
	httpServer.register_router("/getlivedata", GetLiveData.new())
	httpServer.register_router("/getdailydata", GetDailyData.new())
	httpServer.register_router("/getkeydata", GetKeyData.new())
	httpServer.register_router("/getplandata", GetPlanData.new())
	httpServer.register_router("/createapikey", CreateAPIKey.new())
	httpServer.register_router("/deleteapikey", DeleteAPIKey.new())
	httpServer.register_router("/renameapikey", RenameAPIKey.new())
	
#	httpServer.register_router("/getalldata", GetAllData.new())
	
	add_child(httpServer)
	httpServer.start()
