extends Node

var ID_TOKEN : String = ""
var IP_ADDRESS : String = ""

func _ready():
	authenticate()
	randomize()

var counter : float = 0.0
func _process(delta):
	counter -= delta*1000.0
	if counter < 0.0: counter = 0.0

func firebaseGet(url : String) -> Array:
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	var jsonArray : Array = []
	var firstRequest : bool = true
	var i : int = 0
	var pageToken : String = ""
	
	while (firstRequest || pageToken != "") and i < 10:
		i += 1
		firstRequest = false
		var currentUrl : String = url
		if pageToken != "":
			currentUrl += "?pageToken="+pageToken
#		print("request!")
		request.request(
			currentUrl,
			["Authorization: Bearer "+ID_TOKEN],
			HTTPClient.METHOD_GET
		)
		pageToken = ""
		
		var result = await request.request_completed
		if result[1] == 200:
			var test_json_conv = JSON.new()
			test_json_conv.parse(result[3].get_string_from_utf8())
			var json = test_json_conv.get_data()
			if json != null:
				jsonArray.append(json)
				
				if json.has("nextPageToken"):
					pageToken = json["nextPageToken"]
	
	request.queue_free()
	
	return jsonArray

func authenticate():
	$Authenticate.request(
		"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="+ServerConfigs.API_KEY,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(
			{
				"email" : ServerConfigs.EMAIL,
				"password" : ServerConfigs.PASSWORD,
				"returnSecureToken" : true
			}
		)
	)

func _on_authenticate_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(10.0).timeout
		authenticate.call_deferred()
		return
	
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	if json != null:
		ID_TOKEN = json["idToken"]
		var expiresIn : float = float(json["expiresIn"])
		await get_tree().create_timer(expiresIn-60).timeout
		authenticate.call_deferred()
	else:
		await get_tree().create_timer(10.0).timeout
		authenticate.call_deferred()

func memberExists(memberID : String) -> bool:
	var resultData = {}
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		if json != null:
			return true
	return false

func getAllMembers():
	var resultData : Array = []
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users"
	)
	
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				resultData.append(data["fields"]["MemberID"]["stringValue"])
	
	return resultData

func getAllKeys(memberID : String):
	var resultData : Array = []
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys"
	)
	
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				
				resultData.append(data["name"])
	
	return resultData

func getAllKeyData(memberID : String):
	var resultData : Dictionary = {}
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys"
	)
	
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				
				var keyData : Dictionary = {}
				var fields = data["fields"]
				if !fields.has("PublicKey"): continue
				keyData["Name"] = fields["Name"]["stringValue"]
				keyData["PublicKey"] = fields["PublicKey"]["stringValue"]
				keyData["PrivateKey"] = fields["PrivateKey"]["stringValue"]
				resultData[data["name"].get_file()] = keyData
	
	return resultData

func getLiveData(memberID : String, keyName : String, liveData : Dictionary):
	var resultData = null
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName+"/LiveData"
	)
	
	var currentTime : int = Time.get_unix_time_from_system()
	var playerCount : int = 0
	var lobbyCount : int = 0
	var dataUsage : int = 0
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				
				var fields = data["fields"]
				var validTime : int = int(fields["ValidTime"]["integerValue"])
				if currentTime > validTime: continue
				
				playerCount += int(fields["PlayerCount"]["integerValue"])
				lobbyCount += int(fields["LobbyCount"]["integerValue"])
				dataUsage += int(fields["DataUsage"]["integerValue"])
	
	liveData["playercount"] += playerCount
	liveData["lobbycount"] += lobbyCount
	liveData["usage"] += dataUsage
	liveData["keys"] += 1



func getDailyData(memberID : String, keyName : String, dailyData : Dictionary, keyData : Dictionary):
	if keyName == "Default": return
	var resultData = {}
	var currentDay : int = floor(Time.get_unix_time_from_system()/86400)
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName+"/DailyData"
	)
	
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				
				var fields = data["fields"]
				var day : int = int(fields["Day"]["integerValue"])
