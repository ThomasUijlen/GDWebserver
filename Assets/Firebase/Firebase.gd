extends Node

var ID_TOKEN : String = ""
var IP_ADDRESS : String = ""

func _ready():
	authenticate()
	randomize()

var counter : float = 0.0
var charts_cache : Dictionary = {}
var charts_cache_plan : Dictionary = {}
var charts_cache_day : int = 0

func _process(delta):
	counter -= delta*1000.0
	if counter < 0.0: counter = 0.0

func _roll_charts_cache_day() -> void:
	var day : int = int(floor(Time.get_unix_time_from_system() / 86400.0))
	if day != charts_cache_day:
		charts_cache_day = day
		charts_cache.clear()
		charts_cache_plan.clear()

func invalidate_charts_cache(member_id : String) -> void:
	charts_cache.erase(member_id)
	charts_cache_plan.erase(member_id)

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
	request.queue_free()
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
				
				if "APIKeys/Default" in data["name"]:
					continue
				
				resultData.append(data["fields"]["PublicKey"]["stringValue"])
	
	return resultData

func getAllKeysFile(memberID : String):
	var resultData : Array = []
	
	var jsonArray : Array = await firebaseGet(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/APIKeys"
	)
	
	for json in jsonArray:
		if json.has("documents"):
			for data in json["documents"]:
				counter += 1.0
				
				if "Default" in data["name"]:
					continue
				
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
				
				if fields.has("Database"):
					keyData["Database"] = fields["Database"]["stringValue"]
				else:
					keyData["Database"] = ""
				
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

func _firestore_scalar(field) -> String:
	if typeof(field) != TYPE_DICTIONARY:
		return ""
	if field.has("stringValue"):
		return str(field["stringValue"])
	if field.has("integerValue"):
		return str(field["integerValue"])
	if field.has("doubleValue"):
		return str(int(field["doubleValue"]))
	return ""

func _fetch_plan_catalog(request : HTTPRequest, planName : String) -> Dictionary:
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Plans/"+planName,
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	var result = await request.request_completed
	if result[1] != 200:
		return {}
	var test_json_conv = JSON.new()
	test_json_conv.parse(result[3].get_string_from_utf8())
	var json = test_json_conv.get_data()
	if json == null or !json.has("fields"):
		return {}
	counter += 1.0
	var fields = json["fields"]
	return {
		"Name": json["name"].get_file(),
		"DataCap": int(fields["DataCap"]["integerValue"]) if fields.has("DataCap") else 0,
		"KeyCap": int(fields["KeyCap"]["integerValue"]) if fields.has("KeyCap") else 0,
		"DatabaseLimit": int(fields["DatabaseLimit"]["integerValue"]) if fields.has("DatabaseLimit") else 0,
		"StorageLimit": int(fields["StorageLimit"]["integerValue"]) if fields.has("StorageLimit") else 0,
		"PlayerLimit": int(fields["PlayerLimit"]["integerValue"]) if fields.has("PlayerLimit") else 0,
		"MonthlyDataCap": int(fields["MonthlyDataCap"]["integerValue"]) if fields.has("MonthlyDataCap") else 0,
	}

const FREE_CYCLE_PERIOD_SECONDS : int = 30 * 86400
const FREE_CYCLE_PENDING_RESET := "30 days until reset."

func free_cycle_next_reset(anchor : int, now : int = -1) -> int:
	if anchor <= 0:
		return 0
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	if now < anchor:
		return anchor + FREE_CYCLE_PERIOD_SECONDS
	var periods : int = int(floor(float(now - anchor) / float(FREE_CYCLE_PERIOD_SECONDS))) + 1
	return anchor + periods * FREE_CYCLE_PERIOD_SECONDS

func _free_cycle_anchor(memberID : String) -> int:
	if memberID.is_empty():
		return 0
	var bag := {"ready": false, "ok": false, "anchor": 0}
	MongoDB.ReadFreeCycleAnchor(memberID, bag)
	var started := Time.get_unix_time_from_system()
	while !bool(bag.get("ready", false)):
		await get_tree().process_frame
		if Time.get_unix_time_from_system() - started > 5.0:
			return 0
	if !bool(bag.get("ok", false)):
		return 0
	return int(bag.get("anchor", 0))

func _apply_free_cycle_reset(resultData : Dictionary, memberID : String) -> void:
	var anchor := await _free_cycle_anchor(memberID)
	if anchor <= 0:
		resultData["CycleEstablished"] = false
		resultData["ResetUnix"] = 0
		resultData["ResetTime"] = FREE_CYCLE_PENDING_RESET
		return
	var nextReset := free_cycle_next_reset(anchor)
	resultData["CycleEstablished"] = true
	resultData["ResetUnix"] = nextReset
	resultData["ResetTime"] = time_until_reset(nextReset)

## Matches the database. A paid plan stays active this long after EndTimestamp.
const PLAN_GRACE_SECONDS : int = 3 * 86400

func _plan_period_length(start_unix : int, end_unix : int) -> int:
	if start_unix <= 0 or end_unix <= start_unix:
		return 30 * 86400
	return end_unix - start_unix

