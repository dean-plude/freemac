#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""xcode.py: builds one target of an Xcode project with Ferry's SDK, for the
app recipes in this folder (freemac 1.236, Ferry 0.60.0). Ferry's own
tool: it reads the project file (project.pbxproj, an old-style property
list) as its public format is laid out, and runs sdk/ferry-cc,
sdk/ferry-ibtool and sdk/ferry-actool where Xcode would run its compilers.
It is not Xcode and builds nothing of Apple's.

    xcode.py build PROJECT.xcodeproj TARGET OUT [options]
    xcode.py list PROJECT.xcodeproj

What a build does, for the Release configuration (with its .xcconfig):

- compiles each source of the target's Sources phase (.m, .mm, .c, .cc,
  .cpp) with the target's prefix header, preprocessor definitions, header
  and framework search paths, ARC setting and each file's own compiler
  flags, and with every folder of the project's repository that holds
  headers searched for quoted includes, as Xcode's header maps do;
- links the program: an app's executable, a framework's dynamic library
  (@rpath/NAME.framework/Versions/A/NAME) or a loadable bundle;
- lays out the bundle as Xcode does: Info.plist with the build settings
  filled in, the Resources phase's files (xibs compiled to nibs, asset
  catalogues compiled, .lproj folders kept, folders copied), and for a
  framework its public headers in Headers, so that other targets find
  <NAME/NAME.h> through -F OUT.

Options:
  --kind app|framework|bundle   what to make (from the target's product
                                type by default)
  --name NAME                   the product's name
  --cflags 'FLAGS'              more compiler flags (shell words)
  --ldflags 'FLAGS'             more linker flags
  --skip FILE                   leave a source out (by file name), repeatable
  --add FILE                    compile another source in, repeatable
  --with TARGET                 compile a static library target of the same
                                project in, repeatable
  --no-pch                      don't use the prefix header
  --info KEY=VALUE              set a key in the built Info.plist (a string;
                                YES and NO become booleans), repeatable
  --setting KEY=VALUE           override a build setting, repeatable
  --jobs N                      compile N files at a time (2)
  --keep-going                  link even if some files didn't compile
