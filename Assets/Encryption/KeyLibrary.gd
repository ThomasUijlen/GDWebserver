extends Node

var keyLib : Dictionary = {}
var mutex : Mutex = Mutex.new()

func addKey(publicKey : String, privateKey : String):
	if publicKey.length() < 16:
		print("Invalid public key")
		return
	if privateKey.length() < 16:
		print("Invalid private key")
		return
	
	var key : KeyPair = KeyPair.new()
	key.publicKey = publicKey
	key.privateKey = privateKey
	
	mutex.lock()
	keyLib[publicKey] = key
	mutex.unlock()

func getKey(publicKey : String) -> KeyPair:
	var key = null
	mutex.lock()
	if keyLib.has(publicKey): key = keyLib[publicKey]
	mutex.unlock()
	return key

class KeyPair:
	var publicKey : String
	var privateKey : String
