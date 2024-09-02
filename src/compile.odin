package brokkr

import "base:runtime"
import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

Build_Mode :: enum {
	None,
	Exe,
	Static,
	Shared,
	OBJ,
	ASM,
	LLVM_IR,
}

Define_Val :: union #no_nil {
	bool,
	int,
	string,
}

Define :: struct {
	name: string,
	val:  Define_Val,
}

Collection :: struct {
	name: string,
	path: string,
}

Platform_ABI :: enum {
	Default,
	SysV,
}

Platform :: struct {
	os:   runtime.Odin_OS_Type,
	arch: runtime.Odin_Arch_Type,
}

Vet_Flag :: enum {
	Unused,
	Shadowing,
	Using_Stmt,
	Using_Param,
	Style,
	Semicolon,
}

Vet_Flags :: bit_set[Vet_Flag]

Subsystem_Kind :: enum {
	Console,
	Windows,
}

Style_Mode :: enum {
	None,
	Strict,
	Strict_Init_Only,
}

Opt_Mode :: enum {
	None,
	Minimal,
	Speed,
	Size,
	Aggressive,
}

Reloc_Mode :: enum {
	Default,
	Static,
	PIC,
	Dynamic_No_PIC,
}

Compiler_Flag :: enum {
	Keep_Temp_Files,
	Debug,
	Disable_Assert,
	No_Bounds_Check,
	No_CRT,
	No_Thread_Local,
	LLD, // maybe do Linker :: enum { Default, LLD, }
	Use_Separate_Modules,
	No_Threaded_Checker, // This is more like an user thing?
	Ignore_Unknown_Attributes,
	Disable_Red_Zone,
	Dynamic_Map_Calls,
	Disallow_Do, // Is this a vet thing? Ask Bill.
	Default_To_Nil_Allocator,

	// Do something different with these?
	Ignore_Warnings,
	Warnings_As_Errors,
	Terse_Errors,
	//
	Foreign_Error_Procedures,
	Ignore_Vs_Search,
	No_Entry_Point,
	Show_System_Calls,
	No_RTTI,
}

Compiler_Flags :: bit_set[Compiler_Flag]

Error_Pos_Style :: enum {
	Default, // .Odin
	Odin, // file/path(45:3)
	Unix, // file/path:45:3
}

Sanitize_Flag :: enum {
	Address,
	Memory,
	Thread,
}

Sanitize_Flags :: bit_set[Sanitize_Flag]

Timings_Mode :: enum {
	Disabled,
	Basic,
	Advanced,
}

Timings_Format :: enum {
	Default,
	JSON,
	CSV,
}

//TODO
Timings_Export :: struct {
	mode:     Timings_Mode,
	format:   Timings_Format,
	filename: Maybe(string),
}

Odin_Command_Type :: enum {
	Build,
	Check,
	Run,
}

Odin_Config :: struct {
	platform:     Platform,
	abi:          Platform_ABI, // Only makes sense for freestanding
	src_path:     string,
	out_dir:      string,
	out_file:     string,
	pdb_name:     string,
	rc_path:      string,
	subsystem:    Subsystem_Kind,
	thread_count: int,
	build_mode:   Build_Mode,
	flags:        Compiler_Flags,
	opt:          Opt_Mode,
	vet:          Vet_Flags,
	style:        Style_Mode,
	reloc:        Reloc_Mode,
	sanitize:     Sanitize_Flags,
	timings:      Timings_Export,
	defines:      []Define,
	collections:  []Collection,
}

split_odin_args :: proc(args: string, allocator := context.allocator) -> []string {
	return strings.split(args, " ", allocator)
}

