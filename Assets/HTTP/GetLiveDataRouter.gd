extends HttpRouter
class_name GetLiveData

func handle_get(request, response):
	var liveData = null
	
	if request.query["key"] == "All" || request.query["key"] == "all":
		var keys = await Firebase.getAllKeys(request.query["memberid"])
		liveData = {
			"playercount" : 0,
			"lobbycount" : 0,
			"usage" : 0,
		}
		
		for key in keys:
			var newData = await Firebase.getLiveData(request.query["memberid"], key.get_file())
			liveData["playercount"] += newData["playercount"]
			liveData["lobbycount"] += newData["lobbycount"]
			liveData["usage"] += newData["usage"]
	else:
		liveData = await Firebase.getLiveData(request.query["memberid"], request.query["key"])
	
	if liveData != null:
		
		
		response.send(200, JSON.stringify(liveData))
	else:
		response.send(401)
