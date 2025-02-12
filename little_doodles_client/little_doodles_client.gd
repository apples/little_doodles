class_name LittleDoodlesClient extends HTTPRequest
## Client class for interacting with a LittleDoodles Server.
##

## LittleDoodles API Endpoints 
const Endpoints = {
	USER_AUTH = "/game/user/auth/",
	USER_CREATE = "/game/user/add/",
	ENTITY_SEARCH = "/game/entity/search/?%s",
	ENTITY_CREATE = "/game/entity/add/",
	ENTITY_GET = "/game/entity/%s/"
}

## The URL including protocol and domain name where the LittleDoodlesServer
## is running. Supports HTTP or HTTPS, as well as arbitrary ports.
@export var api_url = "https://example.com"

var _cookiejar = PackedStringArray()


## Register a new user account with the server. Also logs the user in. Returns
## true if successful
func create_user(username: String, password: String) -> bool:
	var resp = await _send_request(Endpoints.USER_CREATE)
	if resp == null:
		return false
	resp = await _send_request(
		Endpoints.USER_CREATE, 
		HTTPClient.METHOD_POST,
		"csrfmiddlewaretoken=%s&username=%s&password1=%s&password2=%s" % [
			resp["csrf_token"], username, password, password,
		]
	)
	return resp != null


## Log an existing user into the server. Returns true is successful
func auth_user(username: String, password: String) -> bool:
	var resp = await _send_request(Endpoints.USER_AUTH)
	if resp == null:
		return false
	resp = await _send_request(
		Endpoints.USER_AUTH, 
		HTTPClient.METHOD_POST,
		"csrfmiddlewaretoken=%s&username=%s&password=%s" % [
			resp["csrf_token"], username, password,
		]
	)
	return resp != null

## Create the Entity on the server if it doesn't already have a UUID, otherwise
## update it. Returns true if the save completed successfully
func save_entity(entity: LittleDoodlesEntity) -> bool:
	var endpoint = Endpoints.ENTITY_CREATE if entity.uuid == null else Endpoints.ENTITY_GET % entity.uuid
	var resp = await _send_request(endpoint)
	if resp == null:
		return false
	resp = await _send_request(
		endpoint, HTTPClient.METHOD_POST, entity.as_request_body(resp["csrf_token"])
	)
	return resp != null


## Returns an Entity instance selected via UUID.
func get_entity(uuid: String):
	var resp = await _send_request(Endpoints.ENTITY_GET % uuid)
	if resp == null:
		return null
	return LittleDoodlesEntity.from_request_body(resp["entity"])


## Returns a list of Entity instances matching the given search parameters
## which should be given as a URI-encoded String of GET parameters. Supports
## most Django filter kwarg expressions.
func search_entities(search_params: String):
	var resp = await _send_request(Endpoints.ENTITY_SEARCH % search_params)
	if resp == null:
		return null

	var entities = []
	for entitydef in resp["entities"]:
		entities.append(LittleDoodlesEntity.from_request_body(entitydef))
	return entities


func _send_request(endpoint, method = HTTPClient.METHOD_GET, body: String = ""):
	var headers = PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	if _cookiejar:
		headers.append("Cookie: %s" % "; ".join(_cookiejar))

	request(api_url.path_join(endpoint), headers, method, body)

	var response = await request_completed
	if response[0] != 0:
		push_error("Request Error Occurred: %s" % response[0])
		return null
	
	# Handle cookie headers
	for header in response[2]:
		if header.to_lower().begins_with("set-cookie"):
			_cookiejar.append(header.split(":", true, 1)[1].strip_edges().split("; ")[0])

	if response[1] != 200:
		push_error("Non-OK Response Code Received: %s" % response[1])
		return null

	var resp_body_str = response[3].get_string_from_utf8()
	var resp_body = null
	if resp_body_str != null && not resp_body_str.is_empty():
		resp_body = JSON.parse_string(resp_body_str)

	if resp_body != null and resp_body.get("result", "") == "failure":
		push_error(JSON.stringify(resp_body["errors"]))
		return null

	return resp_body
