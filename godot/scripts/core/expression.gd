## How someone's face reacts in a conversation.
##
## Faces respond to the conversation (being pressed, a sore subject, their own money troubles, gossip) and to
## the person's manner (`demeanour`, and the nervous/smooth `style` the dialogue already shows) - never to
## whether they did it or are lying. An honest person with something to protect may look uneasy; a calm liar
## stays calm. Every reaction has a strength; higher difficulties show only the stronger ones, and only an
## Absolute Beginner is told in words what a face shows.
extends RefCounted

const Investigation = preload("res://scripts/core/investigation.gd")

## The face someone wears when nothing in particular is going on.
const AT_REST := {"cheerful": "content", "easygoing": "content", "brisk": "neutral", "reserved": "neutral",
		"gruff": "neutral"}
## The weakest reaction each difficulty shows (0 shows everything).
const SHOWN_FROM := {"beginner": 0, "hobby": 1, "experienced": 2}
const WORDS := {"happy": "looks pleased", "content": "seems at ease", "tired": "looks tired", "worried": "looks worried",
		"uneasy": "looks uneasy", "guarded": "gives nothing away", "irritated": "looks irritated",
		"neutral": "looks calm"}


static func at_rest(resident: Dictionary) -> String:
	if resident.get("condition", "") == "injured":
		return "tired"
	return AT_REST.get(String(resident.get("demeanour", "easygoing")), "neutral")


static func react(resident: Dictionary, style: String, topic: String, res: Dictionary) -> Array:
	## [expression, strength 0..3] for an answer just given.
	var dem := String(resident.get("demeanour", "easygoing"))
	var rest := at_rest(resident)
	var lines := PackedStringArray()
	for line in res.get("lines", []):
		lines.append(String(line["text"]))
	var said := "\n".join(lines)
	if said.contains(Investigation.WORN_OUT) or said.contains("You've already pushed them"):
		return ["irritated", 3]
	if res.get("pressed", false):
		if style == "nervous":
			return ["uneasy", 3]
		return ["irritated" if dem == "gruff" or dem == "brisk" else "guarded", 3]
	if said.contains(Investigation.EVASIVE["nervous"]) or said.contains(Investigation.HESITATE["nervous"]):
		return ["uneasy", 2]
	if said.contains(Investigation.EVASIVE["smooth"]):
		return ["guarded", 2]
	if topic == "money":
		if said.contains("I owe") or said.contains("I'm behind") or said.contains("I couldn't make the rent") \
				or said.contains("They said no"):
			return ["worried", 1]
		if said.contains("owe me") or said.contains("owes me") or said.contains("come to me for money"):
			return ["irritated" if dem == "gruff" else "tired", 1]
	if topic == "conflicts" and (said.contains("I had it out") or said.contains("never got on")
			or said.contains("came at me") or said.contains("attacked me")):
		return ["irritated", 2]
	if topic == "incident" and not said.contains(Investigation.NO_KNOWLEDGE):
		return ["worried" if dem == "cheerful" or dem == "easygoing" else "guarded", 1]
	if topic == "rumors" and dem == "cheerful" and not said.contains(Investigation.NO_KNOWLEDGE):
		return ["happy", 1]
	if topic.begins_with("person:") and dem == "cheerful":
		return ["content", 0]
	return [rest, 0]


static func shown(resident: Dictionary, reaction: Array, mode: String) -> String:
	## What the player actually sees: weak reactions fade back to the face at rest on harder difficulties.
	if int(reaction[1]) >= int(SHOWN_FROM.get(mode, 0)):
		return String(reaction[0])
	return at_rest(resident)


static func caption(resident: Dictionary, expression: String, mode: String) -> String:
	## Only an Absolute Beginner is told in words; everyone else reads the face.
	if mode != "beginner" or expression == at_rest(resident):
		return ""
	return "%s %s." % [String(resident.get("first", "")), WORDS.get(expression, "looks thoughtful")]
