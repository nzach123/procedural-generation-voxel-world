# gdlint:ignore-file:print-statement
## DebugLogger - Conditional debug output utility
## Thread-safe static class for debug logging.
## Uses const to avoid data race on _debug_enabled flag.
class_name DebugLogger
extends RefCounted


## Set to false for release builds (or use: OS.is_debug_build())
const DEBUG_ENABLED: bool = true


## Logs a debug message with optional context prefix.
## @param msg The message to log.
## @param ctx Optional context string (e.g., "ChunkManager", "PERF").
static func debug(msg: String, ctx: String = "") -> void:
	if DEBUG_ENABLED:
		if ctx.is_empty():
			print(msg)
		else:
			print("[%s] %s" % [ctx, msg])


## Logs a warning message.
static func warn(msg: String, ctx: String = "") -> void:
	if ctx.is_empty():
		push_warning(msg)
	else:
		push_warning("[%s] %s" % [ctx, msg])


## Logs an error message.
static func error(msg: String, ctx: String = "") -> void:
	if ctx.is_empty():
		push_error(msg)
	else:
		push_error("[%s] %s" % [ctx, msg])
