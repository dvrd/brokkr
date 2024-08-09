package brokkr

import "base:builtin"
import "core:log"
import "core:os"
import "core:path/filepath"

Target :: enum {
	Debug,
	Release,
}

target_to_dir :: proc(t: Target) -> string {
	switch t {
	case .Debug:
		return "target/debug"
	case .Release:
		return "target/release"
	}
	return ""
}

Build_Options :: struct {
	name:   string,
	root:   string,
	target: Target,
	optim:  Opt_Mode,
}

Compile_Step :: struct {
	kind:   Build_Mode,
	name:   string,
	config: Odin_Config,
}

Build :: struct {
	steps:   [dynamic]^Compile_Step,
	builds:  map[string]^Compile_Step,
	runners: map[string]^Runner,
}

add_executable :: proc(b: ^Build, options: Build_Options) -> (step: ^Compile_Step) {
	step = new(Compile_Step)
	step.kind = .Exe
	if options.name == "" {
		log.error("Executable needs a name")
		os.exit(1)
	}
	step.name = options.name
	step.config = {
		src_path = options.root,
		out_dir  = target_to_dir(options.target),
		out_file = options.name,
		opt      = options.optim,
	}

	append(&b.steps, step)
	return
}

add_static_library :: proc(b: ^Build, options: Build_Options) -> (step: ^Compile_Step) {
	step = new(Compile_Step)
	step.kind = .Static
	if options.name == "" {
		log.error("Library needs a name")
		os.exit(1)
	}
	step.name = options.name
	step.config = {
		build_mode = .Static,
		src_path   = options.root,
		out_dir    = target_to_dir(options.target),
		out_file   = options.name,
		opt        = options.optim,
	}

	append(&b.steps, step)
	return
}

Runner :: struct {
	artifact:     ^Compile_Step,
	dependencies: []^Compile_Step,
	args:         []string,
}

install_artifact :: proc(b: ^Build, artifact: ^Compilte_Step) {
	b.builds[artifact.name] = artifact
}

add_run_artifact :: proc(b: ^Build, artifact: ^Compile_Step) -> (r: ^Runner) {
	r = new(Runner)
	r.artifact = artifact
	b.runners[artifact.name] = r
	return
}

add_arguments :: proc(r: ^Runner) {
	arguments := make([dynamic]string)
	flag := false
	for arg in os.args {
		if arg == "--" do flag = true
		if flag do append(&arguments, arg)
	}
	r.args = arguments[:]
}

path :: proc(sub_path: string) -> string {
	if filepath.is_abs(sub_path) {
		log.errorf("Expect relative path: {}", sub_path)
		os.exit(1)
	}

	new_path, ok := filepath.abs(sub_path)
	if !ok {
		log.errorf("Path provided could not be made absolute: {}", sub_path)
		log.error(os.get_last_error_string())
		os.exit(1)
	}

	return sub_path
}

handle_cli_commands :: proc() {
	cmd, cmd_ok := slice.get(os.args, 1)
	if !cmd_ok {
		log.error("Missing command")
		os.exit(1)
	}
	step, step_ok := slice.get(os.args, 2)

	switch cmd {
	case "build":
		if !step_ok {
			for _, &build in b.builds {
				odin(.Build, build.config)
			}
		} else {
			odin(.Build, b.builds[step].config)
		}
	case "run":
		if !step_ok {
			for _, &runner in b.runners {
				odin(.Build, runner.config)
			}
		} else {
			odin(.Build, b.runners[step].config)
		}
	}
}
