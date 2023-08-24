extends HttpRouter
class_name DeleteAPIKey

func handle_delete(request, response):
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var succes : bool = await Firebase.deleteAPIKey(request.query["memberid"], request.query["key"])
	if succes: Firebase.markPlayerChanged(request.query["memberid"])
	response.send(200 if succes else 404)
