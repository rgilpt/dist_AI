class_name FSMIdle
extends Node

@export var actor: CharacterBody2D = null
var name_state = "Idle"

func action_state():
	actor.velocity = Vector2()
