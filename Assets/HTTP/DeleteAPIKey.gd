extends HttpRouter
class_name DeleteAPIKey

func handle_delete(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	Firebase.deleteAPIKey(request.query["memberid"], request.query["key"])
	Firebase.markPlayerChanged(request.query["memberid"])
	response.send(200)
