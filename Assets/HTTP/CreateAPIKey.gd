extends HttpRouter
class_name CreateAPIKey

func handle_post(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var data : Dictionary = await Firebase.getPlanData(request.query["memberid"])
	var keys : Array = await Firebase.getAllKeys(request.query["memberid"])
	var keyModifier : int = 0
	for key in keys:
		if key.get_file() == "Default":
			keyModifier = 1
	
	if keys.size() < data["KeyCap"]+keyModifier:
		await Firebase.createAPIKey(request.query["memberid"], str(request.query["keyname"]))
		Firebase.markPlayerChanged(request.query["memberid"])
		response.send(200)
	else:
		response.send(403)
