class_name CardData
extends Resource

enum CardType {TACTIC, MOVEMENT, SUPPORT}

enum EffectType {
	END_TURN_WITHOUT_ROLL,
	ADDITIONAL_ROLL,
	MOVE_TO_NEAREST_HOSPITAL,
}

@export var card_id: StringName
@export var display_name := "Card"
@export_multiline var description := ""
@export var type: CardType = CardType.TACTIC
@export var effect: EffectType = EffectType.END_TURN_WITHOUT_ROLL
@export_group("Presentation")
@export var color := Color(0.0, 0.0, 0.0, 0.0)


## Authored colours are preferred, but older/new prototype cards still receive
## a stable distinct colour derived from their persistent ID.
func get_display_color() -> Color:
	if color.a > 0.0:
		return color
	var stable_hash := absi(hash(String(card_id)))
	var hue := float(stable_hash % 360) / 360.0
	return Color.from_hsv(hue, 0.52, 0.72, 1.0)
