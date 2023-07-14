extends Node

const url = "https://api.airtable.com/v0/"
var playerTable : String = url+ServerConfigs.base+"/Players"
var serverTable : String = url+ServerConfigs.base+"/Servers"

var ip : String = ""

func _ready():
	randomize()
	getIP()

var ipTimer : float = 3600
func _process(delta):
	ipTimer -= delta
	if ipTimer <= 0.0:
		ipTimer = 3600+randf_range(-100,100)
		publishIP()

func getIP():
	$GetIP.request("https://api.ipify.org")

func _on_get_ip_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(randf_range(5.0,10.0)).timeout
		getIP()
		return
	ip = body.get_string_from_utf8()
	ipTimer = 0.0

func publishIP():
	$PublishIP.request(
		serverTable,
		["Authorization: Bearer "+ServerConfigs.databaseToken,
		"Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(
			{
				"fields" : {
					"IP" : ip,
					"Age" : Time.get_unix_time_from_system(),
					"Type" : "LoadBalancer"
				}
			}
		)
	)

func _on_publish_ip_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(randf_range(31.0,50.0)).timeout
		publishIP()
		return
	
	getServers()

func getServers():
	$GetServers.request(
		serverTable,
		["Authorization: Bearer "+ServerConfigs.databaseToken],
		HTTPClient.METHOD_GET
	)

func _on_get_servers_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(randf_range(31.0,50.0)).timeout
		getServers()
		return
	
	IPLibrary.clearServers()
	
	var data = JSON.new().parse_string(body.get_string_from_utf8())
	for record in data["records"]:
		IPLibrary.addServer(record)
	
	cleanupServers()

func cleanupServers():
	if IPLibrary.oldServers.size() == 0: return
	
	var text = "?"
	for i in range(IPLibrary.oldServers.size()):
		if i >= 10: break
		if i > 0: text += "&"
		text += "records="+IPLibrary.oldServers[i]
	
	if IPLibrary.oldServers.size() > 1:
		$DeleteOldServers.cancel_request()
		$DeleteOldServers.request(
			serverTable+text,
			["Authorization: Bearer "+ServerConfigs.databaseToken],
			HTTPClient.METHOD_DELETE
		)
	else:
		$DeleteOldServers.request(
		serverTable+"/"+IPLibrary.oldServers[0],
		["Authorization: Bearer "+ServerConfigs.databaseToken],
		HTTPClient.METHOD_DELETE
		)


func _on_delete_old_servers_request_completed(result, response_code, headers, body):
	if response_code != 200 and response_code != 404:
		await get_tree().create_timer(randf_range(31.0,50.0)).timeout
		getServers()
		return
	
	for i in range(10):
		if IPLibrary.oldServers.size() == 0: break
		IPLibrary.oldServers.pop_front()
	
	if IPLibrary.oldServers.size() > 0:
		await get_tree().create_timer(randf_range(3.0,4.0)).timeout
		getServers()

func getKeys():
	$GetKeys.request(
	playerTable,
	["Authorization: Bearer "+ServerConfigs.databaseToken],
	HTTPClient.METHOD_GET
	)

func _on_GetKeys_request_completed(result, response_code, headers, body):
	if response_code != 200:
		await get_tree().create_timer(randf_range(31.0,50.0)).timeout
		getKeys()
		return
	
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	if json == null: return
	for record in json["records"]:
		var fields : Dictionary = record["fields"]
		KeyLibrary.addKey(fields["PublicKey"], fields["PrivateKey"])
