@tool
extends EditorPlugin

## Pirate Dev Tools — organizational home for editor-only authoring scenes.
##
## Unlike addons that register dock panels or inspector plugins, this addon
## is a *container* for standalone .tscn files the developer runs directly
## via F6. Each tool lives as a runnable scene + script + .uid triplet at
## the root of this folder:
##
##   - dash_fire_test.tscn          — dash flame shader tuning sandbox
##   - explosion_test.tscn          — bakes explosion atlases to
##                                    features/vfx/textures/explosions/
##   - stylized_flame_test.tscn     — stylized flame material tuning +
##                                    save-to-dash_flame_material.tres
##
## Why an EditorPlugin shell instead of a plain subfolder: enabling the
## plugin via project.godot [editor_plugins] makes the addon visible in
## the editor's Project Settings → Plugins panel, and more importantly
## lets export_presets.cfg's exclude_filter strip `addons/pirate_dev_tools/*`
## from release builds without needing a separate dev/ exclude rule.
##
## No _enter_tree / _exit_tree work is needed — this plugin doesn't add
## dock controls or inspector plugins. It exists to mark the folder as
## a recognized addon.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
