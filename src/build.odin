package brokkr

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"

Target :: enum {
	Debug,
	Release,
}


Compiler :: enum {
	Odin,
	Clang,
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
	name:       string,
	build_mode: Build_Mode,
	root:       string,
	optim:      Opt_Mode,
	target:     Target,
	compiler:   Compiler,
}

build_binary :: proc(options: Build_Options) -> bool {
	assert(options.name != "", "Executable needs a name")
	switch options.compiler {
	case .Odin:
		odin(
			.Build,
			{
				build_mode = options.build_mode,
				src_path = path(options.root, context.temp_allocator),
				out_dir = target_to_dir(options.target),
				out_file = options.name,
				opt = options.optim,
			},
			extra_args = get_extra_arguments(),
		)
	case .Clang:
		panic("Not yet developed")
	}

	return false
}

get_extra_arguments :: proc() -> []string {
	arguments := make([dynamic]string)
	flag := false
	for arg in os.args {
		if arg == "--" do flag = true
		if flag do append(&arguments, arg)
	}
	return arguments[:]
}

path :: proc(sub_path: string, allocator := context.allocator) -> string {
	assert(!filepath.is_abs(sub_path), fmt.tprintf("Expect `{}` to be a relative path", sub_path))

	new_path, ok := filepath.abs(sub_path, allocator)
	assert(ok, fmt.tprintf("`{}` could not be made absolute", sub_path))

	return new_path
}
