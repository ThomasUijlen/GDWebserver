extends RefCounted
class_name MemberstackAuth

const VERIFY_URL := "https://admin.memberstack.com/members/verify-token"
const CACHE_TTL := 300.0
const CACHE_CAP := 2048

static var _cache: Dictionary = {}

static func extract_bearer(request: HttpRequest) -> String:
	var auth := ""
	if request.headers.has("Authorization"):
		auth = str(request.headers["Authorization"])
	elif request.headers.has("authorization"):
		auth = str(request.headers["authorization"])
	auth = auth.strip_edges()
	if auth.to_lower().begins_with("bearer "):
		return auth.substr(7).strip_edges()
	return ""

static func require_id(request: HttpRequest, response: HttpResponse) -> String:
	var token := extract_bearer(request)
	if token != "":
		var member_id := await verify(token)
		if member_id != "":
			return member_id
	response.send(401)
	return ""

static func verify(token: String) -> String:
	if token == "":
		return ""
	var cache_key := token.sha256_text()
	var now := Time.get_unix_time_from_system()
	if _cache.has(cache_key):
		var row: Dictionary = _cache[cache_key]
		if float(row.get("exp", 0.0)) > now:
			return str(row.get("id", ""))
		_cache.erase(cache_key)
	var member_id := await _verify_remote(token)
	if member_id == "":
		return ""
	if _cache.size() >= CACHE_CAP:
		_cache.clear()
	_cache[cache_key] = {
		"id": member_id,
		"exp": now + CACHE_TTL
	}
	return member_id

static func _verify_remote(token: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 10
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	tree.root.add_child(http)
	var err := http.request(
		VERIFY_URL,
		PackedStringArray([
			"Content-Type: application/json",
			"X-API-KEY: " + ServerConfigs.memberstackSecretKey
		]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"token": token})
	)
	if err != OK:
		http.queue_free()
		return ""
	var completed: Array = await http.request_completed
	http.queue_free()
	var status: int = completed[1]
	if status != 200:
		return ""
	var body := (completed[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(body)
	if parsed is Dictionary:
		var payload: Dictionary = parsed
		var data = payload.get("data", payload)
		if data is Dictionary:
			return str(data.get("id", ""))
	return ""
