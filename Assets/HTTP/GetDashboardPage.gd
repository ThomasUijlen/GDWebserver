extends HttpRouter
class_name GetDashboardPage

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	var key : String = "All"
	if request.query.has("key"):
		key = str(request.query["key"])
	var bag : Dictionary = { "plan": {}, "live": { "playercount": 0, "lobbycount": 0, "usage": 0, "keys": 0 }, "left": 2 }
	_fill_plan(memberID, bag)
	_fill_live(memberID, key, bag)
	var started : float = Time.get_unix_time_from_system()
	while int(bag.left) > 0:
		await Firebase.get_tree().process_frame
		if Time.get_unix_time_from_system() - started > 25.0:
			break
	response.send(200, JSON.stringify({ "plan": bag.plan, "live": bag.live }))

func _fill_plan(member_id : String, bag : Dictionary) -> void:
	bag.plan = await Firebase.getPlanData(member_id)
	bag.left -= 1

func _fill_live(member_id : String, key : String, bag : Dictionary) -> void:
	bag.live = await Firebase.get_live_snapshot(member_id, key)
	bag.left -= 1
