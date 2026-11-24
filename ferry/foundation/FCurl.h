/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of this system's libcurl that Ferry's Foundation uses for URL
 * loading (NSURLSession.m). libcurl is a Linux library and Foundation is Mac
 * code, but both use the System V calling convention, so Foundation can
 * call it directly. Its calls are looked up by name through
 * ferry_network_symbol() (src/host.c) the first time a program loads a URL
 * from the network, so a program that never does doesn't open libcurl.
 *
 * Written here from libcurl's published API documentation (the Mac build
 * can't include Linux headers): only calls, option numbers and structures
 * that are part of libcurl's stable public API.
 */
#ifndef FERRY_FOUNDATION_CURL_H
#define FERRY_FOUNDATION_CURL_H
#include <stddef.h>
#include <stdint.h>

typedef void CURL;
typedef void CURLM;
typedef int CURLcode;
typedef int CURLMcode;
typedef int CURLoption;
typedef int CURLMoption;
typedef int CURLINFO;
typedef int curl_socket_t;
typedef int64_t curl_off_t;
struct curl_slist {
    char *data;
    struct curl_slist *next;
};
typedef struct {
    int msg; /* CURLMSG_DONE when a transfer ended */
    CURL *easy_handle;
    union {
        void *whatever;
        CURLcode result;
    } data;
} CURLMsg;

typedef size_t (*curl_write_callback)(char *ptr, size_t size, size_t nmemb, void *userdata);
typedef int (*curl_xferinfo_callback)(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal,
                                      curl_off_t ulnow);
typedef int (*curl_socket_callback)(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);
typedef int (*curl_multi_timer_callback)(CURLM *multi, long timeout_ms, void *userp);

/* Option numbers: a type base (long 0, pointer 10000, function 20000,
 * curl_off_t 30000) plus the option's own number. */
enum {
    CURLOPT_WRITEDATA = 10001,
    CURLOPT_URL = 10002,
    CURLOPT_ERRORBUFFER = 10010,
    CURLOPT_WRITEFUNCTION = 20011,
    CURLOPT_TIMEOUT = 13,
    CURLOPT_POSTFIELDS = 10015,
    CURLOPT_USERAGENT = 10018,
    CURLOPT_HTTPHEADER = 10023,
    CURLOPT_HEADERDATA = 10029,
    CURLOPT_CUSTOMREQUEST = 10036,
    CURLOPT_NOPROGRESS = 43,
    CURLOPT_NOBODY = 44,
    CURLOPT_POST = 47,
    CURLOPT_FOLLOWLOCATION = 52,
    CURLOPT_XFERINFODATA = 10057,
    CURLOPT_MAXREDIRS = 68,
    CURLOPT_CONNECTTIMEOUT = 78,
    CURLOPT_HEADERFUNCTION = 20079,
    CURLOPT_HTTPGET = 80,
    CURLOPT_NOSIGNAL = 99,
    CURLOPT_ACCEPT_ENCODING = 10102,
    CURLOPT_PRIVATE = 10103,
    CURLOPT_POSTFIELDSIZE_LARGE = 30120,
    CURLOPT_TIMEOUT_MS = 155,
    CURLOPT_CONNECTTIMEOUT_MS = 156,
    CURLOPT_XFERINFOFUNCTION = 20219,
    CURLOPT_PROTOCOLS_STR = 10318,
    CURLOPT_REDIR_PROTOCOLS_STR = 10319,
};
enum {
    CURLMOPT_SOCKETFUNCTION = 20001,
    CURLMOPT_SOCKETDATA = 10002,
    CURLMOPT_TIMERFUNCTION = 20004,
    CURLMOPT_TIMERDATA = 10005,
};
enum {
    CURLINFO_EFFECTIVE_URL = 0x100000 + 1,
    CURLINFO_RESPONSE_CODE = 0x200000 + 2,
    CURLINFO_CONTENT_LENGTH_DOWNLOAD_T = 0x600000 + 15,
};
enum {
    CURLE_OK = 0,
    CURLE_UNSUPPORTED_PROTOCOL = 1,
    CURLE_URL_MALFORMAT = 3,
    CURLE_COULDNT_RESOLVE_PROXY = 5,
    CURLE_COULDNT_RESOLVE_HOST = 6,
    CURLE_COULDNT_CONNECT = 7,
    CURLE_WEIRD_SERVER_REPLY = 8,
    CURLE_PARTIAL_FILE = 18,
    CURLE_WRITE_ERROR = 23,
    CURLE_OUT_OF_MEMORY = 27,
    CURLE_OPERATION_TIMEDOUT = 28,
    CURLE_SSL_CONNECT_ERROR = 35,
    CURLE_FILE_COULDNT_READ_FILE = 37,
    CURLE_ABORTED_BY_CALLBACK = 42,
    CURLE_TOO_MANY_REDIRECTS = 47,
    CURLE_GOT_NOTHING = 52,
    CURLE_SEND_ERROR = 55,
    CURLE_RECV_ERROR = 56,
    CURLE_SSL_CERTPROBLEM = 58,
    CURLE_PEER_FAILED_VERIFICATION = 60,
    CURLE_BAD_CONTENT_ENCODING = 61,
    CURLE_FILESIZE_EXCEEDED = 63,
    CURLE_SSL_CACERT_BADFILE = 77,
};
enum { CURLMSG_DONE = 1 };
enum { CURL_GLOBAL_DEFAULT = 3 };
#define CURL_SOCKET_TIMEOUT (-1)
enum { CURL_POLL_NONE = 0, CURL_POLL_IN = 1, CURL_POLL_OUT = 2, CURL_POLL_INOUT = 3, CURL_POLL_REMOVE = 4 };
enum { CURL_CSELECT_IN = 1, CURL_CSELECT_OUT = 2, CURL_CSELECT_ERR = 4 };
enum { CURLPAUSE_ALL = 5, CURLPAUSE_CONT = 0 };

/* The calls, as pointers filled in by name (NSURLSession.m). */
struct ferry_curl {
    CURLcode (*global_init)(long flags);
    CURL *(*easy_init)(void);
    CURLcode (*easy_setopt)(CURL *curl, CURLoption option, ...);
    CURLcode (*easy_getinfo)(CURL *curl, CURLINFO info, ...);
    CURLcode (*easy_pause)(CURL *curl, int bitmask);
    void (*easy_cleanup)(CURL *curl);
    const char *(*easy_strerror)(CURLcode code);
    struct curl_slist *(*slist_append)(struct curl_slist *list, const char *string);
    void (*slist_free_all)(struct curl_slist *list);
    CURLM *(*multi_init)(void);
    CURLMcode (*multi_setopt)(CURLM *multi, CURLMoption option, ...);
    CURLMcode (*multi_add_handle)(CURLM *multi, CURL *curl);
    CURLMcode (*multi_remove_handle)(CURLM *multi, CURL *curl);
    CURLMcode (*multi_socket_action)(CURLM *multi, curl_socket_t s, int ev_bitmask, int *running);
    CURLMsg *(*multi_info_read)(CURLM *multi, int *msgs_in_queue);
};

#endif
