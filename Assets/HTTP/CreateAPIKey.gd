extends HttpRouter
class_name CreateAPIKey

func handle_post(request, response):
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var data : Dictionary = await Firebase.getPlanData(request.query["memberid"])
	var keys : Array = await Firebase.getAllKeys(request.query["memberid"])
	if keys.size() < data["KeyCap"]:
		await Firebase.createAPIKey(request.query["memberid"], str(request.query["keyname"]))
		Firebase.markPlayerChanged(request.query["memberid"])
		response.send(200)
	else:
		response.send(403)
