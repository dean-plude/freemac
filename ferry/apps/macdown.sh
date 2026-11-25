#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/macdown.sh [WORK]
#
# MacDown (github.com/MacDownApp/macdown, MIT), a Markdown editor with a
# live preview, built for Ferry (freemac 1.236, Ferry 0.60.0; it first ran
# in freemac 1.225). It is fetched at the commit freemac's rounds were built
# from, with Prism (its submodule, at the commit it pins), and the pods its
# Podfile names at the commits those rounds built: hoedown 3.0.7, LibYAML,
# handlebars-objc, MASPreferences, PAPreferences, JJPluralForm and
# M13OrderedDictionary. CocoaPods isn't used: handlebars-objc and
# MASPreferences are built as frameworks from their own Xcode projects
# (handlebars-objc's parser made with bison and flex, as Xcode makes it),
# and the other pods' few sources are compiled into the app, with their
# headers where the pods put them. Its updater is Sparkle 1.22.0, which its
# Podfile's "~> 1.18" takes, built as for Spectacle. version.h, which its
# build makes from git's tags, is written from Tools/version.txt. Run it
# with
#
#   ./ferry WORK/build/MacDown/MacDown.app
#
# Needs bison, flex and a host C compiler (for peg-markdown-highlight's
# parser generator, greg). See apps/recipe.sh for WORK and what a recipe
# needs.
recipe_name=macdown
. "$(dirname "$0")/recipe.sh"

fetch macdown https://github.com/MacDownApp/macdown 3e2a2bf101c215c143bf00d9f857965f0ee82487
submodule macdown Dependency/prism https://github.com/PrismJS/prism
fetch hoedown https://github.com/hoedown/hoedown 980b9c549b4348d50b683ecee6abee470b98acda
fetch libyaml https://github.com/yaml/libyaml 1ebd83d894d4fc476a23977e85a2164c28aadf6b
fetch handlebars-objc https://github.com/Bertrand/handlebars-objc e98bb1234c95ff7a88e6fac1c3d1df7f310ce262
fetch MASPreferences https://github.com/shpakovski/MASPreferences 56bafeeabffa78a18620f006f74efbbcde3c45e2
fetch PAPreferences https://github.com/dhennessy/PAPreferences bd83bda4886ded3caa3f8cfbd0368fb8a8439ec6
fetch JJPluralForm https://github.com/junjie/JJPluralForm bd051b253a2c0286c2f1c70a5901f56d4943a02f
fetch M13OrderedDictionary https://github.com/Marxon13/M13OrderedDictionary d74468c3c2c188d774789f562d359305d3eb5646

for t in bison flex cc make; do command -v $t > /dev/null || die "needs $t"; done

build=$work/build/MacDown
rm -rf "$build"
mkdir -p "$build/include" "$build/gen"
m=$src/macdown

# what MacDown's own build phases make: the Markdown highlighter's parser,
# version.h and Prism's files among its resources
say "making peg-markdown-highlight's parser"
make -s -C "$m/Dependency/peg-markdown-highlight" > "$build/gen/pmh.log" 2>&1 ||
    { sed 's/^/    /' "$build/gen/pmh.log" >&2; die "peg-markdown-highlight's parser didn't build"; }
v=$(cat "$m/Tools/version.txt")
printf '#ifndef VERSION_H\n#define VERSION_H\n\nstatic const char * const kMPApplicationShortVersion = "%s";\nstatic const char * const kMPApplicationBundleVersion = "%s";\n\n#endif\n' \
    "$v" 1 > "$m/Dependency/version/version.h"
rm -rf "$m/MacDown/Resources/Prism"
mkdir -p "$m/MacDown/Resources/Prism"
cp -R "$m/Dependency/prism/components" "$m/Dependency/prism/themes" "$m/Dependency/prism/plugins" \
    "$m/Dependency/prism/components.js" "$m/MacDown/Resources/Prism/"

# the pods
sparkle1 d5222353e6d6ee7baf4c18711e5b897fe2ed886a 1.22.0
hb=$src/handlebars-objc/src/handlebars-objc
bison -y --defines="$build/gen/y.tab.h" -o "$build/gen/y.tab.m" "$hb/parser/handlebars-objc.ym" \
    2> "$build/gen/bison.log" || die "handlebars-objc's grammar didn't build"
flex -o "$build/gen/lex.yy.m" "$hb/parser/handlebars-objc.lm" 2> "$build/gen/flex.log" ||
    die "handlebars-objc's lexer didn't build"
# Bison 3 declares the parser's arguments before the grammar's own
# prologue, which imports the syntax tree's classes, so they come first.
# One helper subscripts an id<NSFastEnumeration>, which today's clang
# refuses; it is compiled from a copy with the object cast to id, as the
# Xcode of its day took it.
sed 's/dictionaryLike\[key\]/((id)dictionaryLike)[key]/' "$hb/helpers/HBBuiltinHelpersRegistry.m" \
    > "$build/gen/HBBuiltinHelpersRegistry.m"
xcbuild "$src/handlebars-objc/src/handlebars-objc.xcodeproj" handlebars-objc-osx --name HBHandlebars \
    --cflags "-fno-objc-arc -I $build/gen -include $hb/ast/HBAst.h" \
    --skip HBBuiltinHelpersRegistry.m --add "$build/gen/HBBuiltinHelpersRegistry.m" \
    --add "$build/gen/y.tab.m" --add "$build/gen/lex.yy.m" --ldflags '-framework Foundation'
xcbuild "$src/MASPreferences/MASPreferences.xcodeproj" MASPreferences --ldflags '-framework Cocoa'
mkdir -p "$build/include/hoedown" "$build/include/PAPreferences" "$build/include/JJPluralForm" \
    "$build/include/M13OrderedDictionary"
ln -sf "$src/hoedown/src/"*.h "$build/include/hoedown/"
ln -sf "$src/PAPreferences/PAPreferences/"*.h "$build/include/PAPreferences/"
ln -sf "$src/JJPluralForm/JJPluralForm/"*.h "$build/include/JJPluralForm/"
ln -sf "$src/M13OrderedDictionary/M13OrderedDictionary.h" "$build/include/M13OrderedDictionary/"
ln -sf "$src/libyaml/include/yaml.h" "$build/include/"
pods=
for f in "$src/hoedown/src/"*.c "$src/libyaml/src/"*.c "$src/PAPreferences/PAPreferences/"*.m \
         "$src/JJPluralForm/JJPluralForm/"*.m "$src/M13OrderedDictionary/M13OrderedDictionary.m"; do
    pods="$pods --add $f"
done

# shellcheck disable=SC2086
xcbuild "$m/MacDown.xcodeproj" MacDown $pods \
    --cflags "-I $src/libyaml/src -DYAML_VERSION_MAJOR=0 -DYAML_VERSION_MINOR=2 -DYAML_VERSION_PATCH=5
              -DYAML_VERSION_STRING=\\\"0.2.5\\\"" \
    --ldflags '-framework Cocoa -framework WebKit -framework JavaScriptCore -framework Carbon
               -framework HBHandlebars -framework MASPreferences -framework Sparkle'
a=$build/MacDown.app
embed "$a" "$build/HBHandlebars.framework" "$build/MASPreferences.framework" "$build/Sparkle.framework"
say "done: $a"
