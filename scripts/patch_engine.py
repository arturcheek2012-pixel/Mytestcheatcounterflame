import re, sys, pathlib
root = pathlib.Path(sys.argv[1])

def edit(path, fn):
    p = root / path
    s = p.read_text()
    n = fn(s)
    assert n != s, 'no change: ' + path
    p.write_text(n)

def unit(i): return '\t' if '\t' in i else '    '

def wscript(s):
    s, c = re.subn(r"(?m)^([ \t]*)(grp\.add_option\('--togles')",
        r"\1grp.add_option('--ios', action='store_true', dest='IOS', default=False, help='build for iOS arm64')\n\1\2",
        s, count=1)
    assert c == 1, 'anchor --togles not found'

    def env(m):
        i = m.group(1)
        return (f"{i}conf.env.IOS = conf.options.IOS\n"
                f"{i}if conf.env.IOS:\n"
                f"{i}{unit(i)}conf.env.append_unique('DEFINES', ['IOS=1', '_IOS=1'])\n" + m.group(0))
    s, c = re.subn(r"(?m)^([ \t]*)conf\.env\.BIT32_MANDATORY = conf\.options\.TARGET32", env, s, count=1)
    assert c == 1, 'anchor BIT32_MANDATORY not found'

    for name, mac, ios in [('APPKIT','AppKit','UIKit'), ('IOKIT','IOKit','Foundation'),
                           ('CARBON','Carbon','Foundation'),
                           ('APPLICATIONSERVICES','ApplicationServices','CoreGraphics'),
                           ('CORESERVICES','CoreServices','CoreFoundation'),
                           ('OPENGL','OpenGL','OpenGLES')]:
        old = f'conf.env.FRAMEWORK_{name} = "{mac}"'
        assert old in s, old
        s = s.replace(old, f'conf.env.FRAMEWORK_{name} = "{ios}" if conf.env.IOS else "{mac}"')

    def fc(m):
        i = m.group(1)
        return f"{i}if not conf.env.IOS:\n{i}{unit(i)}conf.check_pkg('fontconfig', 'FC', FC_CHECK)"
    s, c = re.subn(r"(?m)^([ \t]*)conf\.check_pkg\('fontconfig', 'FC', FC_CHECK\)", fc, s, count=1)
    assert c == 1, 'fontconfig check not found'
    return s

edit('wscript', wscript)
edit('appframework/wscript', lambda s: s.replace(
    "if bld.env.DEST_OS == 'darwin' and bld.env.GL:",
    "if bld.env.DEST_OS == 'darwin' and bld.env.GL and not bld.env.IOS:"))

# --- звук: убрать macOS CoreAudio-файлы, взять SDL-вывод ---
def engine_wscript(s):
    def ins(m):
        i = m.group(1); u = unit(i)
        return (f"{i}if bld.env.IOS:\n"
                f"{i}{u}source = [x for x in source if not any(k in x for k in "
                f"('snd_dev_openal', 'snd_dev_mac_audioqueue', 'voice_record_mac_audioqueue'))]\n"
                f"{i}{u}if 'audio/snd_dev_sdl.cpp' not in source:\n"
                f"{i}{u}{u}source += ['audio/snd_dev_sdl.cpp']\n\n" + m.group(0))
    s, c = re.subn(r"(?m)^([ \t]*)includes = \[", ins, s, count=1)
    assert c == 1, 'engine/wscript: includes anchor not found'
    return s
edit('engine/wscript', engine_wscript)

