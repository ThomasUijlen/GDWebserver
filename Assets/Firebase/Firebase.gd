extends Node

var ID_TOKEN : String = ""
var IP_ADDRESS : String = ""

class HTTPData:
	signal requestCompleted
	var data

var liveDataList : Dictionary = {}

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

func getLiveData(memberID : String, keyName : String):
	var data : HTTPData = HTTPData.new()
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 5
	request.request_completed.connect(_player_count_complete)
	add_child(request)
	
	liveDataList[keyName] = data
	
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys/"+keyName+"/LiveData",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	autoComplete(data)
	await data.requestCompleted
	request.queue_free()
	liveDataList.erase(keyName)
	return data.data

func autoComplete(data : HTTPData):
	await get_tree().create_timer(5.0).timeout
	data.requestCompleted.emit()

func _player_count_complete(result, response_code, headers, body):
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	
	if json != null:
		var httpData : HTTPData = null
		for data in json["documents"]:
			if httpData: break
			for name in liveDataList:
				if name in data["name"]:
					httpData = liveDataList[name]
					break
		
		var playerCount : int = 0
		var lobbyCount : int = 0
		var dataUsage : int = 0
		for data in json["documents"]:
			var fields = data["fields"]
			playerCount += int(fields["PlayerCount"]["integerValue"])
			playerCount += int(fields["LobbyCount"]["integerValue"])
			playerCount += int(fields["DataUsage"]["integerValue"])
		
		if httpData:
			httpData.data = JSON.stringify(
				{
					"playercount" : playerCount,
					"lobbycount" : lobbyCount,
					"usage" : dataUsage,
				}
			)
			httpData.requestCompleted.emit()
