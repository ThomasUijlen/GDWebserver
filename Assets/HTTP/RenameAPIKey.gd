extends HttpRouter
class_name RenameAPIKey

func handle_patch(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	if !(await Firebase.memberExists(memberID)):
		response.send(403)
		return
	var succes : bool = await Firebase.updateAPIKey(memberID, request.query["key"], str(request.query["keyname"]), "")
	response.send(200 if succes else 404)
