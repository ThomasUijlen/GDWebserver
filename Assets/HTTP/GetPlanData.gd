extends HttpRouter
class_name GetPlanData

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	if !request.query.has("memberid"):
		response.send(403)
		return
	
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var data : Dictionary = await Firebase.getPlanData(request.query["memberid"])
	response.send(200, JSON.stringify(data))
