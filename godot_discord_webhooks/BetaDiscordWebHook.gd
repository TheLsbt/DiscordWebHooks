extends RefCounted
class_name BetaDiscordWebHook

## A discord webhook is not a node and does not need to be added to the scene tree

enum MESSAGE_FLAGS {
	SUPPRESS_EMBEDS = 1 << 2, ## Do not include any embeds when serializing this message
	SUPRESS_NOTIFICATIONS = 1 << 12, ## This message will not trigger push and desktop notifications
	}

const HEADERS: PackedStringArray = ["Accept: application/json", "Content-Type: multipart/form-data; boundary=\"BodyBoundaryHere\""]
const PORT := 443
const API_HOST := "https://discord.com"

const WebHookEmbed = preload("./DiscordWebHookEmbed.gd")

var client: HTTPClient
var webhook_url: String = ""
var data: Dictionary = {}
var files: Array = []

## Returned by [method DiscordWebHook.post] and [method DiscordWebHook.edit]
class Response:
	var _parsed := false
	var code: int = -1
	var headers: Dictionary = {}
	var body: PackedByteArray = []
	var error = null

	# Determine if this response was chunked
	var chunked := false

	var channel_id := ""
	var message_id := ""
	var message_content := ""
	var message_embeds: Array = []
	var message_tts := false
	var message_flags := 0
	var message_poll: Dictionary = {}


	func text() -> String:
		return body.get_string_from_utf8()


	func parse() -> void:
		var data = JSON.parse_string(text())
		if typeof(data) != TYPE_DICTIONARY:
			print(data)
			return

		data = (data as Dictionary)
		channel_id = data.get("channel_id", "")
		message_id = data.get("id", "")
		message_content = data.get("content", "")
		message_embeds = data.get("embeds", [])
		message_tts = data.get("tts", false)
		message_flags = data.get("flags", 0)
		#message_poll = data.get("poll", )
		_parsed = true

func _init(url: String) -> void:
	client = HTTPClient.new()
	webhook_url = url

	_connect_to_discord()


func _connect_to_discord() -> void:
	 # Connect to host/port.
	if client.connect_to_host(API_HOST, PORT) != OK:
		printerr("Failed to connect to %s, try again using [connect_to_discord]" %API_HOST)
		return

	# Wait until resolved and connected.
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()

	if client.get_status() == HTTPClient.STATUS_CONNECTED:
		print("Connected to 'https://discord.com'")
	else:
		printerr("Could not connect to 'https://discord.com'")


# Helper function
func len_limit_string(string: String, length: int) -> String:
	return string.left(length)


#region Message

## Supports hyperlink
func message(content: String) -> BetaDiscordWebHook:
	data["content"] = content
	return self


func add_file(path: String) -> BetaDiscordWebHook:
	files.append(path)
	return self


## Chain-able
func username(username: String) -> BetaDiscordWebHook:
	data["username"] = username
	return self


## Chain-able
func profile_picture(url: String) -> BetaDiscordWebHook:
	data["avatar_url"] = url
	return self


## Chain-able
func tts(tts: bool) -> BetaDiscordWebHook:
	data["tts"] = tts
	return self


## use [enum MESSAGE_FLAGS]
## combine flags by using '^'[br]eg.
## [codeblock]MESSAGE_FLAGS.SUPRESS_EMBEDS ^ MESSAGE_FLAGS.SUPRESS_NOTIFICATIONS[/codeblock]
func flags(flag: int) -> BetaDiscordWebHook:
	data["flags"] = flag
	return self


## Creates an embed and returns it[br]
## Not chainable
func add_embed() -> WebHookEmbed:
	if not data.has("embeds"):
		data["embeds"] = []

	var embed := WebHookEmbed.new()

	if data["embeds"].size() >= 10:
		printerr("There are currently 10 embeds which are the maximum amount for a message")
		return embed

	data["embeds"].append(embed)

	return embed


# Not chain-able
func get_embed(at: int) -> WebHookEmbed:
	if not data.has("embeds") and at <= 10:
		return null

	if data["embeds"].size()  <= at + 1:
		return data["embeds"][at]

	return null


## Creates a poll using [param question] (300 character limit) and a list of [param awnsers]
## (Each awnser has a character limit of 55). The poll lasts for [param duration] hours. [br]
## To add emojis to questions make sure that the corosponding [param emojis] index has the right
## 'id' to [param awnsers] index. A message can only ever have one poll so when this method is
## called again it overrides the previous one
func add_poll(question: String, awnsers: PackedStringArray, duration: int, multiselect: bool = false, emojis: PackedStringArray = []) -> BetaDiscordWebHook:
	var awnsers_array: Array = []
	for idx: int in awnsers.size():
		var awnser_text: String = awnsers[idx]
		var awnser: Dictionary = {
			"awnser_id": idx + 1,
			"poll_media": {
				"text": len_limit_string(awnser_text, 55),
			},
		}
		if emojis.size() >= (idx + 1):
			var emoji: String = emojis[idx]
			# If the emoji begins with : and ends with :
			if emoji.begins_with(":") and emoji.ends_with(":"):
				awnser["poll_media"]["emoji"] = {}
				awnser["poll_media"]["emoji"]["name"] = emoji.lstrip(":").rstrip(":")
				print(awnser)
			# If an emoji is an int then the user wants to add a custom emoji
			elif emoji.is_valid_int():
				awnser["poll_media"]["emoji"] = {}
				awnser["poll_media"]["emoji"]["id"] = emoji

		awnsers_array.append(awnser)

	data["poll"] = {
		"answers": awnsers_array,
		"question": {"text": len_limit_string(question, 300)},
		"duration": duration,
		"allow_multiselect": multiselect
	}
	return self


#endregion


