extends HttpRouter
class_name GetLiveData

func handle_get(request, response):
	var liveData = {
		"playercount" : 0,
		"lobbycount" : 0,
		"usage" : 0,
		"keys" : 0,
	}
	
	var targetKeys : int = 1
	
	if request.query["key"] == "All" || request.query["key"] == "all":
		var keys = await Firebase.getAllKeys(request.query["memberid"])
		targetKeys = keys.size()
		
		for key in keys:
			Firebase.getLiveData(request.query["memberid"], key.get_file(), liveData)
	else:
		Firebase.getLiveData(request.query["memberid"], request.query["key"], liveData)
	
	var i : int = 0
	while i < 50:
		i += 1
		await Firebase.get_tree().create_timer(0.2).timeout
		if liveData["keys"] == targetKeys:
			break
	
	response.send(200, JSON.stringify(liveData))
