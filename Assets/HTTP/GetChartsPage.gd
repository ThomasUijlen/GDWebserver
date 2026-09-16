extends HttpRouter
class_name GetChartsPage

var last_day : int = 0
var cache : Dictionary = {}

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	var day : int = int(floor(Time.get_unix_time_from_system() / 86400.0))
	if day != last_day:
		last_day = day
		cache.clear()
	if cache.has(memberID):
		response.send(200, cache[memberID])
		return
	var page : Dictionary = await Firebase.get_charts_page(memberID)
	var json_string : String = JSON.stringify(page)
	cache[memberID] = json_string
	response.send(200, json_string)
