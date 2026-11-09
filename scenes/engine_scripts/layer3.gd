#data processor comparator and evaluator
#eg checking question and answer to know if answer is affirmative or negative relative to question
#also watever method calls this shud provide type of comparion ie  q&a yes/no answer, like dislike etc

extends Node

var common_words:Array = ["the", "a", "an", "on", "in"]


func process_predictions(for_what:String):

	pass



func tokenise(text:String):
	#target is to identify subject target time etc
	var parts = text.split(" ")
	var id = -1
	var subjects = []
	#subject
	for word in parts:
		id += 1
		if word == "the":
			subjects.append(parts[id+1])

	#remove common words








	pass
