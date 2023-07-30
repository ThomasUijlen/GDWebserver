extends HttpRouter
class_name GetDailyData

func handle_get(request, response):
	var liveData = {}
	
	if request.query["key"] == "All" || request.query["key"] == "all":
		var keys = await Firebase.getAllKeys(request.query["memberid"])
		
		for key in keys:
			var keyData : Dictionary = {}
			liveData[key.get_file()] = keyData
			keyData["MonthlyData"] = await Firebase.getDailyData(request.query["memberid"], key.get_file())
			keyData["Name"] = (await Firebase.getKeyData(request.query["memberid"], key.get_file()))["Name"]
	else:
		var keyData : Dictionary = {}
		liveData[request.query["key"].get_file()] = keyData
		keyData["MonthlyData"] = await Firebase.getDailyData(request.query["memberid"], request.query["key"])
		keyData["Name"] = (await Firebase.getKeyData(request.query["memberid"], request.query["key"]))["Name"]
	
	if liveData != null:
		response.send(200, JSON.stringify(liveData))
	else:
		response.send(401)
