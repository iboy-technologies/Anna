#this is for learning mode in case of a new [prompt]


#use await in custom or engine scripts to wait for user input or confirmation
#before asking for user input check for highly weighted suggestions
extends Node






#
#check if command or conversation
func process(what:String):
	var query = "Im not sure what you're refering to."
	var token = Layer3.tokenise(query)
	var predictions = Layer3.process_predictions(token)

	#predictions = ("command, something i should know about")
	#output = query + predictions processed
































	pass