"""
import argparse
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SDK = os.environ.get('FERRY_SDK_DIR') or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'sdk')
CC = os.path.join(SDK, 'ferry-cc')
IBTOOL = os.path.join(SDK, 'ferry-ibtool')
ACTOOL = os.path.join(SDK, 'ferry-actool')


# ---- the project file -------------------------------------------------------

def parse_plist(text):
    """An old-style (NeXTSTEP) property list, as project.pbxproj is written."""
    i = 0
    n = len(text)
    bare = re.compile(r'[A-Za-z0-9_$+/:.\-<>@]+')

    def ws():
        nonlocal i
        while i < n:
            c = text[i]
            if c in ' \t\r\n':
                i += 1
            elif text.startswith('//', i):
                j = text.find('\n', i)
                i = n if j < 0 else j + 1
            elif text.startswith('/*', i):
                j = text.find('*/', i + 2)
                i = n if j < 0 else j + 2
            else:
                break

    def string():
        nonlocal i
        if text[i] == '"':
            i += 1
            out = []
            while text[i] != '"':
                if text[i] == '\\':
                    i += 1
                    out.append({'n': '\n', 't': '\t'}.get(text[i], text[i]))
                else:
                    out.append(text[i])
                i += 1
            i += 1
            return ''.join(out)
        m = bare.match(text, i)
        if not m:
            raise ValueError('project file: unexpected %r' % text[i:i + 20])
        i = m.end()
        return m.group(0)

    def value():
        nonlocal i
        ws()
        if text[i] == '{':
            i += 1
            d = {}
            while True:
                ws()
                if text[i] == '}':
                    i += 1
                    return d
                k = string()
                ws()
                i += 1  # =
                d[k] = value()
                ws()
                i += 1  # ;
        if text[i] == '(':
            i += 1
            a = []
            while True:
                ws()
                if text[i] == ')':
                    i += 1
                    return a
                a.append(value())
                ws()
                if text[i] == ',':
                    i += 1
        return string()

    return value()


def read_xcconfig(path, seen=None):
    s = {}
    seen = seen or set()
    if path in seen or not os.path.exists(path):
        return s
    seen.add(path)
    for line in open(path, errors='replace'):
        line = line.split('//')[0].strip()
        m = re.match(r'#include\??\s+"([^"]+)"', line)
        if m:
            s.update(read_xcconfig(os.path.join(os.path.dirname(path), m.group(1)), seen))
            continue
        m = re.match(r'([A-Za-z_0-9]+)(\[[^]]*\])?\s*=\s*(.*)', line)
        if m and not m.group(2):
            s[m.group(1)] = m.group(3)
    return s


def inherit(base, layer):
    """Build settings: LAYER over BASE, a $(inherited) in LAYER's values
    standing for BASE's value, as Xcode's levels stack up."""
    out = dict(base)
    for k, v in layer.items():
        if isinstance(v, str):
            v = v.rstrip(';').strip()
        prev = base.get(k, '')
        if isinstance(prev, list):
            prev = ' '.join(prev)
        if isinstance(v, list):
            vv = []
            for x in v:
                if x in ('$(inherited)', '${inherited}'):
                    vv += [prev] if prev else []
                else:
                    vv.append(x)
            v = vv
        elif isinstance(v, str):
            v = re.sub(r'\$[({]inherited[)}]', lambda m: prev, v)
        out[k] = v
    return out


def targets(xcodeproj):
    projfile = os.path.join(xcodeproj, 'project.pbxproj')
    root = os.path.dirname(os.path.abspath(xcodeproj))
    with open(projfile, encoding='utf-8', errors='replace') as f:
        p = parse_plist(f.read())
    objs = p['objects']
    proj = objs[p['rootObject']]
    parent = {}
    for k, o in objs.items():
        if o.get('isa') in ('PBXGroup', 'PBXVariantGroup', 'XCVersionGroup'):
            for c in o.get('children', []):
                parent[c] = k
    projdir = os.path.join(root, proj.get('projectDirPath', '') or '')

    def path_of(ref):
        o = objs[ref]
        tree = o.get('sourceTree', '<group>')
        pth = o.get('path', '')
        if tree == '<group>':
            if ref in parent:
                return os.path.join(path_of(parent[ref]), pth)
            return os.path.join(projdir, pth)
        if tree == 'SOURCE_ROOT':
            return os.path.join(projdir, pth)
        if tree == '<absolute>':
            return pth
        return os.path.join('$(' + tree + ')', pth)

    def settings(cfglist, base):
        cl = objs[cfglist]
        cfgs = [objs[c] for c in cl['buildConfigurations']]
        pick = next((c for c in cfgs if c.get('name') == 'Release'), None)
        if pick is None:
            pick = next((c for c in cfgs if c.get('name') == cl.get('defaultConfigurationName')), cfgs[0])
        s = dict(base)
        if 'baseConfigurationReference' in pick:
            s = inherit(s, read_xcconfig(os.path.normpath(path_of(pick['baseConfigurationReference']))))
        return inherit(s, pick.get('buildSettings', {}))

    psettings = settings(proj['buildConfigurationList'], {})
    out = []
    for t in proj['targets']:
        o = objs[t]
        if o.get('isa') != 'PBXNativeTarget':
            continue
        s = settings(o['buildConfigurationList'], psettings)
        srcs, res, hdrs = [], [], []
        for ph in o.get('buildPhases', []):
            po = objs[ph]
            for bf in po.get('files', []):
                b = objs[bf]
                ref = b.get('fileRef')
                if not ref or ref not in objs:
                    continue
                r = objs[ref]
                if r.get('isa') == 'PBXVariantGroup':
                    paths = [path_of(c) for c in r.get('children', [])]
                else:
                    paths = [path_of(ref)]
                bs = b.get('settings', {})
                for pth in paths:
                    pth = os.path.normpath(pth)
                    if po['isa'] == 'PBXSourcesBuildPhase':
                        srcs.append((pth, bs.get('COMPILER_FLAGS', '')))
                    elif po['isa'] == 'PBXResourcesBuildPhase':
                        res.append(pth)
                    elif po['isa'] == 'PBXHeadersBuildPhase':
                        attrs = bs.get('ATTRIBUTES', [])
                        hdrs.append((pth, 'Public' in attrs, 'Private' in attrs))
        # Xcode 16's synchronized folders: every file under the folder,
        # less the target's membership exceptions
        for g in o.get('fileSystemSynchronizedGroups', []):
            go = objs[g]
            gdir = os.path.normpath(os.path.join(projdir, go.get('path', '')))
            skip = set()
            for ex in go.get('exceptions', []):
                eo = objs[ex]
                if eo.get('target') == t:
                    skip.update(eo.get('membershipExceptions', []))
            for dirpath, dirnames, filenames in os.walk(gdir):
                rel_dir = os.path.relpath(dirpath, gdir)
                keep = []
                for d in sorted(dirnames):
                    rel = os.path.normpath(os.path.join(rel_dir, d))
                    if d.endswith(('.xcassets', '.lproj', '.bundle')):
                        if rel not in skip:
                            if d.endswith('.lproj'):
                                res += [os.path.join(dirpath, d, f) for f in sorted(os.listdir(os.path.join(dirpath, d)))]
                            else:
                                res.append(os.path.join(dirpath, d))
                    elif not d.startswith('.') and not d.endswith(('.framework', '.app')):
                        keep.append(d)
                dirnames[:] = keep
                for f in sorted(filenames):
                    rel = os.path.normpath(os.path.join(rel_dir, f))
                    if rel in skip or f.startswith('.'):
                        continue
                    pth = os.path.join(dirpath, f)
                    if f.endswith(('.m', '.mm', '.c', '.cc', '.cpp', '.swift')):
                        srcs.append((pth, ''))
                    elif not f.endswith(('.h', '.pch', '.entitlements', '.xcconfig', '.plist', '.md')):
                        res.append(pth)
        out.append({'name': o.get('name'), 'product': o.get('productType', ''),
                    'productName': o.get('productName', ''), 'settings': s, 'sources': srcs,
                    'resources': res, 'headers': hdrs, 'root': projdir})
    return out


# ---- build settings ---------------------------------------------------------

def words(v):
    if isinstance(v, list):
        return [w for x in v for w in words(x)]
    try:
        return shlex.split(v)
    except ValueError:
        return v.split()


def xwords(v, env):
    """A setting's words, with the settings in it filled in first."""
    if isinstance(v, list):
        return [w for x in v for w in xwords(x, env)]
    return words(expand(v, env))


