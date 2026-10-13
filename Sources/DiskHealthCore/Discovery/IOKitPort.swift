import IOKit

/// Port for IOKit lookups. `MACH_PORT_NULL` is the documented equivalent of `ioMainPort`,
/// which only exists from macOS 12 on (Aman Legacy builds the engine for macOS 10.13).
let ioMainPort = mach_port_t(MACH_PORT_NULL)
