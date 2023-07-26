extends Node
class_name ThreadPool

var THREAD_COUNT = 10

var threadPool : Array = []
var functionQueue : ConcurrentQueue = ConcurrentQueue.new()
var poolActive = true

func _ready():
	for i in range(THREAD_COUNT):
		threadPool.append(PoolThread.new())
		var poolThread : PoolThread = threadPool[i]
		poolThread.pool = self
		var threadI = i
		poolThread.thread.start(Callable(self,"ThreadFunction").bind(i),Thread.PRIORITY_NORMAL)

func _process(delta):
	if functionQueue.size() == 0:
		return
	for i in range(threadPool.size()):
		if functionQueue.size() == 0:
			break
		var poolThread = threadPool[i]
		
		if !poolThread.thread.is_alive():
			poolThread.thread.wait_to_finish()
			poolThread.active = false
			var threadI = i
			poolThread.thread.start(Callable(self,"ThreadFunction").bind(threadI),Thread.PRIORITY_NORMAL)
		if !poolThread.active:
			var functionRequest: FunctionRequest = functionQueue.dequeue()
			if functionRequest:
				poolThread.callFunction(functionRequest)

func ThreadFree() -> bool:
	return GetFreeThreads() > functionQueue.size()

func GetFreeThreads() -> int:
	var freeThreads = 0
	for i in range(threadPool.size()):
		if !threadPool[i].active:
			freeThreads += 1
	freeThreads -= functionQueue.size()
	return freeThreads

func ThreadsActive() -> bool:
	for i in range(threadPool.size()):
		if threadPool[i].active:
			return true
	return false

func requestFunctionCall(node: Object, functionName: String, parameters = null) -> FunctionRequest:
	var functionRequest = FunctionRequest.new(node, functionName, parameters)
	functionRequest.pool = self
	functionQueue.enqueue(functionRequest)
	return functionRequest

func ThreadFunction(i: int) -> void:
	var poolThread : PoolThread = threadPool[i]
	
	while poolActive:
		poolThread.semaphore.wait()
		if not poolActive:
			return
		if poolThread.functionRequest.node != null and is_instance_valid(poolThread.functionRequest.node):
			if poolThread.functionRequest.parameters != null:
				poolThread.functionRequest.node.callv(
					poolThread.functionRequest.functionName,
					poolThread.functionRequest.parameters)
			else:
				poolThread.functionRequest.node.call(
					poolThread.functionRequest.functionName)
			
		poolThread.call_deferred("functionFinished")

func _exit_tree():
	poolActive = false
	for i in range(threadPool.size()):
		var poolThread = threadPool[i]
		poolThread.semaphore.post()
		poolThread.thread.wait_to_finish()

class PoolThread extends Resource:
	var pool: ThreadPool
	var thread: Thread
	var semaphore: Semaphore
	var active = false
	var functionRequest: FunctionRequest

	func _init():
		thread = Thread.new()
		semaphore = Semaphore.new()

	func callFunction(function_request: FunctionRequest) -> void:
		self.functionRequest = function_request
		function_request.processed = true
		active = true
		semaphore.post()

	func functionFinished() -> void:
		active = false
		functionRequest = null

class FunctionRequest:
	var node: Object
	var functionName: String
	var parameters
	var processed: bool = false
	var pool: ThreadPool
	
	func _init(node: Object,functionName: String,parameters = null):
		self.node = node
		self.functionName = functionName
		self.parameters = parameters