def expand(v, env):
    def modify(value, mods):
        for mod in mods:
            if mod == 'rfc1034identifier':
                value = re.sub(r'[^A-Za-z0-9.-]', '-', value)
            elif mod in ('identifier', 'c99extidentifier'):
                value = re.sub(r'[^A-Za-z0-9_]', '_', value)
            elif mod == 'lower':
                value = value.lower()
            elif mod == 'upper':
                value = value.upper()
        return value

    def sub(m):
        name = m.group(1) or m.group(2) or m.group(3)
        name, *mods = name.split(':')
        return modify(env.get(name, ''), mods)
    for _ in range(5):
        v2 = re.sub(r'\$\(([A-Za-z_0-9:]+)\)|\$\{([A-Za-z_0-9:]+)\}|\$([A-Za-z_][A-Za-z_0-9]*)', sub, v)
        if v2 == v:
            break
        v = v2
    return v


def environment(t, xcodeproj, out, overrides):
    s = dict(t['settings'])
    s.update(overrides)
    root = t['root']
    name = s.get('PRODUCT_NAME', t['productName'])
    env = {'SRCROOT': root, 'PROJECT_DIR': root, 'SOURCE_ROOT': root,
           'PROJECT_NAME': os.path.basename(xcodeproj)[:-len('.xcodeproj')], 'TARGET_NAME': t['name'],
           'inherited': '', 'BUILT_PRODUCTS_DIR': out, 'CONFIGURATION_BUILD_DIR': out,
           'CONFIGURATION': 'Release', 'PODS_ROOT': os.path.join(root, 'Pods'),
           'SDKROOT': SDK, 'DEVELOPER_DIR': '/nonexistent', 'PLATFORM_DIR': '/nonexistent',
           'DEVELOPMENT_LANGUAGE': 'en', 'MACOSX_DEPLOYMENT_TARGET': s.get('MACOSX_DEPLOYMENT_TARGET', '10.13'),
           'CURRENT_PROJECT_VERSION': '1'}
    for k, v in s.items():
        if isinstance(v, str):
            env.setdefault(k, v)
        elif isinstance(v, list):
            env.setdefault(k, ' '.join(v))
    env['PRODUCT_NAME'] = expand(name, env) or t['productName']
    for k in list(env):
        if isinstance(env[k], str) and '$' in env[k]:
            env[k] = expand(env[k], env)
    env['EXECUTABLE_NAME'] = env['PRODUCT_NAME']
    env['PRODUCT_MODULE_NAME'] = re.sub(r'\W', '_', env['PRODUCT_NAME'])
    return s, env


