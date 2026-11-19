extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var report := {"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"models":[],"attachment_api":{}}
	report.mesh2d_methods = ClassDB.class_get_method_list("SpineMesh2D",true)
	report.mesh2d_properties = ClassDB.class_get_property_list("SpineMesh2D",true)
	report.spine_classes = []
	for name: String in ClassDB.get_class_list():
		if name.begins_with("Spine"): report.spine_classes.append(name)
	for class_name_value: String in ["SpineMeshAttachment","SpineRegionAttachment","SpineVertexAttachment","SpineSlot","SpineSkeleton","SpineMesh"]:
		if not ClassDB.class_exists(class_name_value): continue
		var methods: Array = []
		for method: Dictionary in ClassDB.class_get_method_list(class_name_value,true):
			var name := str(method.name)
			if name.contains("vertices") or name.contains("triang") or name.contains("uv") or name.contains("attachment") or name.contains("draw") or name.contains("region") or name.contains("mesh"):
				methods.append({"name":name,"args":method.args,"return":method.get("return",{})})
		report.attachment_api[class_name_value] = methods
	for id: String in ["d69_097","d69_147","d69_094"]:
		var actor := Actor.new()
		root.add_child(actor)
		actor.configure(id,1)
		actor.set_process(false)
		var model := {"id":id,"native":actor.using_spine(),"children":[],"signals":[]}
		if actor.using_spine():
			var sprite := actor.spine_sprite()
			for signal_spec: Dictionary in sprite.get_signal_list():
				if str(signal_spec.name).contains("skeleton") or str(signal_spec.name).contains("transform"): model.signals.append(signal_spec.name)
			model.child_count = sprite.get_child_count()
			var child_count := 0
			for child: Node in sprite.get_children():
				if child_count >= 2: break
				child_count += 1
				var item := {"class":child.get_class(),"name":child.name,"mesh_surfaces":[]}
				item.properties = child.get_property_list().filter(func(property: Dictionary) -> bool: return str(property.name).contains("mesh") or str(property.name).contains("texture") or str(property.name).contains("material") or str(property.name).contains("vert"))
				if child.has_method("get_mesh"):
					var mesh: Mesh = child.call("get_mesh")
					if mesh != null:
						for surface in mesh.get_surface_count():
							var arrays := mesh.surface_get_arrays(surface)
							var lengths: Array = []
							for array: Variant in arrays: lengths.append(array.size() if array != null else 0)
							item.mesh_surfaces.append({"array_lengths":lengths,"mesh_class":mesh.get_class(),"primitive":mesh.call("surface_get_primitive_type",surface) if mesh.has_method("surface_get_primitive_type") else -1})
				model.children.append(item)
		report.models.append(model)
		actor.queue_free()
		await process_frame
	var folder := "res://reports/performance_0.1.3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder+"/mesh_api.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SPINE_MESH_API_COMPLETE ",JSON.stringify(report))
	quit()
