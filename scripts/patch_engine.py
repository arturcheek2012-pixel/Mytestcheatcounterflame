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
print('patched')