def header_dirs(repo):
    dirs = []
    for d, sub, files in os.walk(repo):
        sub[:] = sorted(x for x in sub if not x.startswith('.') and not x.endswith(('.xcassets', '.lproj')))
        if any(f.endswith('.h') for f in files):
            dirs.append(d)
    return dirs


def compile_flags(s, env, repo, out):
    flags = []
    if s.get('CLANG_ENABLE_OBJC_ARC', 'NO') == 'YES':
        flags.append('-fobjc-arc')
    elif s.get('CLANG_ENABLE_OBJC_WEAK', 'NO') == 'YES':
        flags.append('-fobjc-weak')
    if s.get('ENABLE_STRICT_OBJC_MSGSEND', 'NO') == 'YES':
        flags.append('-DOBJC_OLD_DISPATCH_PROTOTYPES=0')
    pch = None
    if s.get('GCC_PREFIX_HEADER'):
        pch = expand(s['GCC_PREFIX_HEADER'], env)
        m = re.match(r'(?:\$\(SYSTEM_LIBRARY_DIR\)|/System/Library)/Frameworks/(\w+)\.framework/Headers/(.+)$',
                     s['GCC_PREFIX_HEADER'])
        if m:
            # a framework's own header as the prefix header (Ferry's SDK
            # has it as <AppKit/AppKit.h>)
            pch = '%s/%s' % m.groups()
        elif not os.path.isabs(pch):
            pch = os.path.join(env['SRCROOT'], pch)
        if not m and not os.path.exists(pch):
            pch = None
    for d in xwords(s.get('GCC_PREPROCESSOR_DEFINITIONS', []), env):
        if d:
            flags.append('-D' + d)

    def paths(key, opt):
        res = []
        for d in xwords(s.get(key, []), env):
            if not d:
                continue
            rec = d.endswith('/**')
            if rec:
                d = d[:-3]
            if not os.path.isabs(d):
                d = os.path.join(env['SRCROOT'], d)
            if not os.path.isdir(d):
                continue
            res += [opt, d]
            if rec:
                for sd, sub, _ in os.walk(d):
                    sub[:] = sorted(x for x in sub if not x.startswith('.'))
                    if sd != d:
                        res += [opt, sd]
        return res
    flags += paths('USER_HEADER_SEARCH_PATHS', '-iquote')
    flags += paths('HEADER_SEARCH_PATHS', '-I')
    flags += ['-I', os.path.join(out, 'include')]
    flags += paths('FRAMEWORK_SEARCH_PATHS', '-F')
    flags += ['-F', out]
    for d in header_dirs(repo):
        flags += ['-iquote', d]
    other = xwords(s.get('OTHER_CFLAGS', []), env)
    flags += [x for x in other if x.startswith(('-D', '-I', '-f', '-W', '-U')) and x != '-fembed-bitcode']
    return flags, pch


