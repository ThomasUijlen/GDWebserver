extends HttpRouter
class_name GetKeyData

func handle_get(request, response):
	var data : Dictionary = {}
	
	var keys = await Firebase.getAllKeys(request.query["memberid"])
	
	for key in keys:
		data[key.get_file()] = await Firebase.getKeyData(request.query["memberid"], key.get_file())
	
	response.send(200, JSON.stringify(data))
