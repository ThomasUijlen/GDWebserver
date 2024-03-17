extends HttpRouter
class_name GetKeyData

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	response.send(200, JSON.stringify(await Firebase.getAllKeyData(request.query["memberid"])))