#					print("-------")
#					print(day)
#					print(currentDay - 30)
#					print(day < currentDay - 30)
				if day < currentDay - 30: continue
				
				if resultData.has(day):
					var dayData = resultData[day]
					dayData["playercount"] += int(fields["PlayerCount"]["integerValue"])
					dayData["lobbiesopened"] += int(fields["LobbiesOpened"]["integerValue"])
					dayData["usage"] += int(fields["DataUsage"]["integerValue"])
				else:
					var dayData = {}
					dayData["playercount"] = int(fields["PlayerCount"]["integerValue"])
					dayData["lobbiesopened"] = int(fields["LobbiesOpened"]["integerValue"])
					dayData["usage"] = int(fields["DataUsage"]["integerValue"])
					resultData[day] = dayData
	
	keyData["MonthlyData"] = resultData
	dailyData[keyName] = keyData

func getKeyData(memberID : String, keyName : String):
	var resultData = {}
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
#	print("get key data")
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			counter += 1.0
			
			var fields = json["fields"]
			resultData["Name"] = fields["Name"]["stringValue"]
			resultData["PublicKey"] = fields["PublicKey"]["stringValue"]
			resultData["PrivateKey"] = fields["PrivateKey"]["stringValue"]
	
	request.queue_free()
	return resultData

func getKeyName(memberID : String, keyName : String, targetData : Dictionary):
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
#	print("get key name")
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			counter += 1.0
			
			var fields = json["fields"]
			targetData["Name"] = fields["Name"]["stringValue"]
	
	request.queue_free()

func getPlanData(memberID : String):
	var resultData : Dictionary = {
		"Name" : "None",
		"DataCap" : 0,
		"KeyCap": 0,
	}
	
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 10
	add_child(request)
#	print("get plan data")
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/Plans",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	var newestPlan = null
	var planName : String = "free"
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			if json.has("documents"):
				for data in json["documents"]:
					counter += 1.0
					
					var fields = data["fields"]
					var time = int(fields["EndTimestamp"]["stringValue"])
					if time < Time.get_unix_time_from_system(): continue
					if newestPlan == null || int(newestPlan["EndTimestamp"]["stringValue"]) < time:
						newestPlan = fields
						planName = fields["Plan"]["stringValue"]
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Plans/"+planName,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			counter += 1.0
			
			var fields = json["fields"]
			resultData["Name"] = json["name"].get_file()
			resultData["DataCap"] = int(fields["DataCap"]["integerValue"])
			resultData["KeyCap"] = int(fields["KeyCap"]["integerValue"])
			
			resultData["DatabaseLimit"] = int(fields["DatabaseLimit"]["integerValue"])
			resultData["StorageLimit"] = int(fields["StorageLimit"]["integerValue"])
			
			if newestPlan:
				resultData["ResetTime"] = time_until_reset(int(newestPlan["EndTimestamp"]["stringValue"]))
				resultData["ResetUnix"] = int(newestPlan["EndTimestamp"]["stringValue"])
			else:
				resultData["ResetTime"] = time_until_reset(int(floor(Time.get_unix_time_from_system()/86400)+1)*86400)
				resultData["ResetUnix"] = int(floor(Time.get_unix_time_from_system()/86400)+1)*86400
	
	request.queue_free()
	return resultData

func time_until_reset(target_time: int) -> String:
	var seconds_left = target_time - Time.get_unix_time_from_system()
	
	if seconds_left <= 0:
		return "Time has already passed."
	
	var hours_left = ceil(seconds_left / 3600.0)
	
	if hours_left > 24:
		var days_left = int(hours_left / 24)
		if days_left == 1:
			return "1 day until reset."
		else:
			return str(days_left) + " days until reset."
	else:
		if hours_left == 1:
			return "1 hour until reset."
		else:
			return str(int(hours_left)) + " hours until reset."


