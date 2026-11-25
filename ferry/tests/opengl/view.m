/* SPDX-License-Identifier: GPL-3.0-or-later
 * OpenGL in AppKit's views (freemac 1.235, Ferry 0.59.0): an NSOpenGLView
 * drawing a triangle with the legacy profile in drawRect:, and, as OBS's
 * gl-cocoa draws, a 3.2 core context with shaders attached to a plain
 * (flipped) view with setView: and drawing from a thread of its own; each
 * view's drawing read back with cacheDisplayInRect:, the right way up.
 * Pictures of them go to $FERRY_TEST_SHOTS when it is set. */
#import <Cocoa/Cocoa.h>
#include <OpenGL/gl.h>
#include <pthread.h>
#include <stdio.h>
#include "../../opengl/FerryGL.h"

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

/* the colour at (x, y) of the view's picture, y from the top */
static void pixel(NSBitmapImageRep *rep, int x, int y, unsigned char out[3])
{
    unsigned char *p = [rep bitmapData] + (NSInteger)y * [rep bytesPerRow] + x * 4;
    out[0] = p[0], out[1] = p[1], out[2] = p[2];
}
static int near(const unsigned char *c, int r, int g, int b)
{
    return abs(c[0] - r) < 24 && abs(c[1] - g) < 24 && abs(c[2] - b) < 24;
}

static NSBitmapImageRep *picture(NSView *v, const char *name)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    const char *dir = getenv("FERRY_TEST_SHOTS");
    if (dir && *dir) {
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithFormat:@"%s/%s.png", dir, name] atomically:YES];
    }
    return rep;
}

static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/* ---- an NSOpenGLView: dark blue, a red triangle, a green square at the bottom left ---- */

@interface TriangleView : NSOpenGLView
@property int draws, prepares, reshapes;
@property BOOL currentInDraw;
@end

