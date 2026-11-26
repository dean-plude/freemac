/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Screen capture's X11 back end (freemac 1.238, Ferry 0.62.0): see
 * ACapture.h. This system's Xlib and its extensions are opened when a
 * program first captures (ferry_capture_symbol, src/host.c), and each
 * stream has its own connection to the X server, used on its capture
 * queue only; listing uses one more, behind a lock.
 *
 * The screen is the root window, read with MIT-SHM where the server has
 * it (XShmGetImage into shared memory) and XGetImage otherwise. A window
 * is read by itself: with the Composite extension it is redirected (the
 * server keeps its pixels even where other windows cover it) and read with
 * XGetImage. The windows are the window manager's (_NET_CLIENT_LIST_STACKING,
 * or _NET_CLIENT_LIST), or with none the root's mapped children that have
 * a name or a process; titles from _NET_WM_NAME or WM_NAME, processes from
 * _NET_WM_PID, owners from WM_CLASS. The pointer is XFixes' cursor image.
 * Errors the server sends about these connections (a window that went
 * away) are noted and not fatal.
 *
 * Xlib's calls and structures are written here from Xlib's, MIT-SHM's,
 * XFixes' and Composite's published documentation, since the Mac build
 * can't include Linux headers; only the documented members, in their
 * documented order. Xlib is a Linux library and AppKit is Mac code, but
 * both use the System V calling convention. */
#import "ACapture.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *ferry_capture_symbol(const char *name); /* src/host.c */

typedef struct _XDisplay Display;
typedef unsigned long XID, Window, Drawable, Atom, Pixmap;
typedef struct Visual Visual;
typedef int Bool;
typedef int Status;

typedef struct _XImage {
    int width, height;
    int xoffset;
    int format;
    char *data;
    int byte_order;
    int bitmap_unit;
    int bitmap_bit_order;
    int bitmap_pad;
    int depth;
    int bytes_per_line;
    int bits_per_pixel;
    unsigned long red_mask, green_mask, blue_mask;
    char *obdata;
    void *funcs[6];
} XImage;

typedef struct {
    int x, y;
    int width, height;
    int border_width;
    int depth;
    Visual *visual;
    Window root;
    int c_class;
    int bit_gravity;
    int win_gravity;
    int backing_store;
    unsigned long backing_planes;
    unsigned long backing_pixel;
    Bool save_under;
    unsigned long colormap;
    Bool map_installed;
    int map_state;
    long all_event_masks;
    long your_event_mask;
    long do_not_propagate_mask;
    Bool override_redirect;
    void *screen;
} XWindowAttributes;

typedef struct {
    int type;
    Display *display;
    XID resourceid;
    unsigned long serial;
    unsigned char error_code;
    unsigned char request_code;
    unsigned char minor_code;
} XErrorEvent;

typedef struct {
    unsigned long shmseg;
    int shmid;
    char *shmaddr;
    Bool readOnly;
} XShmSegmentInfo;

typedef struct {
    short x, y;
    unsigned short width, height;
    unsigned short xhot, yhot;
    unsigned long cursor_serial;
    unsigned long *pixels;
} XFixesCursorImage;

enum { ZPixmap = 2, IsViewable = 2, InputOutput = 1, CompositeRedirectAutomatic = 0 };
enum { XA_CARDINAL = 6, XA_STRING = 31, XA_WINDOW = 33, XA_WM_NAME = 39, XA_WM_CLASS = 67 };
#define AllPlanes (~0UL)
#define AnyPropertyType 0UL
enum { IPC_PRIVATE = 0, IPC_CREAT = 01000, IPC_RMID = 0 };

typedef int (*XErrorHandler)(Display *, XErrorEvent *);