func createAPIKey(memberID : String, keyName : String):
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
#	print("create api key")
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_POST,
		JSON.stringify(
			{
				"fields": {
					"IsServer": {"booleanValue": false},
					"MemberID": {"stringValue": memberID},
					"Name": {"stringValue": keyName.replace("%20", " ")},
					"PublicKey": {"stringValue": generateUniqueID()},
					"PrivateKey": {"stringValue": generateUniqueID()},
				}
			}
		)
	)
	
	counter += 5.0
	
	var result = await request.request_completed
	request.queue_free()
	return result[1] == 200

func updateAPIKey(memberID : String, key : String, keyName : String, database : String):
	if key == "Default": return
	var data : Dictionary = await getKeyData(memberID, key)
	if data.size() == 0: return false
	
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
#	print("rename API key")
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+key,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_PATCH,
		JSON.stringify(
			{
				"fields": {
					"Name": {"stringValue": keyName.replace("%20", " ")},
					"IsServer" : {"booleanValue": false},
					"MemberID": {"stringValue": memberID},
					"PrivateKey": {"stringValue": data["PrivateKey"]},
					"PublicKey": {"stringValue": data["PublicKey"]},
					"Database": {"stringValue": database},
				}
			}
		)
	)
	
	counter += 5.0
	
	var result = await request.request_completed
	request.queue_free()
	return result[1] == 200

func markPlayerChanged(memberID : String):
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
#	print("mark player change")
	var playerData : Dictionary = {}
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			var fields = json["fields"]
			if !fields.has("Changed"): fields["Changed"] = {"integerValue" : 0}
			fields["Changed"]["integerValue"] = int(Time.get_unix_time_from_system())
			
			request.request(
				"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID,
				["Authorization: Bearer "+ID_TOKEN],
				HTTPClient.METHOD_PATCH,
				JSON.stringify(
					{
						"fields": fields
					}
				)
			)
			
			counter += 5.0
			
			await request.request_completed
	request.queue_free()

func deleteAPIKey(memberID : String, key : String):
	if key == "Default": return
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+key,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_DELETE,
	)
	await request.request_completed
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/Default",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_PATCH,
		JSON.stringify(
			{
				"fields": {
					"Name": {"stringValue": "Default"}
				}
			}
		)
	)
	await request.request_completed
	
	var liveData = {
		"playercount" : 0,
		"lobbycount" : 0,
		"usage" : 0,
		"keys" : 0,
	}
	await Firebase.getLiveData(memberID, key, liveData)
	
	var planData : Dictionary = await getPlanData(memberID)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/Default/LiveData/"+str(randi_range(0,100000000)),
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_PATCH,
		JSON.stringify(
			{
				"fields": {
					"IP": {"stringValue": IP_ADDRESS},
					"LobbyCount": {"integerValue": 0},
					"PlayerCount": {"integerValue": 0},
					"DataUsage": {"integerValue": liveData["usage"]},
					"ValidTime": {"integerValue": planData["ResetUnix"]}
				}
			}
		)
	)
	await request.request_completed
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+key,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_DELETE,
	)
	await request.request_completed
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+key+"/LiveData",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_DELETE,
	)
	await request.request_completed
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+key+"/DailyData",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_DELETE,
	)
	await request.request_completed
	
	counter += 30.0
	
	request.queue_free()


const MODULO_8_BIT = 256
func getRandomInt():
	randomize()
	return randi() % MODULO_8_BIT

func uuidbin():
	return [
		getRandomInt(), getRandomInt(), getRandomInt(), getRandomInt(),
		((getRandomInt()) & 0x0f) | 0x40, getRandomInt(),
		((getRandomInt()) & 0x3f) | 0x80, getRandomInt(),
	]

func generateUniqueID() -> String:
	var b = uuidbin()
	return '%02x%02x%02x%02x%02x%02x%02x%02x' % [
		b[0], b[1], b[2], b[3],
		b[4], b[5],
		b[6], b[7]
	]

func flooded() -> bool:
	return counter > 1000
