#include "CDiskIO.h"
#include "nvme_interface.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <string.h>

// op_mask: 1 = SMART log (512 bytes), 2 = Identify data (4096 bytes), 3 = both,
// opening the plug-in only once.
static int _cdiskio_do_nvme_operation(const char *bsd_name, unsigned char *smart_buffer, unsigned char *identify_buffer, int op_mask) {
    io_service_t service = MACH_PORT_NULL;
    io_service_t target_service = MACH_PORT_NULL;
    IOCFPlugInInterface **plugin = NULL;
    IONVMeSMARTInterface **smartIf = NULL;
    int result = -1;
    SInt32 score = 0;
    IOReturn err = kIOReturnSuccess;

    // 1. IOMedia from the BSD name (IOServiceGetMatchingService consumes the dictionary).
    CFMutableDictionaryRef matchingDict = IOBSDNameMatching(kIOMainPortDefault, 0, bsd_name);
    if (!matchingDict) {
        return -1;
    }
    service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict);
    if (service == MACH_PORT_NULL) {
        return -1;
    }

    // 2. Walk up the parents to the controller that reports “NVMe SMART Capable”.
    target_service = service;
    IOObjectRetain(target_service);
    bool found = false;
    while (target_service != MACH_PORT_NULL) {
        CFTypeRef smartCapable = IORegistryEntryCreateCFProperty(target_service, CFSTR("NVMe SMART Capable"), kCFAllocatorDefault, 0);
        if (smartCapable) {
            bool capable = CFGetTypeID(smartCapable) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)smartCapable);
            CFRelease(smartCapable);
            if (capable) {
                found = true;
                break;
            }
        }
        io_service_t parent = MACH_PORT_NULL;
        IORegistryEntryGetParentEntry(target_service, kIOServicePlane, &parent);
        IOObjectRelease(target_service);
        target_service = parent;
    }
    if (!found || target_service == MACH_PORT_NULL) {
        result = -2;
        goto cleanup;
    }

    // 3. NVMe SMART plug-in and interface.
    err = IOCreatePlugInInterfaceForService(target_service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (err != kIOReturnSuccess || !plugin) {
        result = -3;
        goto cleanup;
    }
    err = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smartIf);
    if (err != kIOReturnSuccess || !smartIf) {
        smartIf = NULL;
        result = -3;
        goto cleanup;
    }

    // 4. Reads.
    result = 0;
    if (op_mask & 1) {
        memset(smart_buffer, 0, 512);
        if ((*smartIf)->SMARTReadData(smartIf, smart_buffer) != kIOReturnSuccess) {
            result = -4;
            goto cleanup;
        }
    }
    if (op_mask & 2) {
        memset(identify_buffer, 0, 4096);
        // Namespace 0: controller Identify data.
        if ((*smartIf)->GetIdentifyData(smartIf, identify_buffer, 0) != kIOReturnSuccess) {
            result = -4;
            goto cleanup;
        }
    }

cleanup:
    if (smartIf) {
        (*smartIf)->Release(smartIf);
    }
    if (plugin) {
        IODestroyPlugInInterface(plugin);
    }
    if (target_service != MACH_PORT_NULL) {
        IOObjectRelease(target_service);
    }
    if (service != MACH_PORT_NULL) {
        IOObjectRelease(service);
    }
    return result;
}


int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size) {
    if (bsd_name == NULL || out_buffer == NULL) return -1;
    if (buffer_size < 512) return -5;
    return _cdiskio_do_nvme_operation(bsd_name, out_buffer, NULL, 1);
}

int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size) {
    if (bsd_name == NULL || out_buffer == NULL) return -1;
    if (buffer_size < 4096) return -5;
    return _cdiskio_do_nvme_operation(bsd_name, NULL, out_buffer, 2);
}

int cdiskio_read_nvme_all(const char *bsd_name, unsigned char *smart_buffer, unsigned char *identify_buffer) {
    if (bsd_name == NULL || smart_buffer == NULL || identify_buffer == NULL) return -1;
    return _cdiskio_do_nvme_operation(bsd_name, smart_buffer, identify_buffer, 3);
}