# ---- building ---------------------------------------------------------------

def run(argv, log=None):
    r = subprocess.run(argv, capture_output=True, text=True)
    if log is not None:
        log.write(' '.join(shlex.quote(a) for a in argv) + '\n' + r.stdout + r.stderr)
    return r.returncode, r.stdout + r.stderr


def repo_of(xcodeproj):
    """The repository the project is in: the folder above it holding .git,
    or the project's own folder."""
    d = os.path.dirname(os.path.abspath(xcodeproj))
    probe = d
    while probe != '/':
        if os.path.exists(os.path.join(probe, '.' + 'git')):
            return probe
        probe = os.path.dirname(probe)
    return d


def case_link(name, repo, casedir):
    """Finds the header NAME (a path like "X.h" or "Dir/X.h") under REPO in
    another case, and links it into CASEDIR under the asked-for name."""
    want = name.lower()
    base = os.path.basename(want)
    found = []
    for d, sub, files in os.walk(repo):
        sub[:] = [x for x in sub if not x.startswith('.')]
        for f in files:
            if f.lower() == base:
                p = os.path.join(d, f)
                # the whole path matching first, then the file's name (a
                # framework's <NAME/X.h>)
                found.append((not p.lower().endswith('/' + want), p))
    link = os.path.join(casedir, name)
    if not found:
        return False
    os.makedirs(os.path.dirname(link), exist_ok=True)
    try:
        os.symlink(min(found)[1], link)
    except FileExistsError:
        pass  # made for another file meanwhile
    return True


def header_case(hdir, name):
    """A framework's headers that import <NAME/X.h> where the file is named
    in another case: a copy of the file under the asked-for name, as a
    Mac's disk would find it."""
    if not os.path.isdir(hdir):
        return
    have = {f.lower(): f for f in os.listdir(hdir)}
    for f in list(have.values()):
        try:
            text = open(os.path.join(hdir, f), errors='replace').read()
        except OSError:
            continue
        for want in re.findall(r'[<"]%s/([^>"/]+\.h)[>"]' % re.escape(name), text):
            if want not in have.values() and want.lower() in have:
                shutil.copy(os.path.join(hdir, have[want.lower()]), os.path.join(hdir, want))


def compile_all(t, s, env, args, objdir, log, more=True):
    repo = repo_of(args.project)
    flags, pch = compile_flags(s, env, repo, args.out)
    if args.no_pch:
        pch = None
    extra = words(args.cflags or '')
    sources = [(p, f) for p, f in t['sources'] if os.path.basename(p) not in set(args.skip)]
    if more:
        sources += [(os.path.abspath(p), '') for p in args.add]
    os.makedirs(objdir, exist_ok=True)
    casedir = os.path.join(objdir, 'case')

    def one(item):
        src, fflags = item
        if not src.endswith(('.m', '.mm', '.c', '.cc', '.cpp')):
            return src, None, 0, ''
        obj = os.path.join(objdir, re.sub(r'[^A-Za-z0-9_.]', '_', os.path.relpath(src, repo)) + '.o')
        f = list(flags)
        if src.endswith(('.c', '.cc', '.cpp')):
            f = [x for x in f if x != '-fobjc-arc']
        base = [CC, '-c', '-O1', '-g0', '-fblocks', '-Wno-everything']
        argv = base + f + (['-include', pch] if pch else []) + words(fflags) + extra + [src, '-o', obj]
        code, msg = run(argv)
        if code and pch and src.endswith(('.c', '.cc', '.cpp')):
            # Xcode builds the prefix header for each language; a C file
            # doesn't get an Objective-C one
            argv = base + f + words(fflags) + extra + [src, '-o', obj]
            code, msg = run(argv)
        tried = set()
        for _ in range(8):
            # a header named in another case than its file's, which a Mac's
            # disk finds: a link of the right case, in the folder above
            m = re.search(r"'([^']+\.h)' file not found", msg) if code else None
            if not m or m.group(1) in tried or not case_link(m.group(1), repo, casedir):
                break
            tried.add(m.group(1))
            if casedir not in argv:
                argv[1:1] = ['-iquote', casedir, '-I', casedir]
            code, msg = run(argv)
        return src, obj, code, ' '.join(shlex.quote(a) for a in argv) + '\n' + msg

    with ThreadPoolExecutor(args.jobs) as ex:
        res = list(ex.map(one, sources))
    objs, bad = [], []
    for src, obj, code, msg in res:
        if obj is None:
            continue
        log.write(msg)
        if code:
            first = [l for l in msg.splitlines() if 'error' in l][:1]
            bad.append((os.path.relpath(src, repo), first[0] if first else msg.strip()[-200:]))
        else:
            objs.append(obj)
    return objs, bad


