/* Minimal stand-in for <linux/fs.h>: the Static Linux SDK's musl sysroot ships
   no kernel headers, and swift-testing only needs FICLONE from it. */
#ifndef SWT_SHIM_LINUX_FS_H
#define SWT_SHIM_LINUX_FS_H
#include <sys/ioctl.h>
#ifndef FICLONE
#define FICLONE _IOW(0x94, 9, int)
#endif
#endif
