# Automatically reload an overlay module when it's modified.
# Made to help speed up iteration during development.
#
# This module does not build a dependency graph, modules are only automatically
# reloaded when they are modified, modifiying their dependencies currently does
# not trigger a reload.

use std/log

const TYPE = "overlay-auto"

def get_hooks []: [nothing -> list] {
	$env.config.hooks.pre_prompt
	| filter { try {$in.type == $TYPE}}
}

def find_hooks [module: path]: [nothing -> list] {
	get_hooks | where module == $module
}

def module_to_path [module: path, --span: record<start: int, end: int>]: [nothing -> path] {
	match ($module | path type) {
		"file" => {$module},
		"dir" => {$module | path join mod.nu},
		_ if $span == null => { error make -u { msg: $"Module `($module)` not found." } },
		_ => { error make {
			msg: "Module not found."
			label: {
				text: "module not found"
				span: $span
			}
		}}
	}
}

# Mark modules to automatically reload as overlays on change.
export def "overlay auto" [] {
	help "overlay auto"
}

# Add a module to the list of automatically reloaded overlays.
export def --env "overlay auto add" [module: path] {
	let span = (metadata $module).span
	let module = $module | path expand --no-symlink
	let module = if ($module | path basename) == "mod.nu" {
		$module | path dirname
	} else {
		$module
	}
	let path = module_to_path $module --span $span
	if not ($path | path exists) {
		error make {
			msg: $'File `($path)` does not exist.'
			label: {
				text: "module not found"
				span: $span
			}
		}
	}

	if (find_hooks $module | is-not-empty) {
		return
	}

	$env.config.hooks.pre_prompt ++= [
		{
			type: $TYPE
			module: $module
			condition: {|| true}
			code: $'overlay use -r `($module)`; overlay auto mark-fresh `($module)`'
		}
	]
}

def "nu-complete overlay-auto-list" [] {
	get_hooks | get module | each {$'`($in)`'}
}

# Remove a module from the list of automatically reloaded overlays.
# This does not unload the overlay.
export def --env "overlay auto remove" [module: path@"nu-complete overlay-auto-list"] {
	let hooks = find_hooks $module
	$env.config.hooks.pre_prompt = $env.config.hooks.pre_prompt | filter {
		$in not-in $hooks
	}
}

# Get the list of automatically reloaded overlay modules.
export def "overlay auto list" [] {
	get_hooks | get module
}

# Mark a module as fresh
export def --env "overlay auto mark-fresh" [module: path] {
	let loaded = date now

	let hooks = find_hooks $module
	let rest = $env.config.hooks.pre_prompt | filter {$in not-in $hooks}

	let path = module_to_path $module
	let new_hook = $hooks | first | merge { condition: {|| (ls $path).0.modified > $loaded} }

	$env.config.hooks.pre_prompt = ($rest ++ [$new_hook])

	log debug $'Refreshed `($module)`'
}
