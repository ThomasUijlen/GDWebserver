extends HttpRouter
class_name RenameAPIKey

func handle_patch(request, response):
	var succes : bool = await Firebase.renameAPIKey(request.query["memberid"], request.query["key"], request.query["keyname"])
	response.send(200 if succes else 404)
