#+private
package glodin

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:reflect"

@(require)
import gl "vendor:OpenGL"

GLODIN_LOG :: #config(GLODIN_LOG, true)
GLODIN_LOG_LEVEL :: #config(GLODIN_LOG_LEVEL, "Debug" when ODIN_DEBUG else "Error")
GLODIN_GL_LOG :: #config(GLODIN_GL_LOG, ODIN_DEBUG) && GLODIN_LOG

when GLODIN_GL_LOG {
	@(private = "file")
	gl_debug_message_callback :: proc "c" (
		source: u32,
		type: u32,
		id: u32,
		severity: u32,
		length: i32,
		message: cstring,
		userParam: rawptr,
	) {
		if id == 131185 {
			return
		}

		source_str: string
		switch source {
		case gl.DEBUG_SOURCE_API:
			source_str = "API"
		case gl.DEBUG_SOURCE_WINDOW_SYSTEM:
			source_str = "WINDOW SYSTEM"
		case gl.DEBUG_SOURCE_SHADER_COMPILER:
			source_str = "SHADER COMPILER"
		case gl.DEBUG_SOURCE_THIRD_PARTY:
			source_str = "THIRD PARTY"
		case gl.DEBUG_SOURCE_APPLICATION:
			source_str = "APPLICATION"
		case gl.DEBUG_SOURCE_OTHER:
			source_str = "OTHER"
		}

		type_string: string
		switch type {
		case gl.DEBUG_TYPE_ERROR:
			type_string = "ERROR"
		case gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR:
			type_string = "DEPRECATED_BEHAVIOR"
		case gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR:
			type_string = "UNDEFINED_BEHAVIOR"
		case gl.DEBUG_TYPE_PORTABILITY:
			type_string = "PORTABILITY"
		case gl.DEBUG_TYPE_PERFORMANCE:
			type_string = "PERFORMANCE"
		case gl.DEBUG_TYPE_MARKER:
			type_string = "MARKER"
		case gl.DEBUG_TYPE_OTHER:
			type_string = "OTHER"
		}

		level: log.Level
		switch severity {
		case gl.DEBUG_SEVERITY_NOTIFICATION:
			level = .Debug
		case gl.DEBUG_SEVERITY_LOW:
			level = .Info
		case gl.DEBUG_SEVERITY_MEDIUM:
			level = .Warning
		case gl.DEBUG_SEVERITY_HIGH:
			level = .Error
		}

		context = {}
		@(static)
		buf: [1024]byte

		if level >= logger.lowest_level {
			logger.procedure(
				logger.data,
				level,
				fmt.bprintf(
					buf[:],
					"[OpenGL(%s: %s)]: %v (Code: %d)",
					source_str,
					type_string,
					message,
					id,
				),
				{.Date, .Time, .Level, .Terminal_Color} & logger.options,
			)
		}
	}
}

logger_init :: proc() {
	when GLODIN_LOG {
		if context.logger.procedure == nil || context.logger.procedure == log.nil_logger_proc {
			logger = log.create_console_logger()

			ok: bool
			logger.lowest_level, ok = reflect.enum_from_name(log.Level, GLODIN_LOG_LEVEL)
			if !ok {
				logger.lowest_level = .Debug when ODIN_DEBUG else .Error
			}
		} else {
			logger = context.logger
		}

		when GLODIN_GL_LOG {
			gl.Enable(gl.DEBUG_OUTPUT)
			gl.DebugMessageCallback(gl_debug_message_callback, nil)
		}
	}
}

