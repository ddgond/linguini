class_name HostDiscovery
extends Node
## Finds Sunshine and GeForce Experience hosts on the local network. They
## announce `_nvstream._tcp` over multicast DNS, so while `active` this asks
## for it every few seconds from each IPv4 interface and reads the answers,
## which come straight back to the asking socket (a "legacy unicast" query, so
## port 5353 is never needed; the OS's own mDNS responder may hold it). Plain
## UDP, so it works the same on every platform without Avahi or Bonjour.

## A host answered, or answered from somewhere new: `host` is {name, address,
## addresses}, `address` being the one to connect to (best_address). This
## machine's own host, if it runs one, is left out.
signal found(host: Dictionary)

const SERVICE := "_nvstream._tcp.local"
const GROUP := "224.0.0.251"
const PORT := 5353
## Seconds between queries: quick at first, then settling down.
const INTERVALS := [0.0, 1.0, 2.0, 4.0, 8.0]

const _TYPE_A := 1
const _TYPE_PTR := 12
const _TYPE_SRV := 33

## Ask while true; the monitor's host page turns this on.
var active := false:
	set(value):
		if value == active:
			return
		active = value
		if active:
			_open()
		else:
			_close()

## Every host found so far, by name: {name, address, addresses}.
var hosts := {}

var _sockets: Array[PacketPeerUDP] = []
var _local: PackedStringArray = []
var _queries := 0
var _next_query := 0.0


func _exit_tree() -> void:
	_close()


func _process(delta: float) -> void:
	if not active:
		return
	_next_query -= delta
	if _next_query <= 0.0:
		_query()
	for socket in _sockets:
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			var source := socket.get_packet_ip()
			for answer: Dictionary in parse(packet):
				_add(answer.name, answer.addresses if not answer.addresses.is_empty() else PackedStringArray([source]))


func _add(name: String, addresses: PackedStringArray) -> void:
	var host: Dictionary = hosts.get(name, {"name": name, "address": "", "addresses": PackedStringArray()})
	var known: PackedStringArray = host.addresses
	var changed := false
	for address in addresses:
		if address == "":
			continue
		if _local.has(address):
			return # our own host: streaming from yourself isn't much use
		if not known.has(address):
			known.append(address)
			changed = true
	if not changed:
		return
	host.addresses = known
	host.address = best_address(known, _local)
	hosts[name] = host
	found.emit(host)


## The address to reach a host at: one on the same /24 as one of ours if
## there is one (a VPN or virtual adapter's address may not route), else a
## private LAN address, else the first.
static func best_address(addresses: PackedStringArray, local: PackedStringArray) -> String:
	for address in addresses:
		for mine in local:
			if address.left(address.rfind(".")) == mine.left(mine.rfind(".")):
				return address
	for address in addresses:
		if address.begins_with("10.") or address.begins_with("192.168."):
			return address
	return addresses[0] if not addresses.is_empty() else ""


func _open() -> void:
	_close()
	_local.clear()
	for iface: Dictionary in IP.get_local_interfaces():
		for address: String in iface.addresses:
			if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
				_local.append(address)
	# One socket per interface address, so the query goes out on each network.
	for address in (_local if not _local.is_empty() else PackedStringArray(["*"])):
		var socket := PacketPeerUDP.new()
		if socket.bind(0, address) != OK:
			continue
		socket.set_dest_address(GROUP, PORT)
		_sockets.append(socket)
	_queries = 0
	_next_query = 0.0


func _close() -> void:
	for socket in _sockets:
		socket.close()
	_sockets.clear()


func _query() -> void:
	var packet := query()
	for socket in _sockets:
		socket.put_packet(packet)
	_queries += 1
	_next_query = INTERVALS[mini(_queries, INTERVALS.size() - 1)]


# --- DNS messages ---

## A query for the service's instances, asking for a unicast answer.
static func query() -> PackedByteArray:
	var out := PackedByteArray([0x4C, 0x47, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	out.append_array(encode_name(SERVICE))
	out.append_array([0, _TYPE_PTR, 0x80, 1]) # PTR, IN with the unicast-response bit
	return out


static func encode_name(name: String) -> PackedByteArray:
	var out := PackedByteArray()
	for label in name.split(".", false):
		var bytes := label.to_utf8_buffer()
		out.append(bytes.size())
		out.append_array(bytes)
	out.append(0)
	return out


## The hosts in an mDNS answer: [{name, addresses}], with no addresses when
## the answer has no A record for the host. Malformed packets give [].
static func parse(packet: PackedByteArray) -> Array:
	if packet.size() < 12 or (packet[2] & 0x80) == 0: # not a response
		return []
	var questions := _u16(packet, 4)
	var records := _u16(packet, 6) + _u16(packet, 8) + _u16(packet, 10)
	var at := 12
	for i in questions:
		var q := _read_name(packet, at)
		if q.is_empty():
			return []
		at = q.next + 4
	var instances := {} # instance, lower case -> as sent (in order)
	var targets := {} # instance -> SRV target host name
	var ipv4 := {} # host name -> its addresses
	var service := SERVICE.to_lower()
	for i in records:
		var r := _read_name(packet, at)
		if r.is_empty() or r.next + 10 > packet.size():
			return []
		var type := _u16(packet, r.next)
		var length := _u16(packet, r.next + 8)
		var data: int = r.next + 10
		if data + length > packet.size():
			return []
		var owner: String = r.name.to_lower()
		if type == _TYPE_PTR and owner == service:
			var target := _read_name(packet, data)
			if not target.is_empty() and not instances.has(target.name.to_lower()):
				instances[target.name.to_lower()] = target.name
		elif type == _TYPE_SRV and owner.ends_with("." + service) and length > 6:
			var target := _read_name(packet, data + 6)
			if not target.is_empty():
				targets[owner] = target.name.to_lower()
				if not instances.has(owner):
					instances[owner] = r.name
		elif type == _TYPE_A and length == 4:
			var list: PackedStringArray = ipv4.get(owner, PackedStringArray()) # a copy: put it back
			list.append("%d.%d.%d.%d" % [packet[data], packet[data + 1], packet[data + 2], packet[data + 3]])
			ipv4[owner] = list
		at = data + length
	var out := []
	for instance: String in instances:
		var sent: String = instances[instance]
		var name := sent.left(sent.length() - service.length() - 1) # the instance's own label
		out.append({"name": name, "addresses": ipv4.get(targets.get(instance, ""), PackedStringArray())})
	return out


static func _u16(packet: PackedByteArray, at: int) -> int:
	return (packet[at] << 8) | packet[at + 1]


## {name, next}: the name at `at` (following compression pointers) and where
## the bytes after it start; {} if it runs off the packet or loops.
static func _read_name(packet: PackedByteArray, at: int) -> Dictionary:
	var labels: PackedStringArray = []
	var next := -1
	var jumps := 0
	while true:
		if at >= packet.size():
			return {}
		var n := packet[at]
		if n == 0:
			at += 1
			break
		if (n & 0xC0) == 0xC0:
			if at + 1 >= packet.size() or jumps > 16:
				return {}
			if next < 0:
				next = at + 2
			at = ((n & 0x3F) << 8) | packet[at + 1]
			jumps += 1
			continue
		if at + 1 + n > packet.size():
			return {}
		labels.append(packet.slice(at + 1, at + 1 + n).get_string_from_utf8())
		at += 1 + n
	return {"name": ".".join(labels), "next": next if next >= 0 else at}
