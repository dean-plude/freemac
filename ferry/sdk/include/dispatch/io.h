/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: dispatch I/O (freemac 1.232, Ferry 0.56.0), written for
 * freemac from Apple's public documentation of libdispatch; not Apple's
 * header. A channel's reads and writes run one after another, in the order
 * they were asked for, on threads of the channel's own, and each handler
 * is called on the queue given (ferry/src/objc/dispatch_io.c). Included by
 * <dispatch/dispatch.h>. */
#ifndef _FERRY_DISPATCH_IO_H_
#define _FERRY_DISPATCH_IO_H_
#include <dispatch/dispatch.h>
#include <sys/types.h>
__FERRY_BEGIN

typedef int dispatch_fd_t;
typedef unsigned long dispatch_io_type_t;
#define DISPATCH_IO_STREAM 0
#define DISPATCH_IO_RANDOM 1
typedef unsigned long dispatch_io_close_flags_t;
#define DISPATCH_IO_STOP 0x1
typedef unsigned long dispatch_io_interval_flags_t;
#define DISPATCH_IO_STRICT_INTERVAL 0x1

#if __BLOCKS__
typedef void (^dispatch_io_handler_t)(bool done, dispatch_data_t data, int error);

void dispatch_read(dispatch_fd_t fd, size_t length, dispatch_queue_t queue,
                   void (^handler)(dispatch_data_t data, int error));
void dispatch_write(dispatch_fd_t fd, dispatch_data_t data, dispatch_queue_t queue,
                    void (^handler)(dispatch_data_t data, int error));
DISPATCH_RETURNS_RETAINED dispatch_io_t dispatch_io_create(dispatch_io_type_t type, dispatch_fd_t fd,
                                                           dispatch_queue_t queue, void (^cleanup_handler)(int error));
DISPATCH_RETURNS_RETAINED dispatch_io_t dispatch_io_create_with_path(dispatch_io_type_t type, const char *path,
                                                                     int oflag, mode_t mode, dispatch_queue_t queue,
                                                                     void (^cleanup_handler)(int error));
DISPATCH_RETURNS_RETAINED dispatch_io_t dispatch_io_create_with_io(dispatch_io_type_t type, dispatch_io_t io,
                                                                   dispatch_queue_t queue,
                                                                   void (^cleanup_handler)(int error));
void dispatch_io_read(dispatch_io_t channel, off_t offset, size_t length, dispatch_queue_t queue,
                      dispatch_io_handler_t io_handler);
void dispatch_io_write(dispatch_io_t channel, off_t offset, dispatch_data_t data, dispatch_queue_t queue,
                       dispatch_io_handler_t io_handler);
void dispatch_io_barrier(dispatch_io_t channel, dispatch_block_t barrier);
#endif
void dispatch_io_close(dispatch_io_t channel, dispatch_io_close_flags_t flags);
dispatch_fd_t dispatch_io_get_descriptor(dispatch_io_t channel);
void dispatch_io_set_high_water(dispatch_io_t channel, size_t high_water);
void dispatch_io_set_low_water(dispatch_io_t channel, size_t low_water);
void dispatch_io_set_interval(dispatch_io_t channel, uint64_t interval, dispatch_io_interval_flags_t flags);

__FERRY_END
#endif
