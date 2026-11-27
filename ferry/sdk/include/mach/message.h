/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Mach messages, as Apple's public mach_msg documentation describes them
 * (freemac 1.224, Ferry 0.48.0; messages themselves freemac 1.265, Ferry
 * 0.88.0): the header, the descriptors a complex message carries, the
 * trailers and mach_msg's options and results. */
#ifndef _FERRY_MACH_MESSAGE_H_
#define _FERRY_MACH_MESSAGE_H_
#include <_ferry.h>
#include <stdint.h>
__FERRY_BEGIN
typedef struct {
    unsigned int val[8];
} audit_token_t;
typedef struct {
    unsigned int val[2];
} security_token_t;

typedef unsigned int mach_msg_bits_t;
typedef unsigned int mach_msg_size_t;
typedef int mach_msg_id_t;
typedef unsigned int mach_msg_timeout_t;
typedef int mach_msg_option_t;
typedef int mach_msg_return_t;
typedef unsigned int mach_msg_type_name_t;
typedef unsigned int mach_msg_descriptor_type_t;
typedef unsigned int mach_msg_copy_options_t;
typedef unsigned int mach_msg_trailer_type_t;
typedef unsigned int mach_msg_trailer_size_t;
typedef unsigned int mach_port_seqno_t;
typedef uint64_t mach_port_context_t;

typedef struct {
    mach_msg_bits_t msgh_bits;
    mach_msg_size_t msgh_size;
    unsigned int msgh_remote_port;
    unsigned int msgh_local_port;
    unsigned int msgh_voucher_port;
    mach_msg_id_t msgh_id;
} mach_msg_header_t;

typedef struct {
    mach_msg_size_t msgh_descriptor_count;
} mach_msg_body_t;

#define MACH_MSGH_BITS_COMPLEX 0x80000000u
#define MACH_MSGH_BITS_REMOTE_MASK 0x0000001fu
#define MACH_MSGH_BITS_LOCAL_MASK 0x00001f00u
#define MACH_MSGH_BITS(remote, local) ((remote) | ((local) << 8))
#define MACH_MSGH_BITS_SET(remote, local, voucher, other) \
    (MACH_MSGH_BITS(remote, local) | ((voucher) << 16) | ((other) & MACH_MSGH_BITS_COMPLEX))
#define MACH_MSGH_BITS_REMOTE(bits) ((bits) & MACH_MSGH_BITS_REMOTE_MASK)
#define MACH_MSGH_BITS_LOCAL(bits) (((bits) & MACH_MSGH_BITS_LOCAL_MASK) >> 8)

#define MACH_MSG_TYPE_MOVE_RECEIVE 16
#define MACH_MSG_TYPE_MOVE_SEND 17
#define MACH_MSG_TYPE_MOVE_SEND_ONCE 18
#define MACH_MSG_TYPE_COPY_SEND 19
#define MACH_MSG_TYPE_MAKE_SEND 20
#define MACH_MSG_TYPE_MAKE_SEND_ONCE 21
#define MACH_MSG_TYPE_COPY_RECEIVE 22
#define MACH_MSG_TYPE_PORT_RECEIVE MACH_MSG_TYPE_MOVE_RECEIVE
#define MACH_MSG_TYPE_PORT_SEND MACH_MSG_TYPE_MOVE_SEND
#define MACH_MSG_TYPE_PORT_SEND_ONCE MACH_MSG_TYPE_MOVE_SEND_ONCE

#define MACH_MSG_PORT_DESCRIPTOR 0
#define MACH_MSG_OOL_DESCRIPTOR 1
#define MACH_MSG_OOL_PORTS_DESCRIPTOR 2
#define MACH_MSG_OOL_VOLATILE_DESCRIPTOR 3
#define MACH_MSG_GUARDED_PORT_DESCRIPTOR 4

#define MACH_MSG_PHYSICAL_COPY 0
#define MACH_MSG_VIRTUAL_COPY 1

#pragma pack(push, 4)
typedef struct {
    unsigned int name;
    mach_msg_size_t pad1;
    unsigned int pad2 : 16;
    mach_msg_type_name_t disposition : 8;
    mach_msg_descriptor_type_t type : 8;
} mach_msg_port_descriptor_t;

typedef struct {
    void *address;
    unsigned int deallocate : 8;
    mach_msg_copy_options_t copy : 8;
    unsigned int pad1 : 8;
    mach_msg_descriptor_type_t type : 8;
    mach_msg_size_t size;
} mach_msg_ool_descriptor_t;

typedef struct {
    void *address;
    unsigned int deallocate : 8;
    mach_msg_copy_options_t copy : 8;
    mach_msg_type_name_t disposition : 8;
    mach_msg_descriptor_type_t type : 8;
    mach_msg_size_t count;
} mach_msg_ool_ports_descriptor_t;

typedef struct {
    unsigned int pad1;
    mach_msg_size_t pad2;
    unsigned int pad3 : 24;
    mach_msg_descriptor_type_t type : 8;
} mach_msg_type_descriptor_t;

