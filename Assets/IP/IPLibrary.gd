extends Node

var loadBalancers : Array = []
var gameServers : Array = []
var storageServers : Array = []
var oldServers : Array = []

func _ready():
	Firebase.getServers()

var serverTimer : float = 20
func _process(delta):
	serverTimer -= delta
	if serverTimer <= 0.0:
		serverTimer = 600
		Firebase.getServers()

func clearServers():
	oldServers.clear()
	loadBalancers.clear()
	gameServers.clear()
	storageServers.clear()

func addServer(data):
	var ip : String = data["IP"]["stringValue"]
	var type : String = data["Type"]["stringValue"]
	
	match type:
		"LoadBalancer":
			if !loadBalancers.has(ip): loadBalancers.append(ip)
		"GameServer":
			if !gameServers.has(ip): gameServers.append(ip)
		"StorageServer":
			if !storageServers.has(ip): storageServers.append(ip)
