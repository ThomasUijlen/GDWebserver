extends HttpRouter
class_name ConnectRouter

func handle_get(request, response):
	response.send(401)
