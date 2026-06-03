extends CharacterBody2D
class_name NPC

## AI-controlled character with a two-layer control system.
##
## PRIMARY CONTROL  — _select_action() decides WHAT to do (runs every 0.5 s).
## SECONDARY CONTROL — _physics_process() executes the chosen action each frame.
##
## ── Student Task ──────────────────────────────────────────────────────────────
##  Make the AI smarter by improving _select_action().
##  The default version is intentionally simple — it always goes for the prize
##  and never fights or defends.  Add your own conditions to make it better!
## ─────────────────────────────────────────────────────────────────────────────

# ── Stats ──────────────────────────────────────────────────────
@export var speed: float = 250.0
## Alias expected by FSMPathFinding.
var max_speed: float:
	get: return speed

@export var team_id: int = -1

var npc_id: String = ""
var health: int = 100
var is_dead: bool = false
var carries_prize: bool = false
var ammo: int = 6
var _fire_cd: float = 0.0

## Set by NetworkManager immediately after spawning the NPC.
var home_position: Vector2 = Vector2.ZERO
## Back-reference to the NetworkManager; used when dropping the prize on death.
var network_manager: Node = null

# ── Child node references (must match NPC.tscn) ────────────────
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _body_poly: Polygon2D = $Body
@onready var _weapon_holder: Node2D = $WeaponHolder
@onready var _sight_area: Area2D = $SightArea
@onready var _health_label: Label = $HealthLabel
@onready var _collision: CollisionShape2D = $CollisionShape2D

const BULLET_SCENE = preload("res://Scenes/Weapon.tscn")

# ── Internal AI state ──────────────────────────────────────────
var _target_enemy: Node2D = null


# ══════════════════════════════════════════════════════════════
#  ACTIONS  (Primary Control)
#
#  Each value represents one behaviour the NPC can perform.
# ══════════════════════════════════════════════════════════════
enum Action {
	IDLE,          ## Stand still; do nothing.
	GET_PRIZE,     ## Walk to the chest and pick up the prize.
	RETURN_PRIZE,  ## Carry the prize back to the home base.
	FIGHT,         ## Chase and shoot the nearest visible enemy.
	DEFEND,        ## Guard the home base; shoot enemies that come close.
}

var current_action: Action = Action.IDLE
@onready var finite_state_machine: FiniteStateMachine = $AI/Secondary/FiniteStateMachine


func _ready() -> void:
	add_to_group("npc")
	add_to_group("player")   # bullets check the "player" group to deal damage

	if not multiplayer.is_server():
		set_physics_process(false)
		return

	_sight_area.body_entered.connect(_on_sight_body_entered)
	_sight_area.body_exited.connect(_on_sight_body_exited)

	# Decision tick: call _select_action every 0.5 seconds
	var tick := Timer.new()
	tick.wait_time = 0.5
	tick.autostart = true
	tick.timeout.connect(_select_action)
	add_child(tick)
	
	if finite_state_machine != null:
		finite_state_machine.is_on = true


# ══════════════════════════════════════════════════════════════
#  PRIMARY CONTROL  ← students improve this!
#
#  Called every 0.5 seconds to pick the NPC's current action.
#  Right now it is intentionally too simple:
#    • If carrying the prize → go home.
#    • Otherwise            → always try to get the prize
#                             (never fights, never defends).
#
#  Ideas for students:
#    • If _target_enemy != null → Action.FIGHT
#    • If the NPC belongs to the defending team → Action.DEFEND
#    • If a teammate is already carrying the prize → protect them
# ══════════════════════════════════════════════════════════════
func _select_action() -> void:
	if is_dead:
		return

	# Always return home if we have the prize
	if carries_prize:
		current_action = Action.RETURN_PRIZE
		return

	# TODO (students): make the AI smarter here!
	current_action = Action.GET_PRIZE   # too simple — never fights or defends


# ══════════════════════════════════════════════════════════════
#  SECONDARY CONTROL  ← executes the chosen action
# ══════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or is_dead:
		return

	_fire_cd -= delta

	#match current_action:
		#Action.IDLE:
			#velocity = Vector2.ZERO
		#Action.GET_PRIZE:
			#_do_get_prize()
		#Action.RETURN_PRIZE:
			#_do_return_prize()
		#Action.FIGHT:
			#_do_fight()
		#Action.DEFEND:
			#_do_defend()

	move_and_slide()

	# Broadcast transform to all clients
	_sync_transform.rpc(position, velocity,
		_weapon_holder.rotation if _weapon_holder else 0.0)


# ── Secondary: move toward the chest ──────────────────────────
func _do_get_prize() -> void:
	var chest := get_tree().get_first_node_in_group("chest")
	if is_instance_valid(chest):
		_move_toward(chest.global_position)
	else:
		velocity = Vector2.ZERO


# ── Secondary: carry the prize home ───────────────────────────
func _do_return_prize() -> void:
	_move_toward(home_position)


# ── Secondary: chase and shoot the nearest enemy ──────────────
func _do_fight() -> void:
	if not is_instance_valid(_target_enemy):
		current_action = Action.GET_PRIZE
		return
	var dist := global_position.distance_to(_target_enemy.global_position)
	if dist > 300.0:
		_move_toward(_target_enemy.global_position)
	else:
		velocity = Vector2.ZERO
		_aim_and_shoot(_target_enemy.global_position)


