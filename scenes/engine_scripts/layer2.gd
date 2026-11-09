#here ill keep track of tasks in the workflow eg doing smthg while waiting for sm other thing
#all variables kept track of

extends Node


var workflow:Dictionary = {}  #smth' lyk {"order food":[ask which food, determine from where, generate prompt, open site, execute prompt, return feedback, evaluate feedback, generate report n paterns, store, clean]}
var curr_task
var curr_step
var confirmation_wait:bool
var confirmation:String

var predictions:Array = []
var suggestions:Array = []






#
