class_name NetVote
extends RefCounted
## A crew vote on one ship (D128, D178, M4-Q2): the abandon vote of a paused ship or a run
## (FT-NET-041, D241), the "Run again" vote and the relaunch vote of an eliminated ship. Each
## remaining connected crew player may cast or withdraw a vote, keyed by session id (two
## players may share a name); the vote passes when the votes reach more than half of the
## ship's connected crew (2 of 2 in the 3-player case). The caller drops the object when the
## vote ends. Pure.

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


## One session's cast or withdrawal among `members`: true when the vote passes now.
func cast_from(session: NetSession, vote: bool, members: Array[int]) -> bool:
	cast(session.id, session.name, vote)
	keep_only(members)
	return passes(members.size())


## Votes needed with n remaining connected crew: more than half.
static func needed(n: int) -> int:
	return n / 2 + 1


func passes(n: int) -> bool:
	return n > 0 and voters.size() >= needed(n)


## Voter names, sorted.
func names() -> Array[String]:
	var out: Array[String] = []
	out.assign(voters.values())
	out.sort()
	return out


## Voter session ids, sorted: a client checks its own vote by id, not by name.
func sessions() -> Array[int]:
	var out: Array[int] = []
	out.assign(voters.keys())
	out.sort()
	return out


## The event payload of the vote of `ship` among n connected crew: {ship, voters, sessions,
## needed} (abandon_votes, run_votes, relaunch_votes).
func payload(ship: int, n: int) -> Dictionary:
	return {"ship": ship, "voters": names(), "sessions": sessions(), "needed": needed(n)}