func get_parsed_data() -> String:
	return """
--BodyBoundaryHere
Content-Disposition: form-data; name=payload_json"
Content-Type: application/json

{
  "content": "Hello, World!",
  "embeds": [{
	"title": "Hello, Embed!",
	"description": "This is an embedded message.",
	"thumbnail": {
	  "url": "attachment://myfilename.png"
	},
	"image": {
	  "url": "attachment://mygif.gif"
	}
  }],
  "attachments": [{
	  "id": 0,
	  "description": "Image of a cute little cat",
	  "filename": "myfilename.png"
  }]
}
--BodyBoundaryHere
Content-Disposition: form-data; name="files[0]"; filename="myfilename.png"
Content-Type: image/png

%s

--BodyBoundaryHere

""" %[FileAccess.get_file_as_bytes("res://godot_discord_webhooks/icon.png")]


func replace_using_response(response: Response) -> BetaDiscordWebHook:
	if not response._parsed:
		response.parse()
	data = {
		"content": response.message_content,
		"embeds": [],
		"tts": response.message_tts,
		"flags": response.message_flags
	}

	for embed_dict: Dictionary in response.message_embeds:
		var embed_object: WebHookEmbed = WebHookEmbed.new()
		embed_object.embed = embed_dict
		data.embeds.append(embed_object)

	return self


func thread(name: String, applied_tags: PackedStringArray = []) -> BetaDiscordWebHook:
	data["thread_name"] = name
	#data["applied_tags"] = applied_tags
	return self


func post() -> Response:
	var url = webhook_url + "?wait=true"
	var send_url = url

	# Create some random bytes to generate our boundary value
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	var boundary = 'GODOT%s' % random_bytes.hex_encode()

	# Setup the header Content-Type with our boundary
	var headers = ["Accept: application/json", "Content-Type: multipart/form-data;boundary=boundary"]

	#proceed with code from @mrcdk, mine has a few tweaks, such as getting rid of filename, and using /jpeg instead of /png, and just make sure you tweak your form-data names to match your APIS proper parameters.

	var body = PackedByteArray()
	#body.push_back('--{{boundary}}')
	#body.push_back('Content-Disposition: form-data; name=\"payload_json\"')
	#body.push_back('Content-Type: application/json')
	#body.push_back('')
	#body.push_back('{"content":"File: attachment://myfilename.png"}')
	body.append_array("\r\n--boundary\r\n".to_utf8_buffer())
	body.append_array('Content-Disposition: form-data; name="file0"; filename="myfilename.png"'.to_utf8_buffer())
	body.append_array('\r\nContent-Type: image/png\r\n\r\n'.to_utf8_buffer())
	body.append_array(''.to_utf8_buffer())
	body.append_array(Image.load_from_file("res://godot_discord_webhooks/icon.png").save_png_to_buffer())
	body.append_array("\r\n--boundary--".to_utf8_buffer())

	print(body.get_string_from_utf8())

	var method = HTTPClient.METHOD_POST
	var response = await _request(method, url, headers, body)
	response.parse()
	print("Posted %s" %response.message_id)
	return response


#func edit(message_id: String) -> Response:
	#var url = webhook_url + "/messages/" + message_id
	#var method = HTTPClient.METHOD_PATCH
	#print("Patched %s" %message_id)
	#var response = await _request(method, url, HEADERS, JSON.stringify(get_parsed_data()))
	#response.parse()
	#return response


## Returns true if deleting the message was sucessful
#func delete(message_id: String) -> bool:
	#var url = webhook_url + "/messages/" + message_id
	#var method = HTTPClient.METHOD_DELETE
	#print("Deleted %s" %message_id)
	#var response = await _request(method, url, HEADERS, JSON.stringify(get_parsed_data()))
#
	#if response.code == 204:
		#return true
	#return false


#func Get(message_id: String) -> Response:
	#var url = webhook_url + "/messages/" + message_id
	#var method = HTTPClient.METHOD_GET
	#print("Patched %s" %message_id)
	#var response = await _request(method, url, HEADERS, JSON.stringify(get_parsed_data()))
	#response.parse()
	#return response


# Ensure that the connection to the client is closed
func close_connection() -> void:
	if client: client.close()


func _request(method: HTTPClient.Method, url: String, headers: PackedStringArray, body: PackedByteArray) -> Response:
	var err = client.request_raw(method, url, headers, body)

	var response := Response.new()
	if err != OK:
		response.error = "There was an error trying to send your request >> %s" %error_string(err)
		return response

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		# Keep polling for as long as the request is being processed.
		client.poll()

	if not client.get_status() in [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]:
		printerr("Failed to post a message to discord")
		response.error = "There was an error trying to senf you request, local error"
		return response

	if not client.has_response():
		response.error = "The the client did not respond with a request, try again"
		return response

	response.headers = client.get_response_headers_as_dictionary()
	response.code = client.get_response_code()
	response.chunked = client.is_response_chunked()

	# Get the response body
	# Array that will hold the data.
	var chunks = PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		# While there is body left to be read
		client.poll()
		# Get a chunk.
		var chunk = client.read_response_body_chunk()
		if chunk.size() == 0:
			if not OS.has_feature("web"):
				# Got nothing, wait for buffers to fill a bit.
				OS.delay_usec(1000)
			else:
				await Engine.get_main_loop().process_frame
		else:
			# Append to read buffer.
			chunks.append_array(chunk)

	response.body = chunks
	return response


## A helper function, used to color embed objects. It converts the rgb components to hex
static func rgb_to_hex(color: Color) -> int:
	return PackedByteArray([
		roundi(color.r * 255.0),
		roundi(color.g * 255.0),
		roundi(color.b * 255.0)
	]).hex_encode().hex_to_int()
