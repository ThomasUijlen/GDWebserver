extends Node

var ID_TOKEN : String = ""
var IP_ADDRESS : String = ""

func _ready():
	authenticate()

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

func getAllKeys(memberID : String):
	var resultData : Array = []
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			if json.has("documents"):
				for data in json["documents"]:
					resultData.append(data["name"])
	
	request.queue_free()
	return resultData

func getLiveData(memberID : String, keyName : String):
	var resultData = null
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName+"/LiveData",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			var playerCount : int = 0
			var lobbyCount : int = 0
			var dataUsage : int = 0
			for data in json["documents"]:
				var fields = data["fields"]
				playerCount += int(fields["PlayerCount"]["integerValue"])
				lobbyCount += int(fields["LobbyCount"]["integerValue"])
				dataUsage += int(fields["DataUsage"]["integerValue"])
			
			resultData = {
				"playercount" : playerCount,
				"lobbycount" : lobbyCount,
				"usage" : dataUsage,
			}
	
	request.queue_free()
	return resultData



func getDailyData(memberID : String, keyName : String):
	var resultData = {}
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	add_child(request)
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName+"/DailyData",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		
		if json != null:
			for data in json["documents"]:
				var fields = data["fields"]
				if resultData.has(fields["Day"]["integerValue"]):
					var dayData = resultData[fields["Day"]]
					dayData["playercount"] += int(fields["PlayerCount"]["integerValue"])
					dayData["lobbiesopened"] += int(fields["LobbiesOpened"]["integerValue"])
					dayData["usage"] += int(fields["DataUsage"]["integerValue"])
				else:
					var dayData = {}
					dayData["playercount"] = int(fields["PlayerCount"]["integerValue"])
					dayData["lobbiesopened"] = int(fields["LobbiesOpened"]["integerValue"])
					dayData["usage"] = int(fields["DataUsage"]["integerValue"])
					resultData[fields["Day"]["integerValue"]] = dayData
	
	request.queue_free()
	return resultData
