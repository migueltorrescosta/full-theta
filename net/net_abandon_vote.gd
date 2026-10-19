class_name NetAbandonVote
extends RefCounted
## The abandon vote of one paused ship (FT-NET-041, D128): each remaining connected
## crew player may cast or withdraw a vote; the ship is abandoned when the votes exceed
## half of that ship's remaining connected crew (2 of 2 in the 3-player case). Votes
## clear when the pause ends (the caller drops this object). Pure.

## Session id -> voter name.
var voters: Dictionary[int, String] = {}


## Casts (vote true) or withdraws (false) a session's vote.
func cast(session: int, voter_name: String, vote: bool) -> void:
	if vote:
		voters[session] = voter_name
	else:
		voters.erase(session)


## Keeps only the votes of the given sessions (the remaining connected crew).
func keep_only(sessions: Array[int]) -> void:
	for id: int in voters.keys():
		if not sessions.has(id):
			voters.erase(id)


## Votes needed with n remaining connected crew: more than half.
static func needed(n: int) -> int:
	return n / 2 + 1


func passes(n: int) -> bool:
	return n > 0 and voters.size() >= needed(n)


## Voter names, sorted (the abandon_votes event).
func names() -> Array[String]:
	var out: Array[String] = []
	out.assign(voters.values())
	out.sort()
	return out