# ── Secondary: guard home base, shoot enemies in range ────────
func _do_defend() -> void:
	if global_position.distance_to(home_position) > 120.0:
		_move_toward(home_position)
	else:
		velocity = Vector2.ZERO
		if is_instance_valid(_target_enemy):
			_aim_and_shoot(_target_enemy.global_position)


# ── Helper: steer toward a world-space position ───────────────
func _move_toward(world_pos: Vector2) -> void:
	var dir := world_pos - global_position
	velocity = Vector2.ZERO if dir.length() < 20.0 else dir.normalized() * speed


# ── Helper: aim weapon and fire when cooldown allows ─────────
func _aim_and_shoot(world_pos: Vector2) -> void:
	if _weapon_holder:
		_weapon_holder.look_at(world_pos)
	if _fire_cd <= 0.0 and ammo > 0:
		_fire_at(world_pos)


func _fire_at(world_pos: Vector2) -> void:
	ammo -= 1
	_fire_cd = 0.65
	var dir := (world_pos - global_position).normalized()
	var bullet: Node2D = BULLET_SCENE.instantiate()
	bullet.global_position = global_position + dir * 36.0
	bullet.direction = dir
	bullet.rotation = dir.angle()
	bullet.shooter_team = team_id
	get_tree().root.add_child(bullet)


# ══════════════════════════════════════════════════════════════
#  DAMAGE & DEATH
# ══════════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	health -= amount
	health = max(health, 0)
	_rpc_sync_health.rpc(health)
	if health <= 0:
		_die()


func _die() -> void:
	is_dead = true
	# If the NPC was carrying the prize, drop it back to the chest
	if carries_prize and network_manager != null:
		network_manager.on_prize_dropped(global_position)
	_rpc_on_die.rpc()
	get_tree().create_timer(4.0).timeout.connect(_respawn)


@rpc("authority", "call_local", "reliable")
func _rpc_on_die() -> void:
	carries_prize = false
	hide()
	_collision.set_deferred("disabled", true)


func _respawn() -> void:
	if not multiplayer.is_server():
		return
	health = 100
	ammo = 6
	is_dead = false
	var pos := home_position + Vector2(
		randf_range(-48.0, 48.0),
		randf_range(-48.0, 48.0))
	_rpc_respawn.rpc(pos)


@rpc("authority", "call_local", "reliable")
func _rpc_respawn(pos: Vector2) -> void:
	health = 100
	is_dead = false
	position = pos
	show()
	_collision.set_deferred("disabled", false)
	if _health_label:
		_health_label.text = "HP: 100"


# ══════════════════════════════════════════════════════════════
#  NETWORKING
# ══════════════════════════════════════════════════════════════
@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_transform(pos: Vector2, vel: Vector2, weapon_rot: float) -> void:
	position = pos
	velocity = vel
	if _weapon_holder:
		_weapon_holder.rotation = weapon_rot


@rpc("authority", "call_local", "reliable")
func _rpc_sync_health(new_health: int) -> void:
	health = new_health
	if _health_label:
		_health_label.text = "HP: " + str(health)
	# Flash red when hit
	if _body_poly:
		_body_poly.color = Color(1.0, 0.2, 0.2)
		await get_tree().create_timer(0.15).timeout
		_apply_team_color_to_poly(_body_poly.color)   # restore — colour set by team


## RPC: set or clear prize-carrying state (called by Chest and NetworkManager).
@rpc("authority", "call_local", "reliable")
func rpc_set_carries_prize(value: bool) -> void:
	carries_prize = value
	# Yellow tint while carrying the prize, team colour otherwise
	if _body_poly:
		_body_poly.color = Color(1.0, 0.85, 0.1) if value else _team_color


# ══════════════════════════════════════════════════════════════
#  ENEMY DETECTION  (SightArea signals)
# ══════════════════════════════════════════════════════════════
func _on_sight_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	var body_team = body.get("team_id")
	if body_team != null and body_team != team_id and body_team != -1:
		if not is_instance_valid(_target_enemy):
			_target_enemy = body as Node2D


func _on_sight_body_exited(body: Node) -> void:
	if body == _target_enemy:
		_target_enemy = null


# ══════════════════════════════════════════════════════════════
#  PRIZE PICKUP  (called by Chest when this NPC enters it)
# ══════════════════════════════════════════════════════════════
func pickup_prize() -> void:
	rpc_set_carries_prize.rpc(true)
	#current_action = Action.RETURN_PRIZE
	


# ══════════════════════════════════════════════════════════════
#  VISUALS
## Called by FSMPathFinding (via NavigationAgent2D.velocity_computed or directly).
## Applies the safe velocity from the navigation server and steps physics.
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


# ══════════════════════════════════════════════════════════════
var _team_color: Color = Color(0.5, 0.5, 1.0)


func apply_team_color(color: Color) -> void:
	_team_color = color
	_apply_team_color_to_poly(color)
	if _sprite and _sprite.texture:
		_sprite.modulate = color


func _apply_team_color_to_poly(color: Color) -> void:
	if _body_poly and not carries_prize:
		_body_poly.color = color
