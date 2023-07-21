extends HttpRouter
class_name GetLiveData

func handle_get(request, response):
	var playerCount = await Firebase.getLiveData(request.query["memberid"], request.query["key"])
	
	if playerCount != null:
		response.send(200, str(playerCount))
	else:
		response.send(401)
