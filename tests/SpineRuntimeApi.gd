extends SceneTree

func _initialize() -> void:
	for method: Dictionary in ClassDB.class_get_method_list("SpineAnimationStateTrack",true):
		if str(method.name).contains("time"): print("TRACK ",method.name)
	for name: String in ClassDB.class_get_integer_constant_list("SpineConstant"):
		print("CONST ",name," ",ClassDB.class_get_integer_constant("SpineConstant",name))
	for method: Dictionary in ClassDB.class_get_method_list("SpineSprite",true):
		print("METHOD ",method.name," ",method.args)
	for property: Dictionary in ClassDB.class_get_property_list("SpineSprite",true):
		print("PROPERTY ",property.name," ",property.type)
	quit()
