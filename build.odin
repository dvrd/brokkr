package build

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import bld "src"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer tracker_report(&track)

	context.logger = log.create_console_logger(
		opt = log.Options{.Level, .Short_File_Path, .Line, .Terminal_Color},
	)
	defer free(context.logger.data)

	bld.build_binary(
		{build_mode = .Shared, name = "brokkr", root = "src", target = .Release, optim = .Speed},
	)
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
