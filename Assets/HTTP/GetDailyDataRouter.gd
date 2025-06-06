extends HttpRouter
class_name GetDailyData

var lastDay : int = 0
var dailyCache : Dictionary = {}

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	var currentTime = Time.get_unix_time_from_system()
	var currentDay = int(floor(currentTime/86400))
	if currentDay != lastDay:
		lastDay = currentDay
		dailyCache.clear()
	
	if(dailyCache.has(request.query["memberid"])):
		response.send(200, dailyCache[request.query["memberid"]])
		return
	
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var dailyData : Dictionary = {}
	var targetKeys : int = 0
	
	var keys = await Firebase.getAllKeys(request.query["memberid"])
	var keysFiles = await Firebase.getAllKeysFile(request.query["memberid"])
	targetKeys = keys.size()
	
	var keyModifier : int = 0
	for i in range(keys.size()):
		var keyData : Dictionary = {}
		var keyName : String = keys[i]
		var fileName : String = keysFiles[i].get_file()
		Firebase.getKeyName(request.query["memberid"], fileName, keyData)
		MongoDB.getDailyData(request.query["memberid"], keyName, dailyData, keyData)
	
	var i : int = 0
	while i < 100:
		i += 1
		await Firebase.get_tree().create_timer(0.3).timeout
		if dailyData.size() == targetKeys+keyModifier:
			break
	await Firebase.get_tree().create_timer(0.1).timeout
	if dailyData != null:
		var jsonString : String = JSON.stringify(dailyData)
		dailyCache[request.query["memberid"]] = jsonString
		response.send(200, jsonString)
	else:
		response.send(401)
