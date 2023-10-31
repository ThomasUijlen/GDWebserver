extends HttpRouter
class_name GetDailyData

func handle_get(request, response):
	if !(await Firebase.memberExists(request.query["memberid"])):
		response.send(403)
		return
	
	var dailyData : Dictionary = {}
	var targetKeys : int = 0
	
	var keys = await Firebase.getAllKeys(request.query["memberid"])
	targetKeys = keys.size()
	
	var keyModifier : int = 0
	for key in keys:
		var keyData : Dictionary = {}
		var keyName : String = key.get_file()
		if keyName == "Default": keyModifier = -1
		Firebase.getKeyName(request.query["memberid"], keyName, keyData)
		Firebase.getDailyData(request.query["memberid"], keyName, dailyData, keyData)
	
	var i : int = 0
	while i < 20:
		i += 1
		await Firebase.get_tree().create_timer(0.2).timeout
		if dailyData.size() == targetKeys+keyModifier:
			break
	await Firebase.get_tree().create_timer(0.1).timeout
	if dailyData != null:
		response.send(200, JSON.stringify(dailyData))
	else:
		response.send(401)
