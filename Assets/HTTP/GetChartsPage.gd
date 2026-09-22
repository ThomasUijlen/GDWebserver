extends HttpRouter
class_name GetChartsPage

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	Firebase._roll_charts_cache_day()
	var plan : Dictionary = await Firebase.getPlanData(memberID)
	var plan_name : String = str(plan.get("Name", "free"))
	if Firebase.charts_cache.has(memberID) and str(Firebase.charts_cache_plan.get(memberID, "")) == plan_name:
		response.send(200, Firebase.charts_cache[memberID])
		return
	var page : Dictionary = await Firebase.get_charts_page(memberID)
	var json_string : String = JSON.stringify(page)
	Firebase.charts_cache[memberID] = json_string
	Firebase.charts_cache_plan[memberID] = str(page.get("plan", {}).get("Name", plan_name))
	response.send(200, json_string)
