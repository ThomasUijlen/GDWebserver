extends HttpRouter
class_name GetDailyData

var lastDay : int = 0
var dailyCache : Dictionary = {}

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	var memberID : String = await MemberstackAuth.require_id(request, response)
	if memberID == "":
		return
	var currentTime = Time.get_unix_time_from_system()
	var currentDay = int(floor(currentTime/86400))
	if currentDay != lastDay:
		lastDay = currentDay
		dailyCache.clear()
	if(dailyCache.has(memberID)):
		response.send(200, dailyCache[memberID])
		return
	if !(await Firebase.memberExists(memberID)):
		response.send(403)
		return
	var planData : Dictionary = await Firebase.getPlanData(memberID)
	var planName : String = planData.get("Name", "free")
	var dailyData : Dictionary = {}
	var targetKeys : int = 0
	var keys = await Firebase.getAllKeys(memberID)
	var keysFiles = await Firebase.getAllKeysFile(memberID)
	targetKeys = keys.size()
	var keyModifier : int = 0
	for i in range(keys.size()):
		var keyData : Dictionary = {}
		keyData["Plan"] = planName
		var keyName : String = keys[i]
		var fileName : String = keysFiles[i].get_file()
		Firebase.getKeyName(memberID, fileName, keyData)
		MongoDB.getDailyData(memberID, keyName, dailyData, keyData)
	var i : int = 0
	while i < 100:
		i += 1
		await Firebase.get_tree().create_timer(0.3).timeout
		if dailyData.size() == targetKeys+keyModifier:
			break
	await Firebase.get_tree().create_timer(1.0).timeout
	if dailyData != null:
		var jsonString : String = JSON.stringify(dailyData)
		dailyCache[memberID] = jsonString
		response.send(200, jsonString)
	else:
		response.send(401)
