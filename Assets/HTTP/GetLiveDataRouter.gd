extends HttpRouter
class_name GetLiveData

var lastTime : int = 0
var liveCache : Dictionary = {}

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	var time = Time.get_unix_time_from_system()
	var currentTime = int(floor(time/120))
	if currentTime != lastTime:
		lastTime = currentTime
		liveCache.clear()
	if(liveCache.has(memberID)):
		response.send(200, liveCache[memberID])
		return
	if !(await Firebase.memberExists(memberID)):
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
		var keys = await Firebase.getAllKeys(memberID)
		targetKeys = keys.size()
		print(keys)
		for key in keys:
			print("scanning ", key)
			MongoDB.getLiveData(key, liveData)
	else:
		MongoDB.getLiveData(request.query["key"], liveData)
	var i : int = 0
	while i < 50:
		i += 1
		await Firebase.get_tree().create_timer(0.2).timeout
		if liveData["keys"] == targetKeys:
			break
	var jsonString : String = JSON.stringify(liveData)
	liveCache[memberID] = jsonString
	response.send(200, jsonString)
