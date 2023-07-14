extends Node

var ID_TOKEN : String = ""
var IP_ADDRESS : String = ""

func _ready():
	getIP()
	authenticate()
	getUsers()

func getIP():
	$GetIP.request("https://api.ipify.org")

func _on_get_ip_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(10.0).timeout
		getIP()
		return
	IP_ADDRESS = body.get_string_from_utf8()
	
	publishIP.call_deferred()

func publishIP():
	if ID_TOKEN.length() == 0:
		await get_tree().create_timer(10.0).timeout
		publishIP.call_deferred()
		return
	
	$PublishIP.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Servers/"+IP_ADDRESS,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_PATCH,
		JSON.stringify(
			{
				"fields": {
					"IP": {"stringValue": IP_ADDRESS},
					"Age": {"integerValue": roundi(Time.get_unix_time_from_system())},
					"Type": {"stringValue": "LoadBalancer"}
				}
			}
		)
	)
	
	await get_tree().create_timer(600).timeout
	publishIP.call_deferred()

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

func getUsers():
	if ID_TOKEN.length() == 0:
		await get_tree().create_timer(10.0).timeout
		getUsers.call_deferred()
		return
	
	$GetUsers.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)

func _on_get_users_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(10.0).timeout
		getUsers.call_deferred()
		return
	
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	if json != null:
		for data in json["documents"]:
			var fields = data["fields"]
			KeyLibrary.addKey(fields["PublicKey"]["stringValue"], fields["PrivateKey"]["stringValue"])
	
	await get_tree().create_timer(600).timeout
	getUsers.call_deferred()


func _on_publish_ip_request_completed(result, response_code, headers, body):
	pass

func getServers():
	$GetServers.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Servers",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)

func _on_get_servers_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(randf_range(31.0,50.0)).timeout
		getServers()
		return
	
	IPLibrary.clearServers()
	
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	if json != null:
		for data in json["documents"]:
			var fields = data["fields"]
			IPLibrary.addServer(fields)
