/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Mach port names and rights (freemac 1.232, Ferry 0.56.0; the port calls
 * freemac 1.265, Ferry 0.88.0), from Apple's public mach_port reference
 * pages: rights, types, notifications, attributes and the calls on them. */
#ifndef _FERRY_MACH_PORT_H_
#define _FERRY_MACH_PORT_H_
#include <mach/mach.h>
#include <mach/message.h>
__FERRY_BEGIN
#define MACH_PORT_DEAD ((mach_port_t)~0)
#define MACH_PORT_VALID(name) ((name) != MACH_PORT_NULL && (name) != MACH_PORT_DEAD)

typedef natural_t mach_port_right_t;
typedef natural_t mach_port_type_t;
typedef natural_t mach_port_urefs_t;
typedef int mach_port_delta_t;
typedef natural_t mach_port_mscount_t;
typedef natural_t mach_port_msgcount_t;
typedef natural_t mach_port_rights_t;
typedef int mach_port_flavor_t;
typedef integer_t *mach_port_info_t;
typedef mach_port_t *mach_port_array_t;
typedef mach_port_name_t *mach_port_name_array_t;
typedef mach_port_type_t *mach_port_type_array_t;
typedef int mach_msg_id_notify_t;

#define MACH_PORT_RIGHT_SEND 0
#define MACH_PORT_RIGHT_RECEIVE 1
#define MACH_PORT_RIGHT_SEND_ONCE 2
#define MACH_PORT_RIGHT_PORT_SET 3
#define MACH_PORT_RIGHT_DEAD_NAME 4

#define MACH_PORT_TYPE(right) ((mach_port_type_t)(1u << ((right) + 16)))
#define MACH_PORT_TYPE_NONE 0u
#define MACH_PORT_TYPE_SEND MACH_PORT_TYPE(MACH_PORT_RIGHT_SEND)
#define MACH_PORT_TYPE_RECEIVE MACH_PORT_TYPE(MACH_PORT_RIGHT_RECEIVE)
#define MACH_PORT_TYPE_SEND_ONCE MACH_PORT_TYPE(MACH_PORT_RIGHT_SEND_ONCE)
#define MACH_PORT_TYPE_PORT_SET MACH_PORT_TYPE(MACH_PORT_RIGHT_PORT_SET)
#define MACH_PORT_TYPE_DEAD_NAME MACH_PORT_TYPE(MACH_PORT_RIGHT_DEAD_NAME)
#define MACH_PORT_TYPE_SEND_RECEIVE (MACH_PORT_TYPE_SEND | MACH_PORT_TYPE_RECEIVE)
#define MACH_PORT_TYPE_DNREQUEST 0x80000000u

#define MACH_NOTIFY_PORT_DELETED 65
#define MACH_NOTIFY_SEND_POSSIBLE 66
#define MACH_NOTIFY_PORT_DESTROYED 69
#define MACH_NOTIFY_NO_SENDERS 70
#define MACH_NOTIFY_SEND_ONCE 71
#define MACH_NOTIFY_DEAD_NAME 72

#define MACH_PORT_LIMITS_INFO 1
#define MACH_PORT_RECEIVE_STATUS 2
#define MACH_PORT_DNREQUESTS_SIZE 3
#define MACH_PORT_QLIMIT_DEFAULT 5
#define MACH_PORT_QLIMIT_MAX 1024

typedef struct mach_port_limits {
    mach_port_msgcount_t mpl_qlimit;
} mach_port_limits_t;
#define MACH_PORT_LIMITS_INFO_COUNT 1

typedef struct mach_port_status {
    mach_port_name_t mps_pset;
    mach_port_seqno_t mps_seqno;
    mach_port_mscount_t mps_mscount;
    mach_port_msgcount_t mps_qlimit;
    mach_port_msgcount_t mps_msgcount;
    mach_port_rights_t mps_sorights;
    int mps_srights;
    int mps_pdrequest;
    int mps_nsrequest;
    natural_t mps_flags;
} mach_port_status_t;
#define MACH_PORT_RECEIVE_STATUS_COUNT 10

#define MPO_CONTEXT_AS_GUARD 0x01
#define MPO_QLIMIT 0x02
#define MPO_TEMPOWNER 0x04
#define MPO_IMPORTANCE_RECEIVER 0x08
#define MPO_INSERT_SEND_RIGHT 0x10
#define MPO_STRICT 0x20

