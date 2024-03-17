extends HttpRouter
class_name GetAllData

func handle_get(request, response):
	if Firebase.flooded():
		response.send(429)
		return
	
	if request.query["secret"] != "F88B3A4D62597972DBB8333F7156B":
		response.send(403)
		return
	
	var members = await Firebase.getAllMembers()
	var user_data : Dictionary = {}
	var targetMembers : int = members.size()
	
	for member in members:
		get_data(member, user_data)
	
	var i : int = 0
	while i < 10000:
		i += 1
		await Firebase.get_tree().create_timer(0.5).timeout
		if user_data.size() == targetMembers:
			break
	await Firebase.get_tree().create_timer(0.5).timeout
	
	
	var endData : Dictionary = {}
	for user in user_data:
		var keyData : Dictionary = user_data[user]
		var cleanData : Dictionary = {
			"players" : 0,
			"lobbies" : 0,
			"dataUsage" : 0
		}
		
		for key in keyData:
			var monthlyData : Dictionary = keyData[key]["MonthlyData"]
			
			for day in monthlyData:
				var dayData : Dictionary = monthlyData[day]
				cleanData["players"] += dayData["playercount"]
				cleanData["lobbies"] += dayData["lobbiesopened"]
				cleanData["dataUsage"] += dayData["usage"]
		
		endData[user] = cleanData
	
	var dataArray : Array = []
	for key in endData.keys():
		var item = endData[key]
		item["key"] = key
		dataArray.append(item)
	
	dataArray.sort_custom(compare_data_usage)
	
	var sortedDict : Dictionary = {}
	for item in dataArray:
		sortedDict[item["key"]] = item
	
	var endString : String = ""
	
	for user in sortedDict:
		var data : Dictionary = sortedDict[user]
		if data["players"] == 0: continue
		endString += "***********************\n"
		endString += "Data for member: "+user
		endString += "\n--------"
		endString += "\nTotal daily players last month: "+str(data["players"])
		endString += "\nTotal lobbies opened last month: "+str(data["lobbies"])
		endString += "\nTotal data usage: "+str(data["dataUsage"])
		endString += "\n--------\n\n"
	
#	var jsonString : String = JSON.stringify(endData)
	response.send(200, endString)

func compare_data_usage(a, b):
	return a["dataUsage"] > b["dataUsage"]

func get_data(member : String, dic : Dictionary):
	var dailyData : Dictionary = {}
	var targetKeys : int = 0
	
	var keys = await Firebase.getAllKeys(member)
	targetKeys = keys.size()
	
	var keyModifier : int = 0
	for key in keys:
		var keyData : Dictionary = {}
		var keyName : String = key.get_file()
		if keyName == "Default": keyModifier = -1
		Firebase.getKeyName(member, keyName, keyData)
		Firebase.getDailyData(member, keyName, dailyData, keyData)
	
	var i : int = 0
	while i < 100:
		i += 1
		await Firebase.get_tree().create_timer(0.3).timeout
		if dailyData.size() == targetKeys+keyModifier:
			break
	await Firebase.get_tree().create_timer(0.3).timeout
	
	dic[member] = dailyData
