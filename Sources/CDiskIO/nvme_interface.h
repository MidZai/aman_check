// Interoperability definitions for Apple's NVMeSMARTLib.plugin, as documented by the smartmontools project (os_darwin.h).

#ifndef NVME_INTERFACE_H_
#define NVME_INTERFACE_H_

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOTypes.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>

#define kIONVMeSMARTUserClientTypeID        CFUUIDGetConstantUUIDWithBytes(NULL,      \
                                        0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, \
                    0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)

#define kIONVMeSMARTInterfaceID     CFUUIDGetConstantUUIDWithBytes(NULL,                  \
                    0xcc, 0xd1, 0xdb, 0x19, 0xfd, 0x9a, 0x4d, 0xaf, 0xbf, 0x95, \
                    0x12, 0x45, 0x4b, 0x23, 0xa, 0xb6)

typedef struct IONVMeSMARTInterface
{
        IUNKNOWN_C_GUTS;

        UInt16 version;
        UInt16 revision;

        // NVMe smart data, returns nvme_smart_log structure
        IOReturn ( *SMARTReadData )( void *  interface,
                                     void * NVMeSMARTData );

        // NVMe IdentifyData, returns nvme_id_ctrl per namespace
        IOReturn ( *GetIdentifyData )( void *  interface,
                                      void * NVMeIdentifyControllerStruct,
                                      unsigned int ns );
        UInt64  reserved0;
        UInt64  reserved1;

        // NumDWords Number of dwords for log page data, zero based.
        IOReturn ( *GetLogPage )( void *  interface, void * data, unsigned int logPageId, unsigned int numDWords);

        UInt64  reserved2;
        UInt64  reserved3;
        UInt64  reserved4;
        UInt64  reserved5;
        UInt64  reserved6;
        UInt64  reserved7;
        UInt64  reserved8;
        UInt64  reserved9;
        UInt64  reserved10;
        UInt64  reserved11;
        UInt64  reserved12;
        UInt64  reserved13;
        UInt64  reserved14;
        UInt64  reserved15;
        UInt64  reserved16;
        UInt64  reserved17;
        UInt64  reserved18;
        UInt64  reserved19;

} IONVMeSMARTInterface;

#endif /* NVME_INTERFACE_H_ */