static struct {
    Display *(*XOpenDisplay)(const char *);
    int (*XCloseDisplay)(Display *);
    Window (*XDefaultRootWindow)(Display *);
    int (*XDefaultScreen)(Display *);
    int (*XDisplayWidth)(Display *, int);
    int (*XDisplayHeight)(Display *, int);
    Visual *(*XDefaultVisual)(Display *, int);
    int (*XDefaultDepth)(Display *, int);
    Status (*XGetWindowAttributes)(Display *, Window, XWindowAttributes *);
    XImage *(*XGetImage)(Display *, Drawable, int, int, unsigned, unsigned, unsigned long, int);
    int (*XDestroyImage)(XImage *);
    int (*XGetWindowProperty)(Display *, Window, Atom, long, long, Bool, Atom, Atom *, int *, unsigned long *,
                              unsigned long *, unsigned char **);
    Atom (*XInternAtom)(Display *, const char *, Bool);
    int (*XFree)(void *);
    Status (*XQueryTree)(Display *, Window, Window *, Window *, Window **, unsigned *);
    Bool (*XTranslateCoordinates)(Display *, Window, Window, int, int, int *, int *, Window *);
    XErrorHandler (*XSetErrorHandler)(XErrorHandler);
    int (*XSync)(Display *, Bool);
    Bool (*XShmQueryExtension)(Display *);
    XImage *(*XShmCreateImage)(Display *, Visual *, unsigned, int, char *, XShmSegmentInfo *, unsigned, unsigned);
    Bool (*XShmAttach)(Display *, XShmSegmentInfo *);
    Bool (*XShmDetach)(Display *, XShmSegmentInfo *);
    Bool (*XShmGetImage)(Display *, Drawable, XImage *, int, int, unsigned long);
    Bool (*XFixesQueryExtension)(Display *, int *, int *);
    XFixesCursorImage *(*XFixesGetCursorImage)(Display *);
    Bool (*XCompositeQueryExtension)(Display *, int *, int *);
    void (*XCompositeRedirectWindow)(Display *, Window, int);
    int (*shmget)(int, size_t, int);
    void *(*shmat)(int, const void *, int);
    int (*shmdt)(const void *);
    int (*shmctl)(int, int, void *);
} x;

static BOOL x_loaded;

static void load_xlib(void)
{
#define X(name) *(void **)&x.name = ferry_capture_symbol(#name)
    X(XOpenDisplay);
    X(XCloseDisplay);
    X(XDefaultRootWindow);
    X(XDefaultScreen);
    X(XDisplayWidth);
    X(XDisplayHeight);
    X(XDefaultVisual);
    X(XDefaultDepth);
    X(XGetWindowAttributes);
    X(XGetImage);
    X(XDestroyImage);
    X(XGetWindowProperty);
    X(XInternAtom);
    X(XFree);
    X(XQueryTree);
    X(XTranslateCoordinates);
    X(XSetErrorHandler);
    X(XSync);
    X(XShmQueryExtension);
    X(XShmCreateImage);
    X(XShmAttach);
    X(XShmDetach);
    X(XShmGetImage);
    X(XFixesQueryExtension);
    X(XFixesGetCursorImage);
    X(XCompositeQueryExtension);
    X(XCompositeRedirectWindow);
    X(shmget);
    X(shmat);
    X(shmdt);
    X(shmctl);
#undef X
    x_loaded = x.XOpenDisplay && x.XCloseDisplay && x.XDefaultRootWindow && x.XGetImage && x.XDestroyImage &&
               x.XGetWindowAttributes && x.XGetWindowProperty && x.XInternAtom && x.XFree && x.XQueryTree &&
               x.XTranslateCoordinates && x.XSetErrorHandler && x.XSync && x.XDisplayWidth && x.XDisplayHeight &&
               x.XDefaultScreen;
}

/* ---- errors: noted for Ferry's own connections, passed on for anyone else's ------------------- */

#define MAX_OWN 64
static pthread_mutex_t own_lock = PTHREAD_MUTEX_INITIALIZER;
static Display *own_displays[MAX_OWN];
static int own_errors[MAX_OWN];
static XErrorHandler previous_handler;

static int on_error(Display *d, XErrorEvent *e)
{
    pthread_mutex_lock(&own_lock);
    BOOL ours = NO;
    for (int i = 0; i < MAX_OWN && !ours; i++)
        if (own_displays[i] == d) {
            own_errors[i]++;
            ours = YES;
        }
    XErrorHandler before = previous_handler;
    pthread_mutex_unlock(&own_lock);
    if (ours)
        return 0;
    return before ? before(d, e) : 0;
}

/* how many errors the server has sent about one of Ferry's connections; each is used on one thread at a time */
static int errors_of(Display *d)
{
    int n = 0;
    pthread_mutex_lock(&own_lock);
    for (int i = 0; i < MAX_OWN; i++)
        if (own_displays[i] == d)
            n = own_errors[i];
    pthread_mutex_unlock(&own_lock);
    return n;
}