def compile_resources(t, s, env, resdir, contents, log):
    notes = []
    os.makedirs(resdir, exist_ok=True)
    catalogs = []
    for r in t['resources']:
        r = expand(r, env)
        parent = os.path.basename(os.path.dirname(r))
        dest = resdir
        if parent.endswith('.lproj'):
            dest = os.path.join(resdir, parent)
            os.makedirs(dest, exist_ok=True)
        name = os.path.basename(r)
        if not os.path.exists(r):
            notes.append('missing resource ' + os.path.relpath(r, t['root']))
            continue
        if name.endswith('.xib'):
            code, msg = run([sys.executable, '-I', IBTOOL, '--compile', os.path.join(dest, name[:-4] + '.nib'), r], log)
            if code:
                notes.append('%s: %s' % (name, msg.strip().splitlines()[-1] if msg.strip() else 'failed'))
        elif name.endswith('.nib') and os.path.isdir(r):
            k = os.path.join(r, 'keyedobjects.nib')
            if os.path.exists(k):
                shutil.copy(k, os.path.join(dest, name))
        elif name.endswith('.xcassets'):
            catalogs.append(r)
        elif name.endswith('.storyboard'):
            notes.append('storyboard left out: ' + name)
        elif name.endswith(('.xcdatamodeld', '.xcdatamodel', '.xcmappingmodel')):
            notes.append('data model left out: ' + name)
        elif os.path.isdir(r):
            shutil.copytree(r, os.path.join(dest, name), dirs_exist_ok=True, symlinks=True)
        else:
            shutil.copy(r, os.path.join(dest, name))
    partial = {}
    if catalogs:
        part = os.path.join(os.path.dirname(resdir), 'assets-partial.plist')
        argv = [sys.executable, '-I', ACTOOL, '--compile', resdir]
        icon = s.get('ASSETCATALOG_COMPILER_APPICON_NAME')
        if icon:
            argv += ['--app-icon', expand(icon, env), '--output-partial-info-plist', part]
        code, msg = run(argv + catalogs, log)
        if code:
            notes.append('asset catalogue: ' + msg.strip()[-300:])
        if os.path.exists(part):
            with open(part, 'rb') as f:
                partial = plistlib.load(f)
            os.remove(part)
    return notes, partial


def fill(v, env):
    if isinstance(v, str):
        return expand(v, env)
    if isinstance(v, list):
        return [fill(x, env) for x in v]
    if isinstance(v, dict):
        return {k: fill(x, env) for k, x in v.items()}
    return v


