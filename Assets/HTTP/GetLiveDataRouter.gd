extends HttpRouter
class_name GetLiveData

var lastTime : int = 0
var liveCache : Dictionary = {}

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	var time = Time.get_unix_time_from_system()
	var currentTime = int(floor(time/120))
	if currentTime != lastTime:
		lastTime = currentTime
		liveCache.clear()
	
	if(liveCache.has(request.query["memberid"])):
		response.send(200, liveCache[request.query["memberid"]])
		return
	
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var liveData = {
		"playercount" : 0,
		"lobbycount" : 0,
		"usage" : 0,
		"keys" : 0,
	}
	
	var targetKeys : int = 1
	
	if request.query["key"] == "All" || request.query["key"] == "all":
		var keys = await Firebase.getAllKeys(request.query["memberid"])
		targetKeys = keys.size()
		
		for key in keys:
			MongoDB.getLiveData(request.query["memberid"], key, liveData)
	else:
		MongoDB.getLiveData(request.query["memberid"], request.query["key"], liveData)
	
	var i : int = 0
	while i < 50:
		i += 1
		await Firebase.get_tree().create_timer(0.2).timeout
		if liveData["keys"] == targetKeys:
			break
	
	var jsonString : String = JSON.stringify(liveData)
	liveCache[request.query["memberid"]] = jsonString
	response.send(200, jsonString)
