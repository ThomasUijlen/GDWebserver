extends HttpRouter
class_name GetPlanData

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	if !(await Firebase.memberExists(memberID)):
		response.send(403)
		return
	var data : Dictionary = await Firebase.getPlanData(memberID)
	response.send(200, JSON.stringify(data))