typedef union {
    mach_msg_port_descriptor_t port;
    mach_msg_ool_descriptor_t out_of_line;
    mach_msg_ool_ports_descriptor_t ool_ports;
    mach_msg_type_descriptor_t type;
} mach_msg_descriptor_t;

typedef struct {
    mach_msg_trailer_type_t msgh_trailer_type;
    mach_msg_trailer_size_t msgh_trailer_size;
} mach_msg_trailer_t;

typedef struct {
    mach_msg_trailer_type_t msgh_trailer_type;
    mach_msg_trailer_size_t msgh_trailer_size;
    mach_port_seqno_t msgh_seqno;
    security_token_t msgh_sender;
} mach_msg_security_trailer_t;

typedef struct {
    mach_msg_trailer_type_t msgh_trailer_type;
    mach_msg_trailer_size_t msgh_trailer_size;
    mach_port_seqno_t msgh_seqno;
    security_token_t msgh_sender;
    audit_token_t msgh_audit;
} mach_msg_audit_trailer_t;

typedef struct {
    mach_msg_trailer_type_t msgh_trailer_type;
    mach_msg_trailer_size_t msgh_trailer_size;
    mach_port_seqno_t msgh_seqno;
    security_token_t msgh_sender;
    audit_token_t msgh_audit;
    mach_port_context_t msgh_context;
} mach_msg_context_trailer_t;

typedef struct {
    mach_msg_trailer_type_t msgh_trailer_type;
    mach_msg_trailer_size_t msgh_trailer_size;
    mach_port_seqno_t msgh_seqno;
    security_token_t msgh_sender;
    audit_token_t msgh_audit;
    mach_port_context_t msgh_context;
    int msgh_ad;
    unsigned int msgh_labels;
} mach_msg_mac_trailer_t;
typedef mach_msg_mac_trailer_t mach_msg_max_trailer_t;
#pragma pack(pop)

#define MAX_TRAILER_SIZE ((mach_msg_size_t)sizeof(mach_msg_max_trailer_t))
#define MACH_MSG_TRAILER_FORMAT_0 0
#define MACH_RCV_TRAILER_NULL 0
#define MACH_RCV_TRAILER_SEQNO 1
#define MACH_RCV_TRAILER_SENDER 2
#define MACH_RCV_TRAILER_AUDIT 3
#define MACH_RCV_TRAILER_CTX 4
#define MACH_RCV_TRAILER_AV 7
#define MACH_RCV_TRAILER_LABELS 8
#define MACH_RCV_TRAILER_TYPE(x) (((x) & 0xf) << 28)
#define MACH_RCV_TRAILER_ELEMENTS(x) (((x) & 0xf) << 24)

#define MACH_MSG_OPTION_NONE 0x00000000
#define MACH_SEND_MSG 0x00000001
#define MACH_RCV_MSG 0x00000002
#define MACH_RCV_LARGE 0x00000004
#define MACH_SEND_TIMEOUT 0x00000010
#define MACH_SEND_INTERRUPT 0x00000040
#define MACH_RCV_TIMEOUT 0x00000100
#define MACH_RCV_INTERRUPT 0x00000400
#define MACH_MSG_TIMEOUT_NONE ((mach_msg_timeout_t)0)

#define MACH_MSG_SUCCESS 0x00000000
#define MACH_SEND_INVALID_DATA 0x10000002
#define MACH_SEND_INVALID_DEST 0x10000003
#define MACH_SEND_TIMED_OUT 0x10000004
#define MACH_SEND_MSG_TOO_SMALL 0x10000008
#define MACH_SEND_INVALID_REPLY 0x10000009
#define MACH_SEND_INVALID_RIGHT 0x1000000a
#define MACH_SEND_INVALID_MEMORY 0x1000000c
#define MACH_SEND_INVALID_TYPE 0x1000000f
#define MACH_SEND_INVALID_HEADER 0x10000010
#define MACH_RCV_INVALID_NAME 0x10004002
#define MACH_RCV_TIMED_OUT 0x10004003
#define MACH_RCV_TOO_LARGE 0x10004004
#define MACH_RCV_INTERRUPTED 0x10004005
#define MACH_RCV_PORT_CHANGED 0x10004006
#define MACH_RCV_PORT_DIED 0x10004009

mach_msg_return_t mach_msg(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size,
                           mach_msg_size_t rcv_size, unsigned int rcv_name, mach_msg_timeout_t timeout,
                           unsigned int notify);
mach_msg_return_t mach_msg_overwrite(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size,
                                     mach_msg_size_t rcv_size, unsigned int rcv_name, mach_msg_timeout_t timeout,
                                     unsigned int notify, mach_msg_header_t *rcv_msg, mach_msg_size_t rcv_limit);
mach_msg_return_t mach_msg_send(mach_msg_header_t *msg);
mach_msg_return_t mach_msg_receive(mach_msg_header_t *msg);
void mach_msg_destroy(mach_msg_header_t *msg);
__FERRY_END
#endif