typedef struct mach_port_options {
    uint32_t flags;
    mach_port_limits_t mpl;
    uint64_t reserved[2];
} mach_port_options_t;
typedef mach_port_options_t *mach_port_options_ptr_t;

#define KERN_NOT_RECEIVER 7
#define KERN_ALREADY_IN_SET 11
#define KERN_NOT_IN_SET 12
#define KERN_NAME_EXISTS 13
#define KERN_INVALID_NAME 15
#define KERN_INVALID_TASK 16
#define KERN_INVALID_RIGHT 17
#define KERN_INVALID_VALUE 18
#define KERN_UREFS_OVERFLOW 19
#define KERN_INVALID_CAPABILITY 20
#define KERN_RIGHT_EXISTS 21

kern_return_t mach_port_allocate(ipc_space_t task, mach_port_right_t right, mach_port_name_t *name);
kern_return_t mach_port_construct(ipc_space_t task, mach_port_options_ptr_t options, mach_port_context_t context,
                                  mach_port_name_t *name);
kern_return_t mach_port_destruct(ipc_space_t task, mach_port_name_t name, mach_port_delta_t srdelta,
                                 mach_port_context_t guard);
kern_return_t mach_port_destroy(ipc_space_t task, mach_port_name_t name);
kern_return_t mach_port_mod_refs(ipc_space_t task, mach_port_name_t name, mach_port_right_t right,
                                 mach_port_delta_t delta);
kern_return_t mach_port_get_refs(ipc_space_t task, mach_port_name_t name, mach_port_right_t right,
                                 mach_port_urefs_t *refs);
kern_return_t mach_port_insert_right(ipc_space_t task, mach_port_name_t name, mach_port_t poly,
                                     mach_msg_type_name_t type);
kern_return_t mach_port_extract_right(ipc_space_t task, mach_port_name_t name, mach_msg_type_name_t type,
                                      mach_port_t *poly, mach_msg_type_name_t *poly_type);
kern_return_t mach_port_type(ipc_space_t task, mach_port_name_t name, mach_port_type_t *type);
kern_return_t mach_port_names(ipc_space_t task, mach_port_name_array_t *names, mach_msg_type_number_t *ncount,
                              mach_port_type_array_t *types, mach_msg_type_number_t *tcount);
kern_return_t mach_port_move_member(ipc_space_t task, mach_port_name_t member, mach_port_name_t after);
kern_return_t mach_port_insert_member(ipc_space_t task, mach_port_name_t name, mach_port_name_t pset);
kern_return_t mach_port_extract_member(ipc_space_t task, mach_port_name_t name, mach_port_name_t pset);
kern_return_t mach_port_request_notification(ipc_space_t task, mach_port_name_t name, mach_msg_id_notify_t id,
                                             mach_port_mscount_t sync, mach_port_t notify,
                                             mach_msg_type_name_t notify_type, mach_port_t *previous);
kern_return_t mach_port_get_attributes(ipc_space_t task, mach_port_name_t name, mach_port_flavor_t flavor,
                                       mach_port_info_t info, mach_msg_type_number_t *count);
kern_return_t mach_port_set_attributes(ipc_space_t task, mach_port_name_t name, mach_port_flavor_t flavor,
                                       mach_port_info_t info, mach_msg_type_number_t count);
kern_return_t mach_port_set_context(ipc_space_t task, mach_port_name_t name, mach_port_context_t context);
kern_return_t mach_port_get_context(ipc_space_t task, mach_port_name_t name, mach_port_context_t *context);
kern_return_t mach_port_set_mscount(ipc_space_t task, mach_port_name_t name, mach_port_mscount_t mscount);
kern_return_t mach_port_get_srights(ipc_space_t task, mach_port_name_t name, mach_port_rights_t *srights);
mach_port_t mach_reply_port(void);
mach_port_t mig_get_reply_port(void);
void mig_dealloc_reply_port(mach_port_t port);

/* the notifications a port is sent */
typedef struct {
    mach_msg_header_t not_header;
    uint64_t NDR;
    mach_port_mscount_t not_count;
    mach_msg_trailer_t trailer;
} mach_no_senders_notification_t;
typedef struct {
    mach_msg_header_t not_header;
    uint64_t NDR;
    mach_port_name_t not_port;
    mach_msg_trailer_t trailer;
} mach_dead_name_notification_t;
typedef struct {
    mach_msg_header_t not_header;
    mach_msg_trailer_t trailer;
} mach_send_once_notification_t;
__FERRY_END
#endif