static Display *open_display(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, load_xlib);
    if (!x_loaded)
        return NULL;
    Display *d = x.XOpenDisplay(NULL);
    if (!d)
        return NULL;
    pthread_mutex_lock(&own_lock);
    for (int i = 0; i < MAX_OWN; i++)
        if (!own_displays[i]) {
            own_displays[i] = d;
            own_errors[i] = 0;
            break;
        }
    static BOOL installed;
    if (!installed) {
        installed = YES;
        pthread_mutex_unlock(&own_lock);
        XErrorHandler before = x.XSetErrorHandler(on_error);
        pthread_mutex_lock(&own_lock);
        previous_handler = before == on_error ? NULL : before;
    }
    pthread_mutex_unlock(&own_lock);
    return d;
}

static void close_display(Display *d)
{
    if (!d)
        return;
    pthread_mutex_lock(&own_lock);
    for (int i = 0; i < MAX_OWN; i++)
        if (own_displays[i] == d)
            own_displays[i] = NULL;
    pthread_mutex_unlock(&own_lock);
    x.XCloseDisplay(d);
}

/* ---- properties --------------------------------------------------------------------------- */

static unsigned char *property(Display *d, Window w, Atom name, Atom type, unsigned long *count, int *format)
{
    Atom actual = 0;
    int fmt = 0;
    unsigned long n = 0, after = 0;
    unsigned char *data = NULL;
    if (x.XGetWindowProperty(d, w, name, 0, 1 << 16, 0, type, &actual, &fmt, &n, &after, &data) != 0 || !data) {
        if (data)
            x.XFree(data);
        return NULL;
    }
    if (actual == 0 || (type != AnyPropertyType && actual != type)) {
        x.XFree(data);
        return NULL;
    }
    if (count)
        *count = n;
    if (format)
        *format = fmt;
    return data;
}

static NSString *string_property(Display *d, Window w, Atom name, Atom type)
{
    unsigned long n = 0;
    int fmt = 0;
    unsigned char *data = property(d, w, name, type, &n, &fmt);
    if (!data)
        return nil;
    NSString *s = fmt == 8 && n ? [[[NSString alloc] initWithBytes:data length:n encoding:NSUTF8StringEncoding] autorelease]
                                : nil;
    if (!s && fmt == 8 && n)
        s = [[[NSString alloc] initWithBytes:data length:n encoding:NSISOLatin1StringEncoding] autorelease];
    x.XFree(data);
    return s;
}

/* ---- the listing connection ------------------------------------------------------------------- */

static pthread_mutex_t list_lock = PTHREAD_MUTEX_INITIALIZER;
static Display *list_display;
static struct {
    Atom clientListStacking, clientList, wmName, utf8, wmPid, wmState, netWmState, hidden, windowType, typeNormal,
        typeDialog, typeUtility;
} atoms;

static Display *listing(void)
{
    if (!list_display) {
        list_display = open_display();
        if (list_display) {
#define A(field, name) atoms.field = x.XInternAtom(list_display, name, 0)
            A(clientListStacking, "_NET_CLIENT_LIST_STACKING");
            A(clientList, "_NET_CLIENT_LIST");
            A(wmName, "_NET_WM_NAME");
            A(utf8, "UTF8_STRING");
            A(wmPid, "_NET_WM_PID");
            A(wmState, "WM_STATE");
            A(netWmState, "_NET_WM_STATE");
            A(hidden, "_NET_WM_STATE_HIDDEN");
            A(windowType, "_NET_WM_WINDOW_TYPE");
            A(typeNormal, "_NET_WM_WINDOW_TYPE_NORMAL");
            A(typeDialog, "_NET_WM_WINDOW_TYPE_DIALOG");
            A(typeUtility, "_NET_WM_WINDOW_TYPE_UTILITY");
#undef A
        }
    }
    return list_display;
}

static CGFloat backend_scale(void)
{
    const char *s = getenv("GDK_SCALE");
    int v = s && *s ? atoi(s) : 1;
    return v > 0 ? v : 1;
}

static BOOL x11_available(void)
{
    pthread_mutex_lock(&list_lock);
    BOOL ok = listing() != NULL;
    pthread_mutex_unlock(&list_lock);
    return ok;
}

