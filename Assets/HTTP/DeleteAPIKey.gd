extends HttpRouter
class_name DeleteAPIKey

func handle_delete(request, response):
	var succes : bool = await Firebase.deleteAPIKey(request.query["memberid"], request.query["key"])
	response.send(200 if succes else 404)
