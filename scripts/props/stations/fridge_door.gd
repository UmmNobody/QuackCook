extends AnimatableBody3D

func interact_with(held_item: Node, player_head: Node) -> bool:
	return get_parent().interact_with(held_item, player_head)
