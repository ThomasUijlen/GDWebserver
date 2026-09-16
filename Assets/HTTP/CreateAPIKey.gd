extends HttpRouter
class_name CreateAPIKey

func handle_post(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	if !(await Firebase.memberExists(memberID)):
		response.send(403)
		return
	var data : Dictionary = await Firebase.getPlanData(memberID)
	var keys : Array = await Firebase.getAllKeys(memberID)
	var keyModifier : int = 0
	for key in keys:
		if key.get_file() == "Default":
			keyModifier = 1
	if keys.size() < data["KeyCap"]+keyModifier:
		if await Firebase.createAPIKey(memberID, str(request.query["keyname"])):
			response.send(200)
		else:
			response.send(500)
	else:
		response.send(403)
