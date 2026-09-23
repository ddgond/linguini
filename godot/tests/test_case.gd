extends RefCounted
## Minimal test base: methods named test_* are run by run_tests.gd.

var tree: SceneTree
var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## Adds a node under the root for the duration of a test.
func add(node: Node) -> Node:
	tree.root.add_child(node)
	return node
