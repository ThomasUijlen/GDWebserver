extends HttpRouter
class_name GetKeyData

func handle_get(request, response):
	response.send(200, JSON.stringify(await Firebase.getAllKeyData(request.query["memberid"])))
