extends HttpRouter
class_name DeleteAPIKey

func handle_delete(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	if !(await Firebase.memberExists(memberID)):
		response.send(403)
		return
	await Firebase.deleteAPIKey(memberID, request.query["key"])
	response.send(200)
