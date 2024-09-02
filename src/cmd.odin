package brokkr

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import os "core:os/os2"
import "core:slice"
import "core:strings"

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
