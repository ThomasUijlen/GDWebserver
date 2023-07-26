extends Resource
class_name ConcurrentQueue

var queue := []
var mutex := Mutex.new()

func enqueue(item):
	mutex.lock()
	queue.append(item)
	mutex.unlock()

func dequeue():
	var item = null
	mutex.lock()
	if queue.size() > 0:
		item = queue[0]
		queue.remove_at(0)
	mutex.unlock()
	return item

func clear():
	mutex.lock()
	queue.clear()
	mutex.unlock()

func size() -> int:
	var count = 0
	mutex.lock()
	count = queue.size()
	mutex.unlock()
	return count

func getQueue() -> Array:
	var queue : Array = []
	mutex.lock()
	queue = self.queue.duplicate()
	mutex.unlock()
	return queue
