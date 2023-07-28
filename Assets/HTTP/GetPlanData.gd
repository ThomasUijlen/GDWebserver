extends HttpRouter
class_name GetPlanData

func handle_get(request, response):
	var data : Dictionary = await Firebase.getPlanData(request.query["memberid"])
	response.send(200, JSON.stringify(data))