func getPlanData(memberID : String):
	var resultData : Dictionary = {
		"Name" : "None",
		"DataCap" : 0,
		"KeyCap": 0,
	}
	
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 10
	add_child(request)
	request.request(
		"https://firestore.googleapis.com/v1/projects/"+ServerConfigs.PROJECT_ID+"/databases/(default)/documents/Users/"+memberID+"/Plans",
		["Authorization: Bearer "+ID_TOKEN],
		HTTPClient.METHOD_GET
	)
	
	var result = await request.request_completed
	
	# Valid overlapping subscriptions: pick highest catalog tier, not latest end date
	# (yearly + monthly upgrade → monthly while active, then yearly again).
	var candidates : Array = []
	if result[1] == 200:
		var test_json_conv = JSON.new()
		test_json_conv.parse(result[3].get_string_from_utf8())
		var json = test_json_conv.get_data()
		if json != null and json.has("documents"):
			var now : int = int(Time.get_unix_time_from_system())
			for data in json["documents"]:
				counter += 1.0
				var fields = data["fields"]
				if !fields.has("EndTimestamp") || !fields.has("Plan"):
					continue
				var plan_str : String = _firestore_scalar(fields["Plan"])
				var end_str : String = _firestore_scalar(fields["EndTimestamp"])
				if plan_str.is_empty() or end_str.is_empty():
					continue
				var end_time : int = int(end_str)
				if end_time + PLAN_GRACE_SECONDS < now:
					continue
				candidates.append({
					"Plan": plan_str,
					"EndTimestamp": end_time,
					"StartTimestamp": _firestore_scalar(fields.get("StartTimestamp", {})),
				})
	
	var planName : String = "free"
	var selected_end : int = -1
	if !candidates.is_empty():
		var catalog_by_name : Dictionary = {}
		for cand in candidates:
			var name : String = cand["Plan"]
			if catalog_by_name.has(name):
				continue
			catalog_by_name[name] = await _fetch_plan_catalog(request, name)
		
		var best = null
		var best_cap : int = -1
		var best_players : int = -1
		var best_end : int = -1
		for cand in candidates:
			var cat : Dictionary = catalog_by_name.get(cand["Plan"], {})
			var cap : int = int(cat.get("DataCap", 0))
			var players : int = int(cat.get("PlayerLimit", 0))
			var end_time : int = int(cand["EndTimestamp"])
			var better : bool = false
			if best == null:
				better = true
			elif cap != best_cap:
				better = cap > best_cap
			elif players != best_players:
				better = players > best_players
			else:
				better = end_time > best_end
			if better:
				best = cand
				best_cap = cap
				best_players = players
				best_end = end_time
		if best != null:
			planName = best["Plan"]
			selected_end = int(best["EndTimestamp"])
			var cat : Dictionary = catalog_by_name.get(planName, {})
			if !cat.is_empty():
				resultData["Name"] = cat["Name"]
				resultData["DataCap"] = cat["DataCap"]
				resultData["KeyCap"] = cat["KeyCap"]
				resultData["DatabaseLimit"] = cat["DatabaseLimit"]
				resultData["StorageLimit"] = cat["StorageLimit"]
				# During the grace window the real end is already past. The label
				# counts down to the following cycle, one period after this one.
				var display_end := selected_end
				if selected_end < int(Time.get_unix_time_from_system()):
					var start_unix := int(str(best.get("StartTimestamp", "0")))
					display_end = selected_end + _plan_period_length(start_unix, selected_end)
				resultData["ResetTime"] = time_until_reset(display_end)
				resultData["ResetUnix"] = display_end
				request.queue_free()
				var live_name : String = str(resultData.get("Name", "None"))
				_roll_charts_cache_day()
				if charts_cache_plan.has(memberID) and str(charts_cache_plan[memberID]) != live_name:
					invalidate_charts_cache(memberID)
				return resultData
	
	# free / no valid subscription — still load catalog defaults
	var free_cat : Dictionary = await _fetch_plan_catalog(request, planName)
	if !free_cat.is_empty():
		resultData["Name"] = free_cat["Name"]
		resultData["DataCap"] = free_cat["DataCap"]
		resultData["KeyCap"] = free_cat["KeyCap"]
		resultData["DatabaseLimit"] = free_cat["DatabaseLimit"]
		resultData["StorageLimit"] = free_cat["StorageLimit"]
	# MonthlyDataCap is absent until the rollout writes it. Until then the free
	# plan keeps the daily cap and the next-midnight reset.
	var monthlyCap : int = int(free_cat.get("MonthlyDataCap", 0)) if !free_cat.is_empty() else 0
	if monthlyCap > 0:
		resultData["DataCap"] = monthlyCap
		await _apply_free_cycle_reset(resultData, memberID)
	else:
		resultData["ResetTime"] = time_until_reset(int(floor(Time.get_unix_time_from_system()/86400)+1)*86400)
		resultData["ResetUnix"] = int(floor(Time.get_unix_time_from_system()/86400)+1)*86400
	
	request.queue_free()
	var live_name2 : String = str(resultData.get("Name", "None"))
	_roll_charts_cache_day()
	if charts_cache_plan.has(memberID) and str(charts_cache_plan[memberID]) != live_name2:
		invalidate_charts_cache(memberID)
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
	if result[1] == 200:
		await markPlayerChanged(memberID)
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
	if result[1] == 200:
		await markPlayerChanged(memberID)
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
	await notifyKeyInvalidation(memberID)

