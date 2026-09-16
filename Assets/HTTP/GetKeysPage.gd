extends HttpRouter
class_name GetKeysPage

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	response.send(200, JSON.stringify(await Firebase.get_keys_page(memberID)))
