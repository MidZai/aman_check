#ifndef CDISKIO_H_
#define CDISKIO_H_

// None of these functions changes the drive's data. Only cdiskio_enable_ata_smart changes
// a setting: it turns S.M.A.R.T. on (never off).
// All of them return 0 on success, otherwise a negative code (-1 to -6) or an IOReturn.

// NVMe. out_buffer: 512 bytes for the SMART log, 4096 for Identify.
int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size);
int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size);
// SMART log (512 bytes) and Identify (4096 bytes), opening the driver only once.
int cdiskio_read_nvme_all(const char *bsd_name, unsigned char *smart_buffer, unsigned char *identify_buffer);

// ATA / SATA / PCIe AHCI. 512-byte buffers. -6: S.M.A.R.T. disabled.
int cdiskio_read_ata_smart_data(const char *bsd_name, unsigned char *out, int size);
int cdiskio_read_ata_smart_thresholds(const char *bsd_name, unsigned char *out, int size);
int cdiskio_read_ata_identify(const char *bsd_name, unsigned char *out, int size);   // even if S.M.A.R.T. is disabled
int cdiskio_read_ata_smart_status(const char *bsd_name, int *threshold_exceeded);          // 0 or 1
// The four reads above, opening the driver only once.
int cdiskio_read_ata_snapshot(const char *bsd_name, unsigned char *smart_data, unsigned char *thresholds,
                              unsigned char *identify, int *threshold_exceeded);

// Turns S.M.A.R.T. on (SMARTEnableDisableOperations(true)) and nothing else.
int cdiskio_enable_ata_smart(const char *bsd_name);

#endif /* CDISKIO_H_ */
