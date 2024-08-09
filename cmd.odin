package brokkr

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"

when ODIN_OS == .Darwin {
	foreign import lib "system:System.framework"
} else when ODIN_OS == .Linux {
	foreign import lib "system:c"
}

foreign lib {
	@(link_name = "execvp")
	_unix_execvp :: proc(path: cstring, argv: [^]cstring) -> c.int ---
	@(link_name = "fork")
	_unix_fork :: proc() -> pid_t ---
	@(link_name = "waitpid")
	_unix_waitpid :: proc(pid: pid_t, stat_loc: ^c.int, options: c.int) -> pid_t ---
}

Pid :: distinct c.int
pid_t :: c.int

/// Termination signal
/// Only retrieve the code if WIFSIGNALED(s) = true
WTERMSIG :: #force_inline proc "contextless" (s: c.int) -> c.int {
	return s & 0x7f
}

/// Check if the process signaled
WIFSIGNALED :: #force_inline proc "contextless" (s: c.int) -> bool {
	return cast(i8)(((s) & 0x7f) + 1) >> 1 > 0
}

/// Check if the process terminated normally (via exit.2)
WIFEXITED :: #force_inline proc "contextless" (s: c.int) -> bool {
	return WTERMSIG(s) == 0
}

WaitOption :: enum {
	WNOHANG     = 0,
	WUNTRACED   = 1,
	WSTOPPED    = WUNTRACED,
	WEXITED     = 2,
	WCONTINUED  = 3,
	WNOWAIT     = 24,
	// For processes created using clone
	__WNOTHREAD = 29,
	__WALL      = 30,
	__WCLONE    = 31,
}

WaitOptions :: bit_set[WaitOption;i32]

CmdRunner :: struct {
	args: []string,
	path: string,
	pid:  Pid,
	err:  os.Error,
}

fork :: proc() -> (Pid, os.Error) {
	pid := _unix_fork()
	if pid == -1 {
		return -1, os.get_last_error()
	}
	return Pid(pid), nil
}

launch :: proc(args: []string) -> os.Error {
	r: CmdRunner
	if !init(&r, args) do return r.err
	if !run(&r) do return r.err
	if !wait(&r) do return r.err

	return nil
}

init :: proc(cmd: ^CmdRunner, args: []string) -> (ok: bool) {
	cmd.args = args
	cmd.pid, cmd.err = fork()
	return cmd.err == nil
}

run :: proc(cmd: ^CmdRunner) -> bool {
	if (cmd.pid == 0) {
		err := exec(cmd.args)
		return err == nil
	}
	return true
}

wait :: proc(cmd: ^CmdRunner) -> bool {
	status: c.int
	wpid, err := waitpid(cmd.pid, &status, {.WUNTRACED})
	cmd.err = err
	return wpid == cmd.pid && WIFEXITED(status)
}

exec :: proc(args: []string = {}) -> os.Error {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	path, ok := slice.get(args, 0)
	if !ok do return os.EINVAL

	path_cstr := strings.clone_to_cstring(path, context.temp_allocator)
	args_cstrs := make([]cstring, len(args) + 1, context.temp_allocator)
	for i in 0 ..< len(args) {
		args_cstrs[i] = strings.clone_to_cstring(args[i], context.temp_allocator)
	}

	if _unix_execvp(path_cstr, raw_data(args_cstrs)) < 0 {
		return os.get_last_error()
	}

	return nil
}

find_program :: proc(target: string) -> (string, bool) {
	env_path := os.get_env("PATH", context.temp_allocator)
	dirs := strings.split(env_path, ":", context.temp_allocator)

	if len(dirs) == 0 do return "", false

	for dir in dirs {
		if !os.is_dir(dir) do continue

		fd, err := os.open(dir)
		defer os.close(fd)
		if err != nil do continue

		fis: []os.File_Info
		os.file_info_slice_delete(fis, context.temp_allocator)
		fis, err = os.read_dir(fd, -1, context.temp_allocator)
		if err != nil do continue

		for fi in fis {
			if fi.name == target do return strings.clone(fi.fullpath, context.temp_allocator), true
		}
	}

	return "", false
}

waitpid :: proc "contextless" (pid: Pid, status: ^c.int, options: WaitOptions) -> (Pid, os.Error) {
	ret := _unix_waitpid(cast(i32)pid, status, transmute(c.int)options)
	return Pid(ret), os.get_last_error()
}

make_directory :: proc(name: string) {
	slash_dir, _ := filepath.to_slash(name, context.temp_allocator)
	dirs := strings.split_after(slash_dir, "/", context.temp_allocator)
	for _, i in dirs {
		new_dir := strings.concatenate(dirs[0:i + 1], context.temp_allocator)
		os.make_directory(new_dir)
	}
}
