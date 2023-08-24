extends HttpRouter
class_name RenameAPIKey

func handle_patch(request, response):
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var succes : bool = await Firebase.renameAPIKey(request.query["memberid"], request.query["key"], str(request.query["keyname"]))
	response.send(200 if succes else 404)
