# Cria um MultiplayerSynchronizer por código, com dono (autoridade) definido.
extends RefCounted


static func add_sync(owner: Node, sync_name: String, authority: int, properties: Array) -> MultiplayerSynchronizer:
	var sync := MultiplayerSynchronizer.new()
	sync.name = sync_name
	var config := SceneReplicationConfig.new()
	for property in properties:
		config.add_property(NodePath(property))
	sync.replication_config = config
	sync.set_multiplayer_authority(authority)
	owner.add_child(sync)
	return sync