# --- заглушки macOS-заголовков для iOS ---
CGL = """#pragma once
#include <stdint.h>
typedef struct _CGLContextObject *CGLContextObj;
typedef struct _CGLPixelFormatObject *CGLPixelFormatObj;
typedef struct _CGLRendererInfoObject *CGLRendererInfoObj;
typedef struct _CGLPBufferObject *CGLPBufferObj;
typedef int CGLError;
typedef int CGLPixelFormatAttribute;
typedef int CGLContextEnable;
typedef int CGLContextParameter;
typedef int CGLGlobalOption;
typedef int CGLRendererProperty;
#define kCGLNoError 0
#define kCGLCPGPUVertexProcessing 122
#define kCGLCPGPUFragmentProcessing 123
#define kCGLCEMPEngine 313
static inline CGLContextObj CGLGetCurrentContext(void) { return 0; }
static inline CGLError CGLEnable(CGLContextObj c, CGLContextEnable e) { (void)c; (void)e; return -1; }
static inline CGLError CGLDisable(CGLContextObj c, CGLContextEnable e) { (void)c; (void)e; return -1; }
static inline CGLError CGLIsEnabled(CGLContextObj c, CGLContextEnable e, int *v) { (void)c; (void)e; *v = 0; return -1; }
static inline CGLError CGLSetParameter(CGLContextObj c, CGLContextParameter p, const int *v) { (void)c; (void)p; (void)v; return -1; }
static inline CGLError CGLGetParameter(CGLContextObj c, CGLContextParameter p, int *v) { (void)c; (void)p; *v = 0; return -1; }
"""
CGL_RENDERERS = """#pragma once
#include <OpenGL/CGLTypes.h>
#define kCGLRendererGenericID 0x00020200
#define kCGLRendererGenericFloatID 0x00020400
#define kCGLRendererAppleSWID 0x00020600
#define kCGLRendererATIRage128ID 0x00021000
#define kCGLRendererATIRadeonID 0x00021200
#define kCGLRendererATIRageProID 0x00021400
#define kCGLRendererATIRadeon8500ID 0x00021600
#define kCGLRendererATIRadeon9700ID 0x00021800
#define kCGLRendererATIRadeonX1000ID 0x00021900
#define kCGLRendererATIRadeonX2000ID 0x00021A00
#define kCGLRendererGeForce2MXID 0x00022000
#define kCGLRendererGeForce3ID 0x00022200
#define kCGLRendererGeForceFXID 0x00022400
#define kCGLRendererGeForce8xxxID 0x00022600
#define kCGLRendererVTBladeXP2ID 0x00023000
#define kCGLRendererIntel900ID 0x00024000
"""
INC_CGL = '#pragma once\n#include <OpenGL/CGLTypes.h>\n'

# Apple OpenGL ES 3: прототипы, конфликтующие с common/GL/glext.h, переименованы
GLES_GL = """#pragma once
#define glShaderSource ios_apple_glShaderSource
#define glTransformFeedbackVaryings ios_apple_glTransformFeedbackVaryings
#define glGetUniformIndices ios_apple_glGetUniformIndices
#include <OpenGLES/ES3/gl.h>
#undef glShaderSource
#undef glTransformFeedbackVaryings
#undef glGetUniformIndices
#ifndef IOS_GL_COMPAT_TYPES
#define IOS_GL_COMPAT_TYPES
typedef double GLdouble;
typedef double GLclampd;
#endif
"""

CARBON = """#pragma once
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
typedef struct __PasteboardRef *PasteboardRef;
typedef void *PasteboardItemID;
typedef uint32_t PasteboardSyncFlags;
typedef uint32_t PasteboardFlavorFlags;
#define kPasteboardClipboard CFSTR("com.apple.pasteboard.clipboard")
enum { kPasteboardModified = 1, kPasteboardClientIsOwner = 2 };
enum { kVK_Return = 0x24, kVK_Escape = 0x35 };
static inline int32_t PasteboardCreate(CFStringRef n, PasteboardRef *p) { (void)n; *p = 0; return -1; }
static inline int32_t PasteboardClear(PasteboardRef p) { (void)p; return -1; }
static inline PasteboardSyncFlags PasteboardSynchronize(PasteboardRef p) { (void)p; return 0; }
static inline int32_t PasteboardCopyItemFlavorData(PasteboardRef p, PasteboardItemID i, CFStringRef f, CFDataRef *d) { (void)p; (void)i; (void)f; *d = 0; return -1; }
static inline int32_t PasteboardPutItemFlavor(PasteboardRef p, PasteboardItemID i, CFStringRef f, CFDataRef d, PasteboardFlavorFlags fl) { (void)p; (void)i; (void)f; (void)d; (void)fl; return -1; }
#ifdef __cplusplus
template <typename T> static inline int32_t PasteboardGetItemCount(PasteboardRef p, T *c) { (void)p; *c = 0; return -1; }
template <typename I> static inline int32_t PasteboardGetItemIdentifier(PasteboardRef p, I i, PasteboardItemID *o) { (void)p; (void)i; *o = 0; return -1; }
#else
static inline int32_t PasteboardGetItemCount(PasteboardRef p, uint32_t *c) { (void)p; *c = 0; return -1; }
static inline int32_t PasteboardGetItemIdentifier(PasteboardRef p, CFIndex i, PasteboardItemID *o) { (void)p; (void)i; *o = 0; return -1; }
#endif
"""

APPSERVICES = """#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CFNetwork/CFNetwork.h>
#include <Carbon/Carbon.h>
typedef int CGEventSourceStateID;
#define kCGEventSourceStateCombinedSessionState 0
static inline int CGEventSourceKeyState(CGEventSourceStateID s, unsigned short k) { (void)s; (void)k; return 0; }
"""

OAL_EXT = """#pragma once
#include <OpenAL/al.h>
typedef ALvoid (*alBufferDataStaticProcPtr)(const ALint bid, ALenum format, ALvoid *data, ALsizei size, ALsizei freq);
"""

EGL = """#pragma once
#include <stdint.h>
typedef void *EGLDisplay;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef void *EGLConfig;
typedef void *EGLNativeDisplayType;
typedef void *EGLNativeWindowType;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_TRUE 1
#define EGL_FALSE 0
#define EGL_DRAW 0x3059
#define EGL_READ 0x305A
static inline EGLDisplay eglGetCurrentDisplay(void) { return 0; }
static inline EGLContext eglGetCurrentContext(void) { return 0; }
static inline EGLSurface eglGetCurrentSurface(EGLint r) { (void)r; return 0; }
static inline EGLBoolean eglSwapInterval(EGLDisplay d, EGLint i) { (void)d; (void)i; return 0; }
static inline EGLBoolean eglMakeCurrent(EGLDisplay d, EGLSurface a, EGLSurface b, EGLContext c) { (void)d; (void)a; (void)b; (void)c; return 0; }
static inline EGLBoolean eglSwapBuffers(EGLDisplay d, EGLSurface s) { (void)d; (void)s; return 0; }
static inline void *eglGetProcAddress(const char *n) { (void)n; return 0; }
"""

SHIMS = {
    'OpenGL/CGLTypes.h': CGL,
    'OpenGL/OpenGL.h': INC_CGL,
    'OpenGL/CGLCurrent.h': INC_CGL,
    'OpenGL/CGLRenderers.h': CGL_RENDERERS,
    'OpenGL/CGLProfiler.h': INC_CGL,
    'OpenGL/gl.h': GLES_GL,
    'OpenGL/glext.h': '#pragma once\n#include <OpenGL/gl.h>\n',
    'OpenGL/glu.h': '#pragma once\n',
    'SDL_opengl.h': '#pragma once\n#include <OpenGL/gl.h>\n',
    'ApplicationServices/ApplicationServices.h': APPSERVICES,
    'Carbon/Carbon.h': CARBON,
    'Cocoa/Cocoa.h': '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n'
                     '#ifdef __OBJC__\n#import <UIKit/UIKit.h>\n#endif\n',
    'OpenAL/MacOSX_OALExtensions.h': OAL_EXT,
    'EGL/egl.h': EGL,
    'EGL/eglext.h': '#pragma once\n#include <EGL/egl.h>\n',
}
for rel, text in SHIMS.items():
    p = root / 'ios_shims' / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)

# --- замена glmgrcocoa.mm: одна функция-мостик ---
STUB = """#include <OpenGL/CGLTypes.h>
typedef void _PseudoNSGLContext;
typedef _PseudoNSGLContext *PseudoNSGLContextPtr;
CGLContextObj GetCGLContextFromNSGL( PseudoNSGLContextPtr ) { return 0; }
"""
(root / 'togles/linuxwin/ios_stubs.cpp').write_text(STUB)
edit('togles/wscript', lambda s: s.replace(
    "'linuxwin/glmgrcocoa.mm'", "'linuxwin/ios_stubs.cpp'"))

# --- запросы OpenGL: прямые вызовы вместо отсутствующих членов gGL ---
p = root / 'togles/linuxwin/cglmquery.cpp'
if p.exists():
    s = p.read_text()
    s2 = re.sub(r'\bgGL->(glGenQueries|glDeleteQueries|glBeginQuery|glEndQuery|glGetQueryObjectuiv)\b',
                r'\1', s)
    p.write_text(s2)

# --- system() недоступен на iOS: точечная замена вызова с аргументом ---
p = root / 'vgui2/vgui_controls/FileOpenDialog.cpp'
if p.exists():
    s = p.read_text()
    s2 = re.sub(r'(?<![\w:>.])system[ \t]*\([ \t]*(?![ \t]*\))', 'ios_noop_system(', s)
    if s2 != s:
        s2 = ('#include <stdlib.h>\n'
              'static inline int ios_noop_system(const char *) { return -1; }\n' + s2)
        p.write_text(s2)

# --- прокси и SDL_SysWMinfo ---
PRE = (b'#include <CoreFoundation/CoreFoundation.h>\n#include <CFNetwork/CFNetwork.h>\n'
       b'#include <SystemConfiguration/SystemConfiguration.h>\n'
       b'#define SCDynamicStoreCopyProxies(x) ((CFDictionaryRef)NULL)\n')
SKIP = {'thirdparty', 'lib', 'build', 'ios_shims', '.git'}
for f in root.rglob('*'):
    if f.suffix in ('.cpp', '.cc', '.mm', '.m', '.c') and f.is_file():
        if set(f.relative_to(root).parts) & SKIP:
            continue
        data = f.read_bytes()
        changed = False
        if b'SCDynamicStoreCopyProxies' in data:
            data = PRE + data
            changed = True
            print('proxy patched:', f)
        if b'SDL_SysWMinfo' in data and b'.cocoa.' in data:
            data = data.replace(b'.cocoa.', b'.uikit.')
            changed = True
            print('wminfo patched:', f)
        if changed:
            f.write_bytes(data)

print('patched')
