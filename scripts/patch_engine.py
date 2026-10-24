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
SHIMS = {
    'OpenGL/CGLTypes.h': CGL,
    'OpenGL/OpenGL.h': '#pragma once\n#include <OpenGL/CGLTypes.h>\n',
    'OpenGL/CGLCurrent.h': '#pragma once\n#include <OpenGL/CGLTypes.h>\n',
    'ApplicationServices/ApplicationServices.h':
        '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n'
        '#include <CoreGraphics/CoreGraphics.h>\n#include <CFNetwork/CFNetwork.h>\n',
    'Carbon/Carbon.h': '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n',
    'Cocoa/Cocoa.h': '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\n'
                     '#ifdef __OBJC__\n#import <UIKit/UIKit.h>\n#endif\n',
    'OpenAL/MacOSX_OALExtensions.h': '#pragma once\n',
}
for rel, text in SHIMS.items():
    p = root / 'ios_shims' / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)

# --- точечные патчи ---
edit('public/togles/linuxwin/glbase.h', lambda s: s.replace(
    "#include <OpenGL/CGLCurrent.h>",
    "#ifndef IOS\n#include <OpenGL/CGLCurrent.h>\n#endif"))

# system() недоступен на iOS
p = root / 'vgui2/vgui_controls/FileOpenDialog.cpp'
if p.exists():
    p.write_text('#include <stdlib.h>\n#define system(x) (-1)\n' + p.read_text())

# macOS-only файл Cocoa
p = root / 'togles/wscript'
if p.exists():
    s = p.read_text()
    s2 = re.sub(r"""['"][^'"]*glmgrcocoa\.mm['"]\s*,?""", "", s)
    p.write_text(s2)

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
