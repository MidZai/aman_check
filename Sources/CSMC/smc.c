#include "CSMC.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

// Disposition attendue par le pilote AppleSMC (80 octets, alignement naturel).
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPowerLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPowerLimit powerLimit;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t command;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

_Static_assert(sizeof(SMCParam) == 80, "AppleSMC attend une structure de 80 octets");

enum {
    kSelectorHandleEvent = 2,
    kCommandReadKey = 5,
    kCommandKeyFromIndex = 8,
    kCommandKeyInfo = 9
};

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static void unfourcc(uint32_t v, char out[5]) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16); out[2] = (char)(v >> 8); out[3] = (char)v; out[4] = 0;
}

static int call(uint32_t connection, SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    memset(out, 0, sizeof(SMCParam));
    kern_return_t kr = IOConnectCallStructMethod((io_connect_t)connection, kSelectorHandleEvent,
                                                 in, sizeof(SMCParam), out, &outSize);
    if (kr != KERN_SUCCESS) return (int)kr;
    return out->result == 0 ? 0 : -(int)out->result;
}

uint32_t aman_smc_open(void) {
    // MACH_PORT_NULL : port maître par défaut, valable sur toutes les versions de macOS.
    io_service_t service = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return kr == KERN_SUCCESS ? (uint32_t)connection : 0;
}

void aman_smc_close(uint32_t connection) {
    if (connection) IOServiceClose((io_connect_t)connection);
}

int aman_smc_read(uint32_t connection, const char *key, char type[5], uint8_t bytes[32], uint32_t *size) {
    if (!connection || !key || strlen(key) != 4) return -1;
    SMCParam in, out;
    memset(&in, 0, sizeof in);
    in.key = fourcc(key);
    in.command = kCommandKeyInfo;
    int r = call(connection, &in, &out);
    if (r != 0) return r;
    SMCKeyInfo info = out.keyInfo;
    if (info.dataSize == 0 || info.dataSize > 32) return -2;

    memset(&in, 0, sizeof in);
    in.key = fourcc(key);
    in.keyInfo.dataSize = info.dataSize;
    in.command = kCommandReadKey;
    r = call(connection, &in, &out);
    if (r != 0) return r;
    unfourcc(info.dataType, type);
    memcpy(bytes, out.bytes, info.dataSize);
    *size = info.dataSize;
    return 0;
}

int aman_smc_key_at(uint32_t connection, uint32_t index, char key[5]) {
    if (!connection) return -1;
    SMCParam in, out;
    memset(&in, 0, sizeof in);
    in.command = kCommandKeyFromIndex;
    in.data32 = index;
    int r = call(connection, &in, &out);
    if (r != 0) return r;
    unfourcc(out.key, key);
    return 0;
}
