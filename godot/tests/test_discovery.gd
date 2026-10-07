extends "res://tests/test_case.gd"
## HostDiscovery: the mDNS query and answers, and which address a host gets.


## An answer as Sunshine's responder sends it: PTR for the service, then SRV
## and A as additional records, with the service name compressed.
func _answer(instance: String, target: String, addresses: Array) -> PackedByteArray:
	var p := PackedByteArray([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 1 + addresses.size()])
	var service_at := p.size()
	p.append_array(HostDiscovery.encode_name(HostDiscovery.SERVICE)) # the PTR record's owner
	var instance_name := PackedByteArray([instance.length()])
	instance_name.append_array(instance.to_utf8_buffer())
	instance_name.append_array([0xC0, service_at]) # "<instance>." + pointer to the service
	p.append_array([0, 12, 0, 1, 0, 0, 0x11, 0x94, 0, instance_name.size()])
	var instance_at := p.size()
	p.append_array(instance_name)
	var srv := PackedByteArray([0, 0, 0, 0, 0xBA, 0x29]) # priority, weight, port 47989
	srv.append_array(HostDiscovery.encode_name(target))
	p.append_array([0xC0, instance_at, 0, 33, 0x80, 1, 0, 0, 0, 120, 0, srv.size()])
	p.append_array(srv)
	for address: String in addresses:
		p.append_array(HostDiscovery.encode_name(target))
		p.append_array([0, 1, 0x80, 1, 0, 0, 0, 120, 0, 4])
		for part in address.split("."):
			p.append(int(part))
	return p


func test_query_asks_for_the_service() -> void:
	var q := HostDiscovery.query()
	check(q[5] == 1, "one question")
	check(q.slice(12, 12 + 13).get_string_from_ascii().contains("_nvstream"), "asks for _nvstream._tcp")
	check(q[q.size() - 3] == 12, "a PTR question")
	check(q[q.size() - 2] == 0x80, "asks for a unicast answer")


func test_parses_a_sunshine_answer() -> void:
	var hosts := HostDiscovery.parse(_answer("Gaia", "gaia.local", ["10.0.0.218", "10.0.0.76"]))
	check(hosts.size() == 1, "one host, got %d" % hosts.size())
	if hosts.size() == 1:
		check(hosts[0].name == "Gaia", "named by its instance, keeping its capitals: " + hosts[0].name)
		check(Array(hosts[0].addresses) == ["10.0.0.218", "10.0.0.76"], "both addresses: %s" % [hosts[0].addresses])


func test_answer_without_addresses() -> void:
	var hosts := HostDiscovery.parse(_answer("Gaia", "gaia.local", []))
	check(hosts.size() == 1 and hosts[0].addresses.is_empty(), "the host, with no addresses (the sender's is used)")


func test_ignores_queries_and_junk() -> void:
	check(HostDiscovery.parse(HostDiscovery.query()).is_empty(), "a query isn't an answer")
	var truncated := _answer("Gaia", "gaia.local", ["10.0.0.218"])
	check(HostDiscovery.parse(truncated.slice(0, truncated.size() - 6)).is_empty(), "a cut-off answer gives nothing")
	var looped := PackedByteArray([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0xC0, 12])
	check(HostDiscovery.parse(looped).is_empty(), "a name pointing at itself gives nothing")


func test_best_address_prefers_our_network() -> void:
	var local := PackedStringArray(["10.0.0.211", "100.71.196.95"])
	check(HostDiscovery.best_address(PackedStringArray(["172.17.144.1", "10.0.0.218"]), local) == "10.0.0.218", "same /24 as us")
	check(HostDiscovery.best_address(PackedStringArray(["172.17.144.1", "192.168.1.5"]), PackedStringArray()) == "192.168.1.5", "else a LAN address")
	check(HostDiscovery.best_address(PackedStringArray(["172.17.144.1"]), PackedStringArray()) == "172.17.144.1", "else the first")


func test_hosts_merge_and_skip_our_own() -> void:
	var discovery := HostDiscovery.new()
	discovery._local = PackedStringArray(["10.0.0.211"])
	var seen := []
	discovery.found.connect(func(host: Dictionary) -> void: seen.append(host.duplicate()))
	discovery._add("gaia", PackedStringArray(["10.0.0.218"]))
	discovery._add("gaia", PackedStringArray(["10.0.0.218"]))
	discovery._add("gaia", PackedStringArray(["10.0.0.76"]))
	discovery._add("Voyager", PackedStringArray(["172.17.144.1", "10.0.0.211"]))
	check(seen.size() == 2, "found again only for a new address, got %d" % seen.size())
	check(discovery.hosts.size() == 1 and discovery.hosts.has("gaia"), "this machine's own host left out")
	check(discovery.hosts.gaia.address == "10.0.0.218", "keeps the address on our network")
	discovery.free()