static NSArray *x11_displays(void)
{
    NSMutableArray *out = [NSMutableArray array];
    pthread_mutex_lock(&list_lock);
    Display *d = listing();
    if (d) {
        int screen = x.XDefaultScreen(d);
        ACaptureDisplay *disp = [[[ACaptureDisplay alloc] init] autorelease];
        disp->number = 1;    /* NSScreen's number for the one X11 screen */
        disp->scale = backend_scale();
        disp->pixelFrame = CGRectMake(0, 0, x.XDisplayWidth(d, screen), x.XDisplayHeight(d, screen));
        disp->frame = CGRectMake(0, 0, disp->pixelFrame.size.width / disp->scale,
                                 disp->pixelFrame.size.height / disp->scale);
        disp->refreshRate = 60;
        [out addObject:disp];
    }
    pthread_mutex_unlock(&list_lock);
    return out;
}

static NSString *owner_of(pid_t pid, NSString *wmClass)
{
    if ([wmClass length])
        return wmClass;
    if (pid > 0) {
        NSString *comm = [NSString stringWithContentsOfFile:[NSString stringWithFormat:@"/proc/%d/comm", (int)pid]
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
        comm = [comm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([comm length])
            return comm;
    }
    return @"";
}

/* called with list_lock held */
static ACaptureWindow *describe(Display *d, Window root, Window w, BOOL managed, CGFloat scale)
{
    XWindowAttributes a;
    memset(&a, 0, sizeof a);
    int before = errors_of(d);
    if (!x.XGetWindowAttributes(d, w, &a) || errors_of(d) != before)
        return nil;
    if (a.c_class != InputOutput || a.width < 2 || a.height < 2)
        return nil;
    NSString *title = string_property(d, w, atoms.wmName, atoms.utf8) ?: string_property(d, w, XA_WM_NAME, AnyPropertyType);
    unsigned long n = 0;
    int fmt = 0;
    pid_t pid = 0;
    unsigned char *p = property(d, w, atoms.wmPid, XA_CARDINAL, &n, &fmt);
    if (p) {
        if (n >= 1 && fmt == 32)
            pid = (pid_t)*(unsigned long *)p;
        x.XFree(p);
    }
    if (!managed && (a.map_state != IsViewable || a.override_redirect || (!title && !pid)))
        return nil;
    /* WM_CLASS is two strings, the instance and the class */
    NSString *instance = nil, *klass = nil;
    p = property(d, w, XA_WM_CLASS, XA_STRING, &n, &fmt);
    if (p) {
        if (fmt == 8 && n) {
            size_t first = strnlen((char *)p, n);
            instance = [[[NSString alloc] initWithBytes:p length:first encoding:NSUTF8StringEncoding] autorelease];
            if (first + 1 < n)
                klass = [[[NSString alloc] initWithBytes:p + first + 1
                                                  length:strnlen((char *)p + first + 1, n - first - 1)
                                                encoding:NSUTF8StringEncoding] autorelease];
        }
        x.XFree(p);
    }
    BOOL hidden = NO;
    p = property(d, w, atoms.netWmState, 4 /* XA_ATOM */, &n, &fmt);
    if (p) {
        for (unsigned long i = 0; fmt == 32 && i < n; i++)
            if (((unsigned long *)p)[i] == atoms.hidden)
                hidden = YES;
        x.XFree(p);
    }
    int rx = 0, ry = 0;
    Window child = 0;
    x.XTranslateCoordinates(d, w, root, 0, 0, &rx, &ry, &child);
    ACaptureWindow *e = [[[ACaptureWindow alloc] init] autorelease];
    e->handle = w;
    e->pid = pid;
    e->title = [(title ?: @"") copy];
    e->owner = [owner_of(pid, klass) copy];
    e->bundleID = [(instance ?: @"") copy];
    e->pixelFrame = CGRectMake(rx, ry, a.width, a.height);
    e->frame = CGRectMake(rx / scale, ry / scale, a.width / scale, a.height / scale);
    e->onscreen = a.map_state == IsViewable && !hidden;
    return e;
}

static NSArray *x11_windows(void)
{
    NSMutableArray *out = [NSMutableArray array];
    pthread_mutex_lock(&list_lock);
    Display *d = listing();
    if (d) {
        Window root = x.XDefaultRootWindow(d);
        CGFloat scale = backend_scale();
        unsigned long n = 0;
        int fmt = 0;
        unsigned char *list = property(d, root, atoms.clientListStacking, XA_WINDOW, &n, &fmt);
        if (!list)
            list = property(d, root, atoms.clientList, XA_WINDOW, &n, &fmt);
        if (list && fmt == 32) {
            /* bottom to top: the list is front to back */
            for (unsigned long i = n; i-- > 0;) {
                ACaptureWindow *e = describe(d, root, ((unsigned long *)list)[i], YES, scale);
                if (e)
                    [out addObject:e];
            }
        } else {
            Window r = 0, parent = 0, *children = NULL;
            unsigned count = 0;
            if (x.XQueryTree(d, root, &r, &parent, &children, &count)) {
                for (unsigned i = count; i-- > 0;) {
                    ACaptureWindow *e = describe(d, root, children[i], NO, scale);
                    if (e)
                        [out addObject:e];
                }
                if (children)
                    x.XFree(children);
            }
        }
        if (list)
            x.XFree(list);
        x.XSync(d, 0);
    }
    pthread_mutex_unlock(&list_lock);
    return out;
}

/* ---- grabbing ----------------------------------------------------------------------------------- */

typedef struct {
    Display *display;
    Window root;
    Visual *visual;
    int depth;
    BOOL shm, fixes, composite;
    XImage *shmImage;
    XShmSegmentInfo seg;
    int shmWidth, shmHeight;
    XImage *image;             /* the last XGetImage's */
    Window redirected[16];
    int redirectedCount;
    uint32_t *cursor;
    size_t cursorSize;
} Grabber;

static void *x11_open(void)
{
    Display *d = open_display();
    if (!d)
        return NULL;
    Grabber *g = calloc(1, sizeof *g);
    g->display = d;
    g->root = x.XDefaultRootWindow(d);
    int screen = x.XDefaultScreen(d);
    g->visual = x.XDefaultVisual ? x.XDefaultVisual(d, screen) : NULL;
    g->depth = x.XDefaultDepth ? x.XDefaultDepth(d, screen) : 24;
    int a = 0, b = 0;
    g->shm = getenv("FERRY_CAPTURE_NO_SHM") == NULL && x.XShmQueryExtension && x.XShmCreateImage && x.XShmAttach &&
             x.XShmGetImage && x.shmget && x.shmat && g->visual && x.XShmQueryExtension(d);
    g->fixes = x.XFixesQueryExtension && x.XFixesGetCursorImage && x.XFixesQueryExtension(d, &a, &b);
    g->composite = x.XCompositeQueryExtension && x.XCompositeRedirectWindow && x.XCompositeQueryExtension(d, &a, &b);
    return g;
}

static void drop_shm(Grabber *g)
{
    if (!g->shmImage)
        return;
    x.XShmDetach(g->display, &g->seg);
    x.XSync(g->display, 0);
    g->shmImage->data = NULL;
    x.XDestroyImage(g->shmImage);
    g->shmImage = NULL;
    x.shmdt(g->seg.shmaddr);
}

static void x11_close(void *p)
{
    Grabber *g = p;
    if (!g)
        return;
    drop_shm(g);
    if (g->image)
        x.XDestroyImage(g->image);
    free(g->cursor);
    close_display(g->display);
    free(g);
}

static BOOL usable(XImage *im)
{
    /* 32 bits a pixel, little-endian, red in the third byte: B, G, R, X */
    return im && im->bits_per_pixel == 32 && im->byte_order == 0 && im->red_mask == 0xff0000 &&
           im->green_mask == 0xff00 && im->blue_mask == 0xff;
}

static BOOL from_ximage(XImage *im, ACaptureImage *out)
{
    if (!usable(im)) {
        ACaptureSayOnce("the X server's pixels aren't 32-bit BGRX, which Ferry's capture reads");
        return NO;
    }
    out->data = (uint8_t *)im->data;
    out->width = (size_t)im->width;
    out->height = (size_t)im->height;
    out->bytesPerRow = (size_t)im->bytes_per_line;
    return YES;
}

static BOOL get_image(Grabber *g, Drawable what, int x0, int y0, int w, int h, ACaptureImage *out)
{
    if (g->image) {
        x.XDestroyImage(g->image);
        g->image = NULL;
    }
    int before = errors_of(g->display);
    g->image = x.XGetImage(g->display, what, x0, y0, (unsigned)w, (unsigned)h, AllPlanes, ZPixmap);
    x.XSync(g->display, 0);
    if (!g->image || errors_of(g->display) != before)
        return NO;
    return from_ximage(g->image, out);
}

static BOOL x11_grab_screen(void *p, CGRect r, ACaptureImage *out)
{
    Grabber *g = p;
    int x0 = (int)r.origin.x, y0 = (int)r.origin.y, w = (int)r.size.width, h = (int)r.size.height;
    if (w <= 0 || h <= 0)
        return NO;
    if (g->shm) {
        if (!g->shmImage || g->shmWidth != w || g->shmHeight != h) {
            drop_shm(g);
            memset(&g->seg, 0, sizeof g->seg);
            XImage *im = x.XShmCreateImage(g->display, g->visual, (unsigned)g->depth, ZPixmap, NULL, &g->seg,
                                           (unsigned)w, (unsigned)h);
            int id = im ? x.shmget(IPC_PRIVATE, (size_t)im->bytes_per_line * (size_t)h, IPC_CREAT | 0600) : -1;
            void *mem = id >= 0 ? x.shmat(id, NULL, 0) : (void *)-1;
            int before = errors_of(g->display);
            BOOL attached = NO;
            if (mem != (void *)-1) {
                g->seg.shmid = id;
                g->seg.shmaddr = im->data = mem;
                g->seg.readOnly = 0;
                attached = x.XShmAttach(g->display, &g->seg);
                x.XSync(g->display, 0);
            }
            if (id >= 0 && x.shmctl)
                x.shmctl(id, IPC_RMID, NULL);    /* gone once both sides let go */
            if (!attached || errors_of(g->display) != before) {
                if (mem != (void *)-1)
                    x.shmdt(mem);
                if (im) {
                    im->data = NULL;
                    x.XDestroyImage(im);
                }
                g->shm = NO;      /* the server can't share memory with this process: XGetImage */
            } else {
                g->shmImage = im;
                g->shmWidth = w;
                g->shmHeight = h;
            }
        }
        if (g->shmImage) {
            int before = errors_of(g->display);
            BOOL ok = x.XShmGetImage(g->display, g->root, g->shmImage, x0, y0, AllPlanes);
            x.XSync(g->display, 0);
            if (ok && errors_of(g->display) == before)
                return from_ximage(g->shmImage, out);
        }
    }
    return get_image(g, g->root, x0, y0, w, h, out);
}

static BOOL x11_grab_window(void *p, uint64_t handle, ACaptureImage *out, CGRect *pixelFrame)
{
    Grabber *g = p;
    Window w = (Window)handle;
    XWindowAttributes a;
    memset(&a, 0, sizeof a);
    int before = errors_of(g->display);
    if (!x.XGetWindowAttributes(g->display, w, &a) || errors_of(g->display) != before || a.map_state != IsViewable)
        return NO;
    if (g->composite) {
        BOOL known = NO;
        for (int i = 0; i < g->redirectedCount && !known; i++)
            known = g->redirected[i] == w;
        if (!known) {
            /* the server keeps the window's pixels where others cover it; undone when this connection closes */
            x.XCompositeRedirectWindow(g->display, w, CompositeRedirectAutomatic);
            x.XSync(g->display, 0);
            if (g->redirectedCount < 16)
                g->redirected[g->redirectedCount++] = w;
        }
    }
    if (pixelFrame) {
        int rx = 0, ry = 0;
        Window child = 0;
        x.XTranslateCoordinates(g->display, w, g->root, 0, 0, &rx, &ry, &child);
        *pixelFrame = CGRectMake(rx, ry, a.width, a.height);
    }
    return get_image(g, w, 0, 0, a.width, a.height, out);
}

static BOOL x11_cursor(void *p, ACaptureCursor *out)
{
    Grabber *g = p;
    if (!g->fixes)
        return NO;
    XFixesCursorImage *c = x.XFixesGetCursorImage(g->display);
    if (!c)
        return NO;
    size_t n = (size_t)c->width * c->height;
    if (n > g->cursorSize) {
        free(g->cursor);
        g->cursor = malloc(n * sizeof *g->cursor);
        g->cursorSize = n;
    }
    /* XFixes gives each pixel in an unsigned long, premultiplied ARGB in its low 32 bits */
    for (size_t i = 0; i < n; i++)
        g->cursor[i] = (uint32_t)c->pixels[i];
    out->argb = g->cursor;
    out->width = c->width;
    out->height = c->height;
    out->x = (long)c->x - c->xhot;
    out->y = (long)c->y - c->yhot;
    x.XFree(c);
    return n > 0;
}

const ACaptureBackend ACaptureX11Backend = {
    "x11", x11_available, x11_displays, x11_windows, x11_open, x11_close, x11_grab_screen, x11_grab_window, x11_cursor,
};
