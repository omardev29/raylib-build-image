/* The image's own proof that it can do the one job it exists for: start a
 * desktop program on Xvfb and have Mesa's llvmpipe draw for it.
 *
 *     xvfb-run -a -s "-screen 0 64x64x24" rmp-glx-smoke
 *
 * The framework's musl-x64-run job starts the shipped musl game exactly that
 * way, and a game built with GLFW asks three things of the system: an X
 * server, the X libraries GLFW opens with dlopen() rather than linking, and an
 * OpenGL that renders. Each is checked here the way the game would meet it --
 * the libraries are dlopen()ed by the names GLFW uses, a GLX context is made on
 * the display xvfb-run started, and a triangle is drawn and read back -- so an
 * image that has the packages and still cannot draw fails its own build.
 *
 * Prints RMP_GLX_SMOKE_OK and exits 0, or says what failed and exits 1. */
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#define SIZE 64

/* What GLFW 3.4's X11 backend dlopen()s, by the soname it asks for: the four
 * the job installs as packages, and libGL, which mesa-gl provides. */
static const char *const libraries[] = {
    "libX11.so.6",      "libXcursor.so.1", "libXrandr.so.2",
    "libXi.so.6",       "libXinerama.so.1", "libGL.so.1",
};

static int fail(const char *what)
{
    fprintf(stderr, "FAIL: %s\n", what);
    return 1;
}

/* One pixel of the back buffer, as RGB. */
static void pixel(int x, int y, unsigned char out[3])
{
    unsigned char rgba[4] = {0, 0, 0, 0};
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    memcpy(out, rgba, 3);
}

static int is(const unsigned char got[3], int r, int g, int b)
{
    return got[0] == r && got[1] == g && got[2] == b;
}

int main(void)
{
    for (size_t i = 0; i < sizeof libraries / sizeof libraries[0]; i++) {
        void *handle = dlopen(libraries[i], RTLD_NOW | RTLD_LOCAL);
        if (!handle) {
            fprintf(stderr, "FAIL: dlopen(%s): %s\n", libraries[i], dlerror());
            return 1;
        }
        printf("  ok    dlopen %s\n", libraries[i]);
        dlclose(handle);
    }

    Display *display = XOpenDisplay(NULL);
    if (!display) return fail("no X display: is this running under xvfb-run?");
    int attributes[] = {GLX_RGBA, GLX_RED_SIZE, 8, GLX_GREEN_SIZE, 8, GLX_BLUE_SIZE, 8,
                        GLX_DOUBLEBUFFER, None};
    XVisualInfo *visual = glXChooseVisual(display, DefaultScreen(display), attributes);
    if (!visual) return fail("no double-buffered 24-bit GLX visual");
    Window root = RootWindow(display, visual->screen);
    XSetWindowAttributes window_attributes;
    memset(&window_attributes, 0, sizeof window_attributes);
    window_attributes.colormap = XCreateColormap(display, root, visual->visual, AllocNone);
    window_attributes.event_mask = StructureNotifyMask;
    Window window = XCreateWindow(display, root, 0, 0, SIZE, SIZE, 0, visual->depth, InputOutput,
                                  visual->visual, CWColormap | CWEventMask, &window_attributes);
    XMapWindow(display, window);
    for (XEvent event;;) {
        XNextEvent(display, &event);
        if (event.type == MapNotify) break;
    }
    GLXContext context = glXCreateContext(display, visual, NULL, True);
    if (!context) return fail("glXCreateContext");
    if (!glXMakeCurrent(display, window, context)) return fail("glXMakeCurrent");

    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("  GL_RENDERER %s\n  GL_VERSION  %s\n", renderer ? renderer : "(null)",
           version ? version : "(null)");
    /* llvmpipe and not softpipe: softpipe is what Mesa falls back to when the
     * LLVM it JITs with cannot be loaded, and it is not what CI should meet. */
    if (!renderer || !strstr(renderer, "llvmpipe")) return fail("the renderer is not llvmpipe");
    char name[128];
    snprintf(name, sizeof name, "%s", renderer);   /* the context owns the original */

    /* Blue everywhere, then a red triangle over the lower-left half: one
     * pixel inside it and one outside, so a clear that works and a rasteriser
     * that does not cannot pass. */
    glViewport(0, 0, SIZE, SIZE);
    glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glBegin(GL_TRIANGLES);
    glColor3f(1.0f, 0.0f, 0.0f);
    glVertex2f(-1.0f, -1.0f);
    glVertex2f(1.0f, -1.0f);
    glVertex2f(-1.0f, 1.0f);
    glEnd();
    glFinish();
    unsigned char inside[3], outside[3];
    pixel(SIZE / 8, SIZE / 8, inside);
    pixel(SIZE - SIZE / 8, SIZE - SIZE / 8, outside);
    GLenum error = glGetError();
    printf("  inside the triangle  %u,%u,%u\n  outside it           %u,%u,%u\n", inside[0],
           inside[1], inside[2], outside[0], outside[1], outside[2]);
    if (error != GL_NO_ERROR) return fail("glGetError after drawing");
    if (!is(inside, 255, 0, 0)) return fail("the triangle is not red: nothing was rasterised");
    if (!is(outside, 0, 0, 255)) return fail("the background is not blue: the clear did not land");
    glXSwapBuffers(display, window);

    glXMakeCurrent(display, None, NULL);
    glXDestroyContext(display, context);
    XDestroyWindow(display, window);
    XFree(visual);
    XCloseDisplay(display);
    printf("RMP_GLX_SMOKE_OK %s\n", name);
    return 0;
}