@implementation TriangleView
- (void)prepareOpenGL
{
    self.prepares++;
    GLint one = 1;
    [[self openGLContext] setValues:&one forParameter:NSOpenGLContextParameterSwapInterval];
}
- (void)reshape
{
    self.reshapes++;
    NSRect b = [self bounds];
    glViewport(0, 0, (GLsizei)b.size.width, (GLsizei)b.size.height);
}
- (void)drawRect:(NSRect)r
{
    self.draws++;
    self.currentInDraw = [NSOpenGLContext currentContext] == [self openGLContext];
    glClearColor(0, 0, 0.4f, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glColor3f(1, 0, 0);
    glBegin(GL_TRIANGLES);
    glVertex2f(-0.6f, -0.5f);
    glVertex2f(0.6f, -0.5f);
    glVertex2f(0, 0.7f);
    glEnd();
    glColor3f(0, 1, 0);
    glRectf(-1, -1, -0.7f, -0.7f);
    [[self openGLContext] flushBuffer];
}
@end

/* ---- a plain flipped view, drawn into from another thread ---- */

@interface FlippedView : NSView
@property int draws;
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r { self.draws++; }
@end

static NSOpenGLContext *core;
static FlippedView *plain;
static int thread_ok;

static GLuint shader(GLenum kind, const char *src)
{
    GLuint s = glCreateShader(kind);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    return ok ? s : 0;
}

static void *render_thread(void *arg)
{
    @autoreleasepool {
        CGLLockContext([core CGLContextObj]);
        [core makeCurrentContext];
        [core setView:plain];
        GLint size[2] = {0, 0};
        [core getValues:size forParameter:NSOpenGLContextParameterSurfaceBackingSize];
        GLuint vs = shader(GL_VERTEX_SHADER, "#version 150\nin vec2 p;\nvoid main() { gl_Position = vec4(p, 0.0, 1.0); }\n");
        GLuint fs = shader(GL_FRAGMENT_SHADER, "#version 150\nuniform vec4 colour;\nout vec4 c;\nvoid main() { c = colour; }\n");
        GLuint prog = glCreateProgram();
        glAttachShader(prog, vs);
        glAttachShader(prog, fs);
        glBindAttribLocation(prog, 0, "p");
        glLinkProgram(prog);
        GLint linked = 0;
        glGetProgramiv(prog, GL_LINK_STATUS, &linked);
        GLfloat tri[] = {-0.6f, -0.5f, 0.6f, -0.5f, 0.0f, 0.7f, -1, -1, -0.7f, -1, -1, -0.7f};
        GLuint vao = 0, vbo = 0;
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof tri, tri, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, NULL);
        glEnableVertexAttribArray(0);
        glViewport(0, 0, size[0], size[1]);
        glClearColor(0.3f, 0.3f, 0.3f, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(prog);
        GLint colour = glGetUniformLocation(prog, "colour");
        glUniform4f(colour, 1, 1, 0, 1);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        glUniform4f(colour, 0, 1, 0, 1);
        glDrawArrays(GL_TRIANGLES, 3, 3);
        [core flushBuffer];
        thread_ok = vs && fs && linked && size[0] == 160 && size[1] == 120 && glGetError() == GL_NO_ERROR;
        [NSOpenGLContext clearCurrentContext];
        CGLUnlockContext([core CGLContextObj]);
    }
    return NULL;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 160) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSOpenGLPixelFormatAttribute attrs[] = {NSOpenGLPFADoubleBuffer, NSOpenGLPFAColorSize, 24, NSOpenGLPFAOpenGLProfile,
                                                NSOpenGLProfileVersionLegacy, 0};
        NSOpenGLPixelFormat *pf = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs] autorelease];
        if (!check("a legacy pixel format", pf != nil))
            return 1;
        GLint db = 0;
        [pf getValues:&db forAttribute:NSOpenGLPFADoubleBuffer forVirtualScreen:0];
        check("double buffered", db == 1);
        TriangleView *tv = [[TriangleView alloc] initWithFrame:NSMakeRect(10, 20, 160, 120) pixelFormat:pf];
        [[w contentView] addSubview:tv];
        check("its context draws into it", [[tv openGLContext] view] == tv);
        [w display];
        check("drawn once, prepared once, reshaped once", tv.draws == 1 && tv.prepares == 1 && tv.reshapes == 1);
        check("its context current in drawRect:", tv.currentInDraw);
        check("and not after", [NSOpenGLContext currentContext] == nil);
        GLint size[2] = {0, 0};
        [[tv openGLContext] getValues:size forParameter:NSOpenGLContextParameterSurfaceBackingSize];
        check("a surface of the view's size", size[0] == 160 && size[1] == 120);

        NSBitmapImageRep *rep = picture(tv, "opengl-view-legacy");
        unsigned char c[3];
        pixel(rep, 80, 70, c);
        check("the triangle is red in the middle", near(c, 255, 0, 0));
        pixel(rep, 80, 10, c);
        check("dark blue above it", near(c, 0, 0, 102));
        pixel(rep, 5, 115, c);
        check("the green square at the bottom left", near(c, 0, 255, 0));
        pixel(rep, 5, 5, c);
        check("not at the top left", near(c, 0, 0, 102));
        check("drawRect: called for the picture", tv.draws == 2);

        /* a flush outside drawRect: shows without drawRect: */
        int draws = tv.draws;
        [[tv openGLContext] makeCurrentContext];
        glClearColor(1, 0, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        [[tv openGLContext] flushBuffer];
        [NSOpenGLContext clearCurrentContext];
        spin(0.1);
        [w displayIfNeeded];
        check("a flush of its own has the window draw it again, without drawRect:", tv.draws == draws);
        FerryGLFrame *f = FerryCGLCopyFrame([[tv openGLContext] CGLContextObj]);
        check("showing the magenta frame", f && f->data[2] == 255 && f->data[1] == 0 && f->data[0] == 255);
        FerryGLFrameRelease(f);

        /* resized: reshaped, and a surface of the new size */
        [tv setFrameSize:NSMakeSize(100, 80)];
        [w display];
        [[tv openGLContext] getValues:size forParameter:NSOpenGLContextParameterSurfaceBackingSize];
        check("reshaped after a resize, to a surface of 100 by 80", tv.reshapes == 2 && size[0] == 100 && size[1] == 80);
        [tv setFrameSize:NSMakeSize(160, 120)];

        /* the core profile, drawn from another thread into a plain view */
        NSOpenGLPixelFormatAttribute cattrs[] = {NSOpenGLPFADoubleBuffer, NSOpenGLPFAOpenGLProfile,
                                                 NSOpenGLProfileVersion3_2Core, 0};
        NSOpenGLPixelFormat *cpf = [[[NSOpenGLPixelFormat alloc] initWithAttributes:cattrs] autorelease];
        core = [[NSOpenGLContext alloc] initWithFormat:cpf shareContext:[tv openGLContext]];
        check("a 3.2 core context sharing with the view's", core != nil);
        plain = [[FlippedView alloc] initWithFrame:NSMakeRect(190, 20, 160, 120)];
        [[w contentView] addSubview:plain];
        [w display];
        pthread_t t;
        pthread_create(&t, NULL, render_thread, NULL);
        pthread_join(t, NULL);
        check("the thread compiled, linked and drew", thread_ok);
        check("attached to the view", [core view] == plain);
        int before = plain.draws;
        spin(0.1);
        [w displayIfNeeded];
        check("its flush had the view drawn again", plain.draws == before + 1);
        rep = picture(plain, "opengl-view-core");
        pixel(rep, 80, 70, c);
        check("the core triangle is yellow in the middle", near(c, 255, 255, 0));
        pixel(rep, 5, 115, c);
        check("its green square at the bottom left of the flipped view", near(c, 0, 255, 0));
        pixel(rep, 5, 5, c);
        check("grey at the top left", near(c, 77, 77, 77));

        /* the whole window */
        rep = picture([w contentView], "opengl-window");
        pixel(rep, 10 + 80, 160 - 20 - 120 + 70, c);
        check("both in the window's picture: the red triangle", near(c, 255, 0, 0));
        pixel(rep, 190 + 80, 160 - 20 - 120 + 70, c);
        check("and the yellow one", near(c, 255, 255, 0));

        [core clearDrawable];
        check("cleared: no view", [core view] == nil);
        [core release];
        [tv removeFromSuperview];
        [tv release];
    }
    return 0;
}
