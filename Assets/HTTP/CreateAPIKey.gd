extends HttpRouter
class_name CreateAPIKey

func handle_post(request, response):
	var data : Dictionary = await Firebase.getPlanData(request.query["memberid"])
	var keys : Array = await Firebase.getAllKeys(request.query["memberid"])
	if keys.size() < data["KeyCap"]:
		await Firebase.createAPIKey(request.query["memberid"], request.query["keyname"])
		response.send(200)
	else:
		response.send(403)