build_odin_args :: proc(
	cmd: string,
	config: Odin_Config,
	extra_args: []string,
	allocator := context.allocator,
) -> (
	args: []string,
) {
	context.allocator = allocator
	odin_args := make([dynamic]string, context.allocator)

	append(&odin_args, "odin")
	append(&odin_args, cmd)
	append(&odin_args, filepath.base(config.src_path))
	append(&odin_args, fmt.tprintf("-out:%s/%s", config.out_dir, config.out_file))

	if config.platform.os == .Windows {
		if config.pdb_name != "" do append(&odin_args, fmt.tprintf("-pdb-name:%s", config.pdb_name))
		if config.rc_path != "" do append(&odin_args, fmt.tprintf("-resource:%s", config.rc_path))
		switch config.subsystem {
		case .Console:
			append(&odin_args, "-subsystem:console")
		case .Windows:
			append(&odin_args, "-subsystem:windows")
		}
	}

	if config.build_mode != .None {
		append(&odin_args, _build_mode_to_arg[config.build_mode])
	}

	if config.opt != .None {
		append(&odin_args, _opt_mode_to_arg[config.opt])
	}

	if config.reloc != .Default {
		append(&odin_args, _reloc_mode_to_arg[config.reloc])
	}

	for flag in Vet_Flag do if flag in config.vet {
		append(&odin_args, _vet_flag_to_arg[flag])
	}
	for flag in Compiler_Flag do if flag in config.flags {
		append(&odin_args, _compiler_flag_to_arg[flag])
	}
	for flag in Sanitize_Flag do if flag in config.sanitize {
		append(&odin_args, _sanitize_to_arg[flag])
	}
	if config.style != .None {
		append(&odin_args, _style_mode_to_arg[config.style])
	}
	for collection in config.collections {
		append(&odin_args, fmt.tprintf("-collection:%s=\"%s\"", collection.name, collection.path))
	}
	for define in config.defines {
		switch val in define.val {
		case string:
			append(&odin_args, fmt.tprintf("-define:%s=\"%s\"", define.name, val))
		case bool:
			append(
				&odin_args,
				fmt.tprintf("-define:%s=%s", define.name, "true" if val else "false"),
			)
		case int:
			append(&odin_args, fmt.tprintf("-define:%s=%d", define.name, val))
		}
	}

	if config.platform.os != .Unknown {
		if config.abi == .Default {
			append(
				&odin_args,
				fmt.tprintf(
					"-target:%s_%s",
					_os_to_arg[config.platform.os],
					_arch_to_arg[config.platform.arch],
				),
			)
		} else {
			append(
				&odin_args,
				fmt.tprintf(
					"-target:%s_%s_%s",
					_os_to_arg[config.platform.os],
					_arch_to_arg[config.platform.arch],
					_abi_to_arg[config.abi],
				),
			)
		}
	}

	if config.thread_count > 0 {
		append(&odin_args, fmt.tprintf("-thread-count:%d", config.thread_count))
	}

	if config.timings.mode != .Disabled {
		append(&odin_args, fmt.tprintf("%s", _timings_mode_to_arg[config.timings.mode]))
	}

	if len(extra_args) > 0 {
		append(&odin_args, "--")
		for arg in extra_args do append(&odin_args, arg)
	}

	return odin_args[:]
}

odin :: proc(
	command_type: Odin_Command_Type,
	config: Odin_Config,
	extra_args: []string,
	print_command := true,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	config := config

	cmd: string
	switch command_type {
	case .Check:
		cmd = "check"
	case .Build:
		cmd = "build"
	case .Run:
		cmd = "run"
	case:
		panic("Invalid command_type")
	}

	err := os.mkdir_all(config.out_dir)
	assert(
		err == nil || err == .Exist,
		fmt.tprintf(
			"Failed to create target directory `{}`: {}",
			config.out_dir,
			os.error_string(err),
		),
	)

	odin_args := build_odin_args(cmd, config, extra_args, context.temp_allocator)

	if print_command {
		log.info("Executing:")
		fmt.println(strings.join(odin_args, " "))
	}

	if !launch(odin_args) {
		log.error("Compilation failed")
		return false
	}

	return true
}


should_rebuild :: proc(src, bin: string, allocator := context.temp_allocator) -> bool {
	cwd, getwd_err := os.getwd(allocator)
	assert(getwd_err == nil, fmt.tprint("Could not get currrent working directory:", getwd_err))

	src_path := filepath.join({cwd, src}, allocator)
	assert(os.exists(src_path), fmt.tprint("`{}` should exist", src_path))

	src_mod_time, src_err := os.modification_time_by_path(src_path)
	assert(src_err == nil, fmt.tprint("Could not get `{}`'s time: {}", src_path, src_err))

	bin_path := filepath.join({cwd, bin}, allocator)
	assert(os.exists(bin_path), fmt.tprint("`{}` should exist", bin_path))

	bin_mod_time, bin_err := os.modification_time_by_path(bin_path)
	assert(bin_err == nil, fmt.tprint("Could not get `{}`'s time: {}", bin_path, bin_err))

	return time.time_to_unix_nano(src_mod_time) > time.time_to_unix_nano(bin_mod_time)
}
