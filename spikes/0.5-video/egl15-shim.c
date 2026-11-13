/* Step 0.5 spike: the vendor Mali EGL is 1.4; Ubuntu Qt Multimedia calls the EGL 1.5 eglCreateImage and
   eglDestroyImage. Forward them to the KHR extension functions. Load with LD_PRELOAD. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
EGLImage eglCreateImage(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLAttrib *attribs)
{
    static PFNEGLCREATEIMAGEKHRPROC create;
    if (!create) create = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    EGLint a[128]; int i = 0;
    if (attribs) for (; attribs[i] != EGL_NONE && i < 126; i += 2) { a[i] = (EGLint)attribs[i]; a[i + 1] = (EGLint)attribs[i + 1]; }
    a[i] = EGL_NONE;
    return create(dpy, ctx, target, buffer, a);
}
EGLBoolean eglDestroyImage(EGLDisplay dpy, EGLImage image)
{
    static PFNEGLDESTROYIMAGEKHRPROC destroy;
    if (!destroy) destroy = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    return destroy(dpy, image);
}