def build(args):
    ts = targets(args.project)
    match = [x for x in ts if x['name'] == args.target]
    if not match:
        sys.exit('xcode.py: no target %r in %s (it has: %s)' % (args.target, args.project, ', '.join(x['name'] for x in ts)))
    t = match[0]
    overrides = dict(kv.split('=', 1) for kv in args.setting)
    os.makedirs(args.out, exist_ok=True)
    args.out = os.path.abspath(args.out)
    s, env = environment(t, args.project, args.out, overrides)
    kind = args.kind or ('framework' if t['product'].endswith('.framework') else
                         'bundle' if t['product'].endswith('.bundle') else
                         'dylib' if t['product'].endswith('library.dynamic') else 'app')
    name = args.name or env['PRODUCT_NAME']
    env['PRODUCT_NAME'] = env['EXECUTABLE_NAME'] = name
    ext = s.get('WRAPPER_EXTENSION') if kind == 'bundle' else None
    ext = args.ext or ext or {'app': 'app', 'framework': 'framework', 'bundle': 'bundle', 'dylib': 'dylib'}[kind]
    logpath = os.path.join(args.out, 'logs', re.sub(r'\W', '_', args.target) + '.log')
    os.makedirs(os.path.dirname(logpath), exist_ok=True)
    log = open(logpath, 'w')
    if kind == 'framework':
        # a framework's sources include its own headers as <NAME/X.h>,
        # which Xcode copies into the product before compiling
        stage = os.path.join(args.out, 'obj', re.sub(r'\W', '_', args.target), 'stage')
        shutil.rmtree(stage, ignore_errors=True)
        for sub_dir in ('Headers', 'PrivateHeaders'):
            os.makedirs(os.path.join(stage, name + '.framework', sub_dir))
        for h, public, private in t['headers']:
            link = os.path.join(stage, name + '.framework', 'PrivateHeaders' if private else 'Headers',
                                os.path.basename(h))
            if os.path.exists(h) and not os.path.lexists(link):
                # a link, so that a header imported both ways is one file
                os.symlink(os.path.abspath(h), link)
        args.cflags = (args.cflags or '') + ' -F ' + shlex.quote(stage)
    objs, bad = compile_all(t, s, env, args, os.path.join(args.out, 'obj', re.sub(r'\W', '_', args.target)), log)
    for other in args.with_target:
        # a static library target of the same project, linked in
        ot = [x for x in ts if x['name'] == other][0]
        os_, oenv = environment(ot, args.project, args.out, overrides)
        o2, b2 = compile_all(ot, os_, oenv, args, os.path.join(args.out, 'obj', re.sub(r'\W', '_', other)), log, False)
        objs += o2
        bad += b2
    print('%s: %d files compiled, %d failed' % (args.target, len(objs), len(bad)))
    for src, err in bad:
        print('  %s: %s' % (src, err))
    if bad and not args.keep_going:
        sys.exit('xcode.py: %s didn\'t compile (its log: %s)' % (args.target, logpath))

    product = os.path.join(args.out, name + '.' + ext)
    if os.path.islink(product) or os.path.isfile(product):
        os.remove(product)
    shutil.rmtree(product, ignore_errors=True)
    ldflags = words(args.ldflags or '') + ['-F', args.out, '-L', args.out]
    if kind == 'framework':
        contents = os.path.join(product, 'Versions', 'A')
        exe = os.path.join(contents, name)
        resdir = os.path.join(contents, 'Resources')
        plist_path = os.path.join(resdir, 'Info.plist')
        link = ['-dynamiclib', '-install_name', '@rpath/%s.framework/Versions/A/%s' % (name, name),
                '-Wl,-rpath,@loader_path/../../..']
    elif kind == 'dylib':
        contents = args.out
        exe = product
        resdir = plist_path = None
        link = ['-dynamiclib', '-install_name', '@rpath/' + os.path.basename(product)]
    else:
        contents = os.path.join(product, 'Contents')
        exe = os.path.join(contents, 'MacOS', name)
        resdir = os.path.join(contents, 'Resources')
        plist_path = os.path.join(contents, 'Info.plist')
        link = (['-bundle', '-Wl,-undefined,dynamic_lookup'] if kind == 'bundle'
                else ['-Wl,-rpath,@executable_path/../Frameworks'])
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    code, msg = run([CC, '-o', exe] + link + objs + ldflags, log)
    if code:
        undefined = sorted(set(re.findall(r'undefined symbol: (\S+)', msg)))
        for u in undefined[:40]:
            print('  undefined:', u)
        if not undefined:
            print(msg[-2000:])
        sys.exit('xcode.py: %s didn\'t link (its log: %s)' % (args.target, logpath))
    if kind == 'dylib':
        print('built', product)
        return
    notes, partial = compile_resources(t, s, env, resdir, contents, log)
    info = {}
    ip = expand(s.get('INFOPLIST_FILE', ''), env)
    if ip:
        ipath = ip if os.path.isabs(ip) else os.path.join(t['root'], ip)
        try:
            with open(ipath, 'rb') as f:
                info = plistlib.load(f)
        except Exception as e:
            notes.append('Info.plist not read: %s' % e)
    info = fill(info, env)
    for k, v in (('CFBundleExecutable', name), ('CFBundleName', name), ('CFBundleInfoDictionaryVersion', '6.0'),
                 ('CFBundlePackageType', {'app': 'APPL', 'framework': 'FMWK', 'bundle': 'BNDL'}[kind]),
                 ('CFBundleIdentifier', env.get('PRODUCT_BUNDLE_IDENTIFIER') or 'org.example.' + name)):
        if not info.get(k):
            info[k] = v
    if not info.get('CFBundleShortVersionString') and env.get('MARKETING_VERSION'):
        info['CFBundleShortVersionString'] = env['MARKETING_VERSION']
    if not info.get('CFBundleVersion'):
        info['CFBundleVersion'] = '1'
    info.update(partial)
    for kv in args.info:
        k, v = kv.split('=', 1)
        info[k] = {'YES': True, 'NO': False}.get(v, v)
    os.makedirs(os.path.dirname(plist_path), exist_ok=True)
    with open(plist_path, 'wb') as f:
        plistlib.dump(info, f)
    if kind == 'framework':
        hdir = os.path.join(contents, 'Headers')
        pdir = os.path.join(contents, 'PrivateHeaders')
        for h, public, private in t['headers']:
            if (public or private) and os.path.exists(h):
                d = hdir if public else pdir
                os.makedirs(d, exist_ok=True)
                shutil.copy(h, d)
        for d in (hdir, pdir):
            header_case(d, name)
        os.symlink('A', os.path.join(product, 'Versions', 'Current'))
        for x in [name, 'Resources', 'Headers', 'PrivateHeaders']:
            if os.path.exists(os.path.join(contents, x)):
                os.symlink('Versions/Current/' + x, os.path.join(product, x))
    for n in notes:
        print('  note:', n)
    print('built', product)


