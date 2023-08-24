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
	
	for key in keys:
		var keyData : Dictionary = {}
		Firebase.getKeyName(request.query["memberid"], key.get_file(), keyData)
		Firebase.getDailyData(request.query["memberid"], key.get_file(), dailyData, keyData)
	
	var i : int = 0
	while i < 50:
		i += 1
		await Firebase.get_tree().create_timer(0.2).timeout
		if dailyData.size() == targetKeys:
			break
	await Firebase.get_tree().create_timer(0.1).timeout
	if dailyData != null:
		response.send(200, JSON.stringify(dailyData))
	else:
		response.send(401)