var _keyInvalidationPending : Dictionary = {}
var _keyInvalidationFlushing : bool = false

func notifyKeyInvalidation(memberID : String) -> void:
	if memberID.is_empty():
		return
	_keyInvalidationPending[memberID] = true
	if _keyInvalidationFlushing:
		while _keyInvalidationPending.has(memberID):
			await get_tree().process_frame
		return
	_keyInvalidationFlushing = true
	while !_keyInvalidationPending.is_empty():
		var id : String = str(_keyInvalidationPending.keys()[0])
		var generation : int = 0
		while generation <= 0:
			generation = int(MongoDB.WriteKeyInvalidation(id))
			if generation <= 0:
				await get_tree().create_timer(1.0).timeout
		while _keyInvalidationPending.has(id):
			if bool(MongoDB.HasKeyInvalidationSettled(id, generation)):
				_keyInvalidationPending.erase(id)
				break
			await get_tree().process_frame
	_keyInvalidationFlushing = false

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
	await markPlayerChanged(memberID)


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

func get_keys_page(member_id : String) -> Dictionary:
	var bag : Dictionary = { "keydata": {}, "plan": {}, "left": 2 }
	_page_fill_keys(member_id, bag)
	_page_fill_plan(member_id, bag)
	while int(bag.left) > 0:
		await get_tree().process_frame
	return { "keys": bag.keydata, "plan": bag.plan }

func _page_fill_keys(member_id : String, bag : Dictionary) -> void:
	bag.keydata = await getAllKeyData(member_id)
	bag.left -= 1

func _page_fill_plan(member_id : String, bag : Dictionary) -> void:
	bag.plan = await getPlanData(member_id)
	bag.left -= 1

func get_live_snapshot(member_id : String, key : String) -> Dictionary:
	var live : Dictionary = {
		"playercount": 0,
		"lobbycount": 0,
		"usage": 0,
		"keys": 0,
	}
	var all : Dictionary = await getAllKeyData(member_id)
	var public_keys : Array = []
	if key == "All" or key == "all" or key == "":
		for id in all:
			if str(id) == "Default":
				continue
			public_keys.append(all[id]["PublicKey"])
	elif all.has(key):
		public_keys.append(all[key]["PublicKey"])
	else:
		public_keys.append(key)
	if public_keys.is_empty():
		return live
	var target : int = public_keys.size()
	for pk in public_keys:
		MongoDB.getLiveDataFast(str(pk), live)
	var i : int = 0
	while i < 50:
		i += 1
		await get_tree().create_timer(0.15).timeout
		if int(live["keys"]) >= target:
			break
	return live

func plan_allows_charts(plan_name : String) -> bool:
	var n := str(plan_name).strip_edges().to_lower()
	return n != "" and n != "free" and n != "none"

func get_charts_page(member_id : String) -> Dictionary:
	var page : Dictionary = await get_keys_page(member_id)
	var keys : Dictionary = page["keys"]
	var plan_name : String = str(page["plan"].get("Name", "free"))
	var charts : bool = plan_allows_charts(plan_name)
	var daily : Dictionary = {}
	var pending : int = 0
	for id in keys:
		if str(id) == "Default":
			continue
		pending += 1
	if pending == 0:
		return { "keys": keys, "daily": daily, "charts": charts }
	var bag : Dictionary = { "left": pending, "daily": daily }
	for id in keys:
		if str(id) == "Default":
			continue
		_daily_one(member_id, str(id), keys[id], plan_name, bag)
	while int(bag.left) > 0:
		await get_tree().process_frame
	return { "keys": keys, "daily": bag.daily, "charts": charts }

func _daily_one(member_id : String, key_id : String, key_info : Dictionary, plan_name : String, bag : Dictionary) -> void:
	var name : String = str(key_info.get("Name", ""))
	var public_key : String = str(key_info.get("PublicKey", ""))
	if public_key.is_empty():
		bag.daily[key_id] = { "Name": name, "Plan": plan_name, "MonthlyData": {}, "Regions": {} }
		bag.left -= 1
		return
	var key_data : Dictionary = { "Name": name, "Plan": plan_name }
	var slot : Dictionary = {}
	MongoDB.getDailyData(member_id, public_key, slot, key_data)
	var i : int = 0
	while i < 80:
		i += 1
		await get_tree().create_timer(0.15).timeout
		if slot.has(public_key):
			bag.daily[key_id] = slot[public_key]
			bag.left -= 1
			return
	bag.daily[key_id] = { "Name": name, "Plan": plan_name, "MonthlyData": {}, "Regions": {} }
	bag.left -= 1
