package bld

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import os "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

LOG_OPT :: log.Options{.Level, .Short_File_Path, .Line, .Terminal_Color}

tracking_allocator :: proc(
	track: ^mem.Tracking_Allocator,
	allocator := context.allocator,
) -> mem.Allocator {
	mem.tracking_allocator_init(track, allocator)
	return mem.tracking_allocator(track)
}

tracker_report :: proc(track: ^mem.Tracking_Allocator) {
	if len(track.allocation_map) > 0 {
		log.errorf("=== %v allocations not freed: ===", len(track.allocation_map))
		for _, entry in track.allocation_map {
			log.errorf("- %v bytes @ %v", entry.size, entry.location)
		}
	}
	if len(track.bad_free_array) > 0 {
		log.errorf("=== %v incorrect frees: ===", len(track.bad_free_array))
		for entry in track.bad_free_array {
			log.errorf("- %p @ %v", entry.memory, entry.location)
		}
	}
	mem.tracking_allocator_destroy(track)
}

/* BUILD SECTION */

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

build_binary :: proc(options: Build_Options, extra_args := []string{}) -> bool {
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
			extra_args = extra_args,
		)
	case .Clang:
		panic("Not yet developed")
	}

	return false
}

get_extra_args :: proc() -> []string {
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

/* CLI SECTION */

Command :: struct {
	name:  string,
	steps: [dynamic]Build_Options,
}

new_command :: proc(name: string) -> (cmd: ^Command) {
	cmd = new(Command)
	cmd.name = name
	cmd.steps = make([dynamic]Build_Options)
	return
}

add_artifact :: proc(cmd: ^Command, artifact_config: Build_Options) {
	append(&cmd.steps, artifact_config)
}

run_steps :: proc(steps: []Build_Options) {
	for step in steps {
		build_binary(step)
	}
}

process_commands :: proc(cmds: []^Command) {
	user_cmd, found := slice.get(os.args, 1)
	if !found {
		log.error("Please provide a command to execute")
		os.exit(1)
	}

	for cmd in cmds {
		if cmd.name == user_cmd {
			run_steps(cmd.steps[:])
			os.exit(0)
		}
	}

	log.error("Please provide a KNOWN command to execute")
	os.exit(1)
}

/* COMPILE ODIN SECTION */

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
	extra_args := []string{},
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

/* CONSTANTS */

DEFAULT_VET :: Vet_Flags{.Unused, .Shadowing, .Using_Stmt}

_compiler_flag_to_arg := [Compiler_Flag]string {
	.Debug                     = "-debug",
	.Disable_Assert            = "-disable-assert",
	.No_Bounds_Check           = "-no-bounds-check",
	.No_CRT                    = "-no-crt",
	.LLD                       = "-lld",
	.Use_Separate_Modules      = "-use-separate-modules",
	.Ignore_Unknown_Attributes = "-ignore-unknown-attributes",
	.No_Entry_Point            = "-no-entry-point",
	.Disable_Red_Zone          = "-disable-red-zone",
	.Disallow_Do               = "-disallow-do",
	.Default_To_Nil_Allocator  = "-default-to-nil-allocator",
	.Ignore_Vs_Search          = "-ignore-vs-search",
	.Foreign_Error_Procedures  = "-foreign-error-procedures",
	.Terse_Errors              = "-terse-errors",
	.Ignore_Warnings           = "-ignore-warnings",
	.Warnings_As_Errors        = "-warnings-as-errors",
	.Keep_Temp_Files           = "-keep-temp-files",
	.No_Threaded_Checker       = "-no-threaded-checker",
	.Show_System_Calls         = "-show-system-calls",
	.No_Thread_Local           = "-no-thread-local",
	.Dynamic_Map_Calls         = "-dynamic-map-calls",
	.No_RTTI                   = "-no-rtti",
}

_opt_mode_to_arg := [Opt_Mode]string {
	.None       = "-o:none",
	.Minimal    = "-o:minimal",
	.Size       = "-o:size",
	.Speed      = "-o:speed",
	.Aggressive = "-o:aggressive",
}

_build_mode_to_arg := [Build_Mode]string {
	.None    = "",
	.Exe     = "-build-mode:exe",
	.Static  = "-build-mode:static",
	.Shared  = "-build-mode:shared",
	.OBJ     = "-build-mode:obj",
	.ASM     = "-build-mode:asm",
	.LLVM_IR = "-build-mode:llvm-ir",
}

_vet_flag_to_arg := [Vet_Flag]string {
	.Unused      = "-vet-unused",
	.Shadowing   = "-vet-shadowing",
	.Using_Stmt  = "-vet-using-stmt",
	.Using_Param = "-vet-using-param",
	.Style       = "-vet-style",
	.Semicolon   = "-vet-semicolon",
}

_style_mode_to_arg := [Style_Mode]string {
	.None             = "",
	.Strict           = "-strict-style",
	.Strict_Init_Only = "-strict-style-init-only",
}

_os_to_arg := [runtime.Odin_OS_Type]string {
	.Unknown      = "UNKNOWN_OS",
	.Windows      = "windows",
	.Darwin       = "darwin",
	.Linux        = "linux",
	.Essence      = "essence",
	.FreeBSD      = "freebsd",
	.OpenBSD      = "openbsd",
	.NetBSD       = "netbsd",
	.Orca         = "orca",
	.WASI         = "wasi",
	.JS           = "js",
	.Freestanding = "freestanding",
	.Haiku        = "haiku",
}

// To be combined with _target_to_arg
_arch_to_arg := [runtime.Odin_Arch_Type]string {
	.Unknown   = "UNKNOWN_ARCH",
	.amd64     = "amd64",
	.i386      = "i386",
	.arm32     = "arm32",
	.arm64     = "arm64",
	.wasm32    = "wasm32",
	.wasm64p32 = "wasm64p32",
	.riscv64   = "riscv64",
}

_abi_to_arg := [Platform_ABI]string {
	.Default = "",
	.SysV    = "sysv",
}

_reloc_mode_to_arg := [Reloc_Mode]string {
	.Default        = "-reloc-mode:default",
	.Static         = "-reloc-mode:static",
	.PIC            = "-reloc-mode:pic",
	.Dynamic_No_PIC = "-reloc-mode:dynamic-no-pic",
}

_sanitize_to_arg := [Sanitize_Flag]string {
	.Address = "-sanitize:address",
	.Memory  = "-sanitize:memory",
	.Thread  = "-sanitize:thread",
}

_timings_mode_to_arg := [Timings_Mode]string {
	.Disabled = "",
	.Basic    = "-show-timings",
	.Advanced = "-show-more-timings",
}

/* CMD SECTION */
launch :: proc(args: []string) -> bool {
	cmd, found := slice.get(args, 0)
	assert(found, "launch requires at least 1 argument to execute as program")

	cmd, found = find_program(cmd)
	if !found {
		log.error("Could not find progra:", args[0])
		return false
	}
	args[0] = cmd

	READ :: 0
	WRITE :: 1
	err: os.Error

	stdin_pipe: [2]^os.File
	stdin_pipe[READ], stdin_pipe[WRITE], err = os.pipe()
	assert(err == nil, fmt.tprint("Failed to create new stdin pipe:", err))

	stdout_pipe: [2]^os.File
	stdout_pipe[READ], stdout_pipe[WRITE], err = os.pipe()
	assert(err == nil, fmt.tprint("Failed to create new stdout pipe:", err))

	stderr_pipe: [2]^os.File
	stderr_pipe[READ], stderr_pipe[WRITE], err = os.pipe()
	assert(err == nil, fmt.tprint("Failed to create new stderr pipe:", err))

	cwd: string
	cwd, err = os.getwd(context.temp_allocator)
	assert(err == nil, fmt.tprint("Failed to get cwd:", err))

	desc: os.Process_Desc = {
		env         = os.environ(context.temp_allocator),
		working_dir = cwd,
		command     = args,
		stdin       = stdin_pipe[WRITE],
		stdout      = stdout_pipe[WRITE],
		stderr      = stderr_pipe[WRITE],
	}

	log.debugf("Executing `{}`", desc.command)
	p: os.Process
	p, err = os.process_start(desc)
	if err != nil {
		log.errorf("Could not start `{}`: {}", cmd, os.error_string(err))
		return false
	}

	assert(os.close(stdin_pipe[WRITE]) == nil, "Failed to close STDIN [WRITE] pipe")
	assert(os.close(stdout_pipe[WRITE]) == nil, "Failed to close STDOUT [WRITE] pipe")
	assert(os.close(stderr_pipe[WRITE]) == nil, "Failed to close STDERR [WRITE] pipe")

	buf: [mem.Kilobyte]u8
	bits: int

	bits, err = os.read(stdin_pipe[READ], buf[:])
	if err == nil do fmt.print(string(buf[:bits]))

	bits, err = os.read(stdout_pipe[READ], buf[:])
	if err == nil do fmt.print(string(buf[:bits]))

	bits, err = os.read(stderr_pipe[READ], buf[:])
	if err == nil do fmt.print(string(buf[:bits]))

	state: os.Process_State
	state, err = os.process_wait(p)
	if err != nil {
		log.error("Could not wait process:", os.error_string(err))
		return false
	}

	assert(os.close(stdin_pipe[READ]) == nil, "Failed to close STDIN [READ] pipe")
	assert(os.close(stdout_pipe[READ]) == nil, "Failed to close STDOUT [READ] pipe")
	assert(os.close(stderr_pipe[READ]) == nil, "Failed to close STDERR [READ] pipe")

	if !state.exited {
		if err = os.process_kill(p); err != nil {
			log.error("Could not kill process:", os.error_string(err))
			return false
		}
	}


	if err = os.process_close(p); err != nil {
		log.error("Could not close process:", os.error_string(err))
		return false
	}

	if state.exit_code != 0 {
		log.errorf(
			"Process exited with code `{}` {}",
			state.exit_code,
			state.success ? "successfully" : "unsuccessfully",
		)
		return false
	}

	return true
}

find_program :: proc(target: string) -> (string, bool) {
	log.debug("Searching for:", target)

	env_path, found := os.lookup_env("PATH", context.allocator)
	assert(found, "Missing PATH environment variable")

	dirs := strings.split(env_path, ":", context.temp_allocator)
	assert(len(dirs) != 0, "Environment PATH has no directories")

	for dir in dirs {
		if !os.is_dir(dir) {
			log.warnf("{} is not a directory", dir)
			continue
		}

		fd, err := os.open(dir)
		defer os.close(fd)
		if err != nil {
			log.warnf("Could not open {}: {}", dir, os.error_string(err))
			continue
		}

		fis: []os.File_Info
		os.file_info_slice_delete(fis, context.temp_allocator)
		fis, err = os.read_dir(fd, -1, context.temp_allocator)
		if err != nil {
			log.warnf(
				"Encountered error getting directory's `{}` children: {}",
				dir,
				os.error_string(err),
			)
			continue
		}

		for fi in fis {
			if fi.name == target {
				log.debugf("Found matching program at: {}", fi.fullpath)
				return strings.clone(fi.fullpath, context.temp_allocator), true
			}
		}
	}

	return "", false
}
