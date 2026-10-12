#include "CDiskIO.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/ata/ATASMARTLib.h>
#include <string.h>

// No command that changes the drive's data. One deliberate, isolated exception:
// cdiskio_enable_ata_smart sends SMARTEnableDisableOperations(true). Never disabling,
// autosave (SMARTEnableDisableAutosave), self-tests or log writes.

typedef struct {
    IOCFPlugInInterface **plugin;
    IOATASMARTInterface **smart;
} ata_handle;

static void close_handle(ata_handle *h) {
    // QueryInterface added a reference: it must be released before the plug-in is destroyed,
    // otherwise the connection to the driver stays open after every read.
    if (h->smart) {
        (*h->smart)->Release(h->smart);
        h->smart = NULL;
    }
    if (h->plugin) {
        IODestroyPlugInInterface(h->plugin);
        h->plugin = NULL;
    }
}

static int is_smart_disabled(IOATASMARTInterface **smart_interface) {
    unsigned char identify[512] = {0};
    UInt32 outSize = 0;
    IOReturn ikr = (*smart_interface)->GetATAIdentifyData(smart_interface, identify, 512, &outSize);
    if (ikr == kIOReturnSuccess && outSize >= 512) {
        // Words 82 and 85, bit 0: S.M.A.R.T. supported / enabled (little-endian).
        unsigned short w82 = (unsigned short)(identify[164] | (identify[165] << 8));
        unsigned short w85 = (unsigned short)(identify[170] | (identify[171] << 8));
        if ((w82 & 0x0001) != 0 && (w85 & 0x0001) == 0) {
            return 1;
        }
    }
    return 0;
}

// require_enabled: returns -6 if S.M.A.R.T. is disabled. Identify and enabling don't need it.
static int open_handle(const char *bsd_name, ata_handle *out, int require_enabled) {
    out->plugin = NULL;
    out->smart = NULL;
    if (!bsd_name) return -1;

    CFMutableDictionaryRef matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsd_name);
    if (!matching) return -2;

    // IOServiceGetMatchingService consumes the dictionary reference.
    io_object_t media = IOServiceGetMatchingService(kIOMainPortDefault, matching);
    if (media == 0) return -3;

    // The ATA S.M.A.R.T. plug-in is published by an ancestor (IOAHCIBlockStorageDevice, etc.):
    // walk up the tree to the first node that accepts it.
    io_object_t current = media;
    IOObjectRetain(current);
    while (current != 0) {
        SInt32 score = 0;
        IOCFPlugInInterface **plugin = NULL;
        kern_return_t kr = IOCreatePlugInInterfaceForService(current, kIOATASMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
        if (kr == kIOReturnSuccess && plugin != NULL) {
            IOATASMARTInterface **smart = NULL;
            HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID), (LPVOID *)&smart);
            if (res == S_OK && smart != NULL) {
                out->plugin = plugin;
                out->smart = smart;
                IOObjectRelease(current);
                break;
            }
            IODestroyPlugInInterface(plugin);
        }
        io_object_t parent = 0;
        kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        IOObjectRelease(current);
        current = (kr == kIOReturnSuccess) ? parent : 0;
    }
    IOObjectRelease(media);

    if (!out->smart) return -5;

    // S.M.A.R.T. disabled: report it; enabling it is a separate command.
    if (require_enabled && is_smart_disabled(out->smart)) {
        close_handle(out);
        return -6;
    }
    return 0;
}

int cdiskio_read_ata_snapshot(const char *bsd_name, unsigned char *smart_data, unsigned char *thresholds,
                              unsigned char *identify, int *threshold_exceeded) {
    if (!smart_data || !thresholds || !identify || !threshold_exceeded) return -1;

    ata_handle h;
    int err = open_handle(bsd_name, &h, 1);
    if (err != 0) return err;

    int result = 0;
    IOReturn kr = (*h.smart)->SMARTReadData(h.smart, (ATASMARTData *)smart_data);
    if (kr != kIOReturnSuccess) { result = kr; goto done; }

    // An invalid checksum doesn't prevent reading: the caller checks it and shows it.
    kr = (*h.smart)->SMARTReadDataThresholds(h.smart, (ATASMARTDataThresholds *)thresholds);
    if (kr != kIOReturnSuccess) { result = kr; goto done; }

    UInt32 outSize = 0;
    kr = (*h.smart)->GetATAIdentifyData(h.smart, identify, 512, &outSize);
    if (kr != kIOReturnSuccess) { result = kr; goto done; }

    Boolean exceeded = false;
    kr = (*h.smart)->SMARTReturnStatus(h.smart, &exceeded);
    if (kr != kIOReturnSuccess) { result = kr; goto done; }
    *threshold_exceeded = exceeded ? 1 : 0;

done:
    close_handle(&h);
    return result;
}

int cdiskio_read_ata_smart_data(const char *bsd_name, unsigned char *out, int size) {
    if (!out || size < 512) return -1;
    ata_handle h;
    int err = open_handle(bsd_name, &h, 1);
    if (err != 0) return err;
    IOReturn kr = (*h.smart)->SMARTReadData(h.smart, (ATASMARTData *)out);
    close_handle(&h);
    return kr == kIOReturnSuccess ? 0 : kr;
}

int cdiskio_read_ata_smart_thresholds(const char *bsd_name, unsigned char *out, int size) {
    if (!out || size < 512) return -1;
    ata_handle h;
    int err = open_handle(bsd_name, &h, 1);
    if (err != 0) return err;
    IOReturn kr = (*h.smart)->SMARTReadDataThresholds(h.smart, (ATASMARTDataThresholds *)out);
    close_handle(&h);
    return kr == kIOReturnSuccess ? 0 : kr;
}

int cdiskio_read_ata_identify(const char *bsd_name, unsigned char *out, int size) {
    if (!out || size < 512) return -1;
    ata_handle h;
    int err = open_handle(bsd_name, &h, 0);
    if (err != 0) return err;
    UInt32 outSize = 0;
    IOReturn kr = (*h.smart)->GetATAIdentifyData(h.smart, out, (UInt32)size, &outSize);
    close_handle(&h);
    return kr == kIOReturnSuccess ? 0 : kr;
}

int cdiskio_read_ata_smart_status(const char *bsd_name, int *threshold_exceeded) {
    if (!threshold_exceeded) return -1;
    ata_handle h;
    int err = open_handle(bsd_name, &h, 1);
    if (err != 0) return err;
    Boolean exceeded = false;
    IOReturn kr = (*h.smart)->SMARTReturnStatus(h.smart, &exceeded);
    close_handle(&h);
    if (kr != kIOReturnSuccess) return kr;
    *threshold_exceeded = exceeded ? 1 : 0;
    return 0;
}

int cdiskio_enable_ata_smart(const char *bsd_name) {
    ata_handle h;
    int err = open_handle(bsd_name, &h, 0);
    if (err != 0) return err;
    // Enabling only: the boolean is always true.
    IOReturn kr = (*h.smart)->SMARTEnableDisableOperations(h.smart, true);
    close_handle(&h);
    return kr == kIOReturnSuccess ? 0 : kr;
}