when GLODIN_LOG {
	@(private = "file")
	logger: log.Logger

	debugf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		logf_proc(.Debug, fmt_str, ..args, location = location)
	}
	infof :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		logf_proc(.Info, fmt_str, ..args, location = location)
	}
	warnf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		logf_proc(.Warning, fmt_str, ..args, location = location)
	}
	errorf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		logf_proc(.Error, fmt_str, ..args, location = location)
	}
	fatalf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		logf_proc(.Fatal, fmt_str, ..args, location = location)
	}

	debug :: proc(args: ..any, sep := " ", location := #caller_location) {
		log_proc(.Debug, ..args, sep = sep, location = location)
	}
	info :: proc(args: ..any, sep := " ", location := #caller_location) {
		log_proc(.Info, ..args, sep = sep, location = location)
	}
	warn :: proc(args: ..any, sep := " ", location := #caller_location) {
		log_proc(.Warning, ..args, sep = sep, location = location)
	}
	error :: proc(args: ..any, sep := " ", location := #caller_location) {
		log_proc(.Error, ..args, sep = sep, location = location)
	}
	fatal :: proc(args: ..any, sep := " ", location := #caller_location) {
		log_proc(.Fatal, ..args, sep = sep, location = location)
	}

	panic :: proc(args: ..any, location := #caller_location) -> ! {
		log_proc(.Fatal, ..args, location = location)
		runtime.panic("log.panic", location)
	}
	panicf :: proc(fmt_str: string, args: ..any, location := #caller_location) -> ! {
		logf_proc(.Fatal, fmt_str, ..args, location = location)
		runtime.panic("log.panicf", location)
	}

	@(disabled = ODIN_DISABLE_ASSERT)
	assert :: proc(
		condition: bool,
		message := "",
		location := #caller_location,
	) {
		if !condition {
			@(cold)
			internal :: proc(message: string, loc: runtime.Source_Code_Location) {
				p := context.assertion_failure_proc
				if p == nil {
					p = runtime.default_assertion_failure_proc
				}
				log_proc(.Fatal, message, location = loc)
				p("runtime assertion", message, loc)
			}
			internal(message, location)
		}
	}

	@(disabled = ODIN_DISABLE_ASSERT)
	assertf :: proc(
		condition: bool,
		fmt_str: string,
		args: ..any,
		location := #caller_location,
	) {
		if !condition {
			// NOTE(dragos): We are using the same trick as in builtin.assert
			// to improve performance to make the CPU not
			// execute speculatively, making it about an order of
			// magnitude faster
			@(cold)
			internal :: proc(loc: runtime.Source_Code_Location, fmt_str: string, args: ..any) {
				p := context.assertion_failure_proc
				if p == nil {
					p = runtime.default_assertion_failure_proc
				}
				message := fmt.tprintf(fmt_str, ..args)
				log_proc(.Fatal, message, location = loc)
				p("Runtime assertion", message, loc)
			}
			internal(location, fmt_str, ..args)
		}
	}

	@(private = "file")
	log_proc :: proc(level: log.Level, args: ..any, sep := " ", location := #caller_location) {
		if logger.procedure == nil || logger.procedure == log.nil_logger_proc {
			return
		}
		if level < logger.lowest_level {
			return
		}
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		str := fmt.tprint(..args, sep = sep) //NOTE(Hoej): While tprint isn't thread-safe, no logging is.
		logger.procedure(logger.data, level, str, logger.options, location)
	}

	@(private = "file")
	logf_proc :: proc(
		level: log.Level,
		fmt_str: string,
		args: ..any,
		location := #caller_location,
	) {
		if logger.procedure == nil || logger.procedure == log.nil_logger_proc {
			return
		}
		if level < logger.lowest_level {
			return
		}
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		str := fmt.tprintf(fmt_str, ..args)
		logger.procedure(logger.data, level, str, logger.options, location)
	}
} else {
	// odinfmt:disable
	debugf :: proc(fmt_str: string, args: ..any, location := #caller_location) {}
	infof  :: proc(fmt_str: string, args: ..any, location := #caller_location) {}
	warnf  :: proc(fmt_str: string, args: ..any, location := #caller_location) {}
	errorf :: proc(fmt_str: string, args: ..any, location := #caller_location) {}
	debug  :: proc(args: ..any,     sep := "",   location := #caller_location) {}
	info   :: proc(args: ..any,     sep := "",   location := #caller_location) {}
	warn   :: proc(args: ..any,     sep := "",   location := #caller_location) {}
	error  :: proc(args: ..any,     sep := "",   location := #caller_location) {}
	// odinfmt:enable

	fatal :: proc(args: ..any, sep := "", location := #caller_location) {
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		msg := fmt.tprint(..args)
		runtime.print_string(msg)
	}

	fatalf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		msg := fmt.tprint(..args)
		runtime.print_string(msg)
	}

	panic :: proc(args: ..any, location := #caller_location) -> ! {
		msg := fmt.tprint(..args)
		runtime.panic(msg, loc = location)
	}

	panicf :: proc(fmt_str: string, args: ..any, location := #caller_location) -> ! {
		msg := fmt.tprintf(fmt_str, ..args)
		runtime.panic(msg, loc = location)
	}

	@(disabled = ODIN_DISABLE_ASSERT)
	assert :: proc(condition: bool, message := "", location := #caller_location) {
		if !condition {
			@(cold)
			internal :: proc(message: string, loc: runtime.Source_Code_Location) {
				p := context.assertion_failure_proc
				if p == nil {
					p = runtime.default_assertion_failure_proc
				}
				fatal(message)
				p("runtime assertion", message, loc)
			}
			internal(message, location)
		}
	}

	@(disabled = ODIN_DISABLE_ASSERT)
	assertf :: proc(condition: bool, fmt_str: string, args: ..any, location := #caller_location) {
		if !condition {
			// NOTE(dragos): We are using the same trick as in builtin.assert
			// to improve performance to make the CPU not
			// execute speculatively, making it about an order of
			// magnitude faster
			@(cold)
			internal :: proc(loc: runtime.Source_Code_Location, fmt_str: string, args: ..any) {
				p := context.assertion_failure_proc
				if p == nil {
					p = runtime.default_assertion_failure_proc
				}
				message := fmt.tprintf(fmt_str, ..args)
				fatalf(message)
				p("Runtime assertion", message, loc)
			}
			internal(location, fmt_str, ..args)
		}
	}
}

