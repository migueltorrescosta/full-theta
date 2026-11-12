var session: ServerSession

func _ready():
	spawn_enemy("raider")  # the scenario map
	var x = my_team_of_x
	cycle_target()
