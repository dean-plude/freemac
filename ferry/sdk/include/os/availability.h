/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the API_AVAILABLE family of markers (freemac 1.221, Ferry
 * 0.45.0). They mark nothing here, since everything Ferry's SDK declares
 * is there to be called. Written for freemac; not Apple's header. */
#ifndef _FERRY_OS_AVAILABILITY_H_
#define _FERRY_OS_AVAILABILITY_H_
#define API_AVAILABLE(...)
#define API_AVAILABLE_BEGIN(...)
#define API_AVAILABLE_END
#define API_UNAVAILABLE(...)
#define API_UNAVAILABLE_BEGIN(...)
#define API_UNAVAILABLE_END
#define API_DEPRECATED(...)
#define API_DEPRECATED_BEGIN(...)
#define API_DEPRECATED_END
#define API_DEPRECATED_WITH_REPLACEMENT(...)
#define API_DEPRECATED_WITH_REPLACEMENT_BEGIN(...)
#define API_DEPRECATED_WITH_REPLACEMENT_END
#define API_OBSOLETE(...)
#define SPI_AVAILABLE(...)
#define SPI_DEPRECATED(...)
#define SPI_DEPRECATED_WITH_REPLACEMENT(...)
#endif
