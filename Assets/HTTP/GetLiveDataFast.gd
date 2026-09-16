extends HttpRouter
class_name GetLiveDataFast

var last_slot : int = 0
var cache : Dictionary = {}

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
	var slot : int = int(floor(Time.get_unix_time_from_system() / 120.0))
	if slot != last_slot:
		last_slot = slot
		cache.clear()
	var cache_key : String = memberID + "|" + key
	if cache.has(cache_key):
		response.send(200, cache[cache_key])
		return
	var live : Dictionary = await Firebase.get_live_snapshot(memberID, key)
	var json_string : String = JSON.stringify(live)
	cache[cache_key] = json_string
	response.send(200, json_string)