def main():
    ap = argparse.ArgumentParser(description='Builds an Xcode target with Ferry\'s SDK.')
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('project')
    b.add_argument('target')
    b.add_argument('out')
    b.add_argument('--kind', choices=['app', 'framework', 'bundle', 'dylib'])
    b.add_argument('--name')
    b.add_argument('--ext')
    b.add_argument('--cflags')
    b.add_argument('--ldflags')
    b.add_argument('--skip', action='append', default=[])
    b.add_argument('--add', action='append', default=[])
    b.add_argument('--with', dest='with_target', action='append', default=[])
    b.add_argument('--info', action='append', default=[])
    b.add_argument('--setting', action='append', default=[])
    b.add_argument('--no-pch', action='store_true')
    b.add_argument('--jobs', type=int, default=2)
    b.add_argument('--keep-going', action='store_true')
    ls = sub.add_parser('list')
    ls.add_argument('project')
    argv = []
    it = iter(sys.argv[1:])
    for a in it:
        if a in ('--cflags', '--ldflags', '--setting', '--info', '--add', '--skip'):
            a += '=' + next(it, '')  # a value may start with "-"
        argv.append(a)
    args = ap.parse_args(argv)
    if args.cmd == 'list':
        for t in targets(args.project):
            print('%s\t%s\t%d sources' % (t['name'], t['product'], len(t['sources'])))
        return
    build(args)


if __name__ == '__main__':
    main()
