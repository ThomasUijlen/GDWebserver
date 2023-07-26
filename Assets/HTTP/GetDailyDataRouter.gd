extends HttpRouter
class_name GetDailyData

func handle_get(request, response):
	var liveData = {}
	
	if request.query["key"] == "All":
		var keys = await Firebase.getAllKeys(request.query["memberid"])
		
		for key in keys:
			var newData = await Firebase.getDailyData(request.query["memberid"], key.get_file())
			liveData[key.get_file()] = newData
	else:
		var newData = await Firebase.getDailyData(request.query["memberid"], request.query["key"])
		liveData[request.query["key"].get_file()] = newData
	
	if liveData != null:
		response.send(200, JSON.stringify(liveData))
	else:
		response.send(401)
