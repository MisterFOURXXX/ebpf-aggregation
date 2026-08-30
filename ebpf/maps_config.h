#ifndef __MAPS_CONFIG_H
#define __MAPS_CONFIG_H

// Maximum concurrent sessions
#define MAX_SESSIONS 1024

// Max floats per packet (must match client library)
#define PAYLOAD_FLOATS 32

// Maximum workers per session (bitmask limit)
#define MAX_WORKERS 4

// Timeout for stale entries (in seconds) - handled by controller
#define SESSION_TIMEOUT 1

#endif // __MAPS_CONFIG_H