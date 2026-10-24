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
"""
INC_CGL = '#pragma once\n#include <OpenGL/CGLTypes.h>\n'

GLES_GL = """#pragma once
#include <OpenGLES/ES3/gl.h>
#include <OpenGLES/ES3/glext.h>
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
static inline int32_t PasteboardCreate(CFStringRef n, PasteboardRef *p) { (void)n; *p = 0; return -1; }
static inline int32_t PasteboardClear(PasteboardRef p) { (void)p; return -1; }
static inline PasteboardSyncFlags PasteboardSynchronize(PasteboardRef p) { (void)p; return 0; }
static inline int32_t PasteboardGetItemCount(PasteboardRef p, uint32_t *c) { (void)p; *c = 0; return -1; }
static inline int32_t PasteboardGetItemIdentifier(PasteboardRef p, CFIndex i, PasteboardItemID *o) { (void)p; (void)i; *o = 0; return -1; }
static inline int32_t PasteboardCopyItemFlavorData(PasteboardRef p, PasteboardItemID i, CFStringRef f, CFDataRef *d) { (void)p; (void)i; (void)f; *d = 0; return -1; }
static inline int32_t PasteboardPutItemFlavor(PasteboardRef p, PasteboardItemID i, CFStringRef f, CFDataRef d, PasteboardFlavorFlags fl) { (void)p; (void)i; (void)f; (void)d; (void)fl; return -1; }
"""

OAL_EXT = """#pragma once
#include <OpenAL/al.h>
typedef ALvoid (*alBufferDataStaticProcPtr)(const ALint bid, ALenum format, ALvoid *data, ALsizei size, ALsizei freq);
"""

SHIMS = {
    'OpenGL/CGLTypes.h': CGL,
    'OpenGL/OpenGL.h': INC_CGL,
    'OpenGL/CGLCurrent.h': INC_CGL,
    'OpenGL/CGLRenderers.h': INC_CGL,
    'OpenGL/CGLProfiler.h': INC_CGL,
    'OpenGL/gl.h': GLES_GL,
    'OpenGL/glext.h': '#pragma once\n#include <OpenGL/gl.h>\n',
    'OpenGL/glu.h': '#pragma once\n',
    'ApplicationServices/ApplicationServices.h':
        '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n'
        '#include <CoreGraphics/CoreGraphics.h>\n#include <CFNetwork/CFNetwork.h>\n'
        '#include <Carbon/Carbon.h>\n',
    'Carbon/Carbon.h': CARBON,
    'Cocoa/Cocoa.h': '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n'
                     '#ifdef __OBJC__\n#import <UIKit/UIKit.h>\n#endif\n',
    'OpenAL/MacOSX_OALExtensions.h': OAL_EXT,
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

# system() недоступен на iOS
p = root / 'vgui2/vgui_controls/FileOpenDialog.cpp'
if p.exists():
    p.write_text('#include <stdlib.h>\n#define system(x) (-1)\n' + p.read_text())

# прокси через SystemConfiguration/CFNetwork
PRE = (b'#include <CoreFoundation/CoreFoundation.h>\n#include <CFNetwork/CFNetwork.h>\n'
       b'#include <SystemConfiguration/SystemConfiguration.h>\n'
       b'#define SCDynamicStoreCopyProxies(x) ((CFDictionaryRef)NULL)\n')
SKIP = {'thirdparty', 'lib', 'build', 'ios_shims', '.git'}
for f in root.rglob('*'):
    if f.suffix in ('.cpp', '.cc', '.mm', '.m', '.c') and f.is_file():
        if set(f.relative_to(root).parts) & SKIP:
            continue
        data = f.read_bytes()
        if b'SCDynamicStoreCopyProxies' in data:
            f.write_bytes(PRE + data)
            print('proxy patched:', f)

print('patched')
