extends HttpRouter
class_name ConnectRouter

func handle_get(request, response):
	var key = KeyLibrary.getKey(request.body)
	if key == null:
		response.send(401)
	else:
		response.send(200, var_to_str(IPLibrary.gameServers))
