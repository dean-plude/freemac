/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: presentation intents and the Markdown initialisers of
 * NSAttributedString, as Apple's API reference describes them (freemac
 * 1.224, Ferry 0.48.0). Markdown isn't read yet: the initialisers answer
 * nil with NSFeatureUnsupportedError (see Foundation.h). Our own code; no
 * Apple code was used. Built without ARC. */
#import "FInternal.h"

NSString *const NSPresentationIntentAttributeName = @"NSPresentationIntent";
NSString *const NSInlinePresentationIntentAttributeName = @"NSInlinePresentationIntent";
NSString *const NSAlternateDescriptionAttributeName = @"NSAlternateDescription";
NSString *const NSImageURLAttributeName = @"NSImageURL";
NSString *const NSLanguageIdentifierAttributeName = @"NSLanguageIdentifier";

@implementation NSPresentationIntent {
    NSPresentationIntentKind _kind;
    NSPresentationIntent *_parent;
    NSInteger _identity, _ordinal, _headerLevel;
    NSString *_languageHint;
}
+ (NSPresentationIntent *)ferryIntent:(NSPresentationIntentKind)kind identity:(NSInteger)identity
                               parent:(NSPresentationIntent *)parent
{
    NSPresentationIntent *i = [[[self alloc] init] autorelease];
    i->_kind = kind;
    i->_identity = identity;
    i->_parent = [parent retain];
    return i;
}
- (void)dealloc
{
    [_parent release];
    [_languageHint release];
    [super dealloc];
}
+ (NSPresentationIntent *)paragraphIntentWithIdentity:(NSInteger)identity nestedInsideIntent:(NSPresentationIntent *)p
{
    return [self ferryIntent:NSPresentationIntentKindParagraph identity:identity parent:p];
}
+ (NSPresentationIntent *)headerIntentWithIdentity:(NSInteger)identity level:(NSInteger)level
                                nestedInsideIntent:(NSPresentationIntent *)p
{
    NSPresentationIntent *i = [self ferryIntent:NSPresentationIntentKindHeader identity:identity parent:p];
    i->_headerLevel = level;
    return i;
}
+ (NSPresentationIntent *)codeBlockIntentWithIdentity:(NSInteger)identity languageHint:(NSString *)hint
                                   nestedInsideIntent:(NSPresentationIntent *)p
{
    NSPresentationIntent *i = [self ferryIntent:NSPresentationIntentKindCodeBlock identity:identity parent:p];
    i->_languageHint = [hint copy];
    return i;
}
+ (NSPresentationIntent *)thematicBreakIntentWithIdentity:(NSInteger)identity nestedInsideIntent:(NSPresentationIntent *)p
{
    return [self ferryIntent:NSPresentationIntentKindThematicBreak identity:identity parent:p];
}
+ (NSPresentationIntent *)orderedListIntentWithIdentity:(NSInteger)identity nestedInsideIntent:(NSPresentationIntent *)p
{
    return [self ferryIntent:NSPresentationIntentKindOrderedList identity:identity parent:p];
}
+ (NSPresentationIntent *)unorderedListIntentWithIdentity:(NSInteger)identity nestedInsideIntent:(NSPresentationIntent *)p
{
    return [self ferryIntent:NSPresentationIntentKindUnorderedList identity:identity parent:p];
}
+ (NSPresentationIntent *)listItemIntentWithIdentity:(NSInteger)identity ordinal:(NSInteger)ordinal
                                  nestedInsideIntent:(NSPresentationIntent *)p
{
    NSPresentationIntent *i = [self ferryIntent:NSPresentationIntentKindListItem identity:identity parent:p];
    i->_ordinal = ordinal;
    return i;
}
+ (NSPresentationIntent *)blockQuoteIntentWithIdentity:(NSInteger)identity nestedInsideIntent:(NSPresentationIntent *)p
{
    return [self ferryIntent:NSPresentationIntentKindBlockQuote identity:identity parent:p];
}
- (NSPresentationIntentKind)intentKind { return _kind; }
- (NSPresentationIntent *)parentIntent { return _parent; }
- (NSInteger)identity { return _identity; }
- (NSInteger)ordinal { return _ordinal; }
- (NSInteger)headerLevel { return _headerLevel; }
- (NSInteger)indentationLevel
{
    /* the lists it is inside, not counting its own */
    NSInteger n = 0;
    for (NSPresentationIntent *p = _parent; p; p = p->_parent)
        if (p->_kind == NSPresentationIntentKindOrderedList || p->_kind == NSPresentationIntentKindUnorderedList)
            n++;
    return n > 0 ? n - 1 : 0;
}
- (NSInteger)column { return 0; }
- (NSInteger)row { return 0; }
- (NSString *)languageHint { return _languageHint; }
- (NSArray *)columnAlignments { return nil; }
- (NSInteger)columnCount { return 0; }
- (BOOL)isEquivalentToPresentationIntent:(NSPresentationIntent *)o
{
    if (o == self)
        return YES;
    if (!o || o->_kind != _kind || o->_ordinal != _ordinal || o->_headerLevel != _headerLevel)
        return NO;
    if (!_parent || !o->_parent)
        return !_parent && !o->_parent;
    return [_parent isEquivalentToPresentationIntent:o->_parent];
}
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[NSPresentationIntent class]] && ((NSPresentationIntent *)o)->_identity == _identity &&
           [self isEquivalentToPresentationIntent:o];
}
- (NSUInteger)hash { return (NSUInteger)_identity * 31 + (NSUInteger)_kind; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeInteger:_kind forKey:@"kind"];
    [c encodeInteger:_identity forKey:@"identity"];
    [c encodeInteger:_ordinal forKey:@"ordinal"];
    [c encodeInteger:_headerLevel forKey:@"headerLevel"];
    [c encodeObject:_languageHint forKey:@"languageHint"];
    [c encodeObject:_parent forKey:@"parent"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _kind = [c decodeIntegerForKey:@"kind"];
        _identity = [c decodeIntegerForKey:@"identity"];
        _ordinal = [c decodeIntegerForKey:@"ordinal"];
        _headerLevel = [c decodeIntegerForKey:@"headerLevel"];
        _languageHint = [[c decodeObjectForKey:@"languageHint"] copy];
        _parent = [[c decodeObjectForKey:@"parent"] retain];
    }
    return self;
}
@end

@implementation NSAttributedStringMarkdownParsingOptions {
    BOOL _allowsExtendedAttributes;
    NSAttributedStringMarkdownInterpretedSyntax _syntax;
    NSAttributedStringMarkdownParsingFailurePolicy _policy;
    NSString *_languageCode;
}
- (void)dealloc
{
    [_languageCode release];
    [super dealloc];
}
- (BOOL)allowsExtendedAttributes { return _allowsExtendedAttributes; }
- (void)setAllowsExtendedAttributes:(BOOL)b { _allowsExtendedAttributes = b; }
- (NSAttributedStringMarkdownInterpretedSyntax)interpretedSyntax { return _syntax; }
- (void)setInterpretedSyntax:(NSAttributedStringMarkdownInterpretedSyntax)s { _syntax = s; }
- (NSAttributedStringMarkdownParsingFailurePolicy)failurePolicy { return _policy; }
- (void)setFailurePolicy:(NSAttributedStringMarkdownParsingFailurePolicy)p { _policy = p; }
- (NSString *)languageCode { return _languageCode; }
- (void)setLanguageCode:(NSString *)c
{
    c = [c copy];
    [_languageCode release];
    _languageCode = c;
}
- (id)copyWithZone:(NSZone *)zone
{
    NSAttributedStringMarkdownParsingOptions *o = [[[self class] alloc] init];
    o->_allowsExtendedAttributes = _allowsExtendedAttributes;
    o->_syntax = _syntax;
    o->_policy = _policy;
    o->_languageCode = [_languageCode copy];
    return o;
}
@end

@implementation NSAttributedString (FerryMarkdown)
- (instancetype)initWithMarkdownString:(NSString *)markdown options:(NSAttributedStringMarkdownParsingOptions *)options
                               baseURL:(NSURL *)baseURL error:(NSError **)error
{
    [self release];
    if (error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError
                                 userInfo:@{NSLocalizedDescriptionKey: @"Markdown isn't read here yet."}];
    return nil;
}
- (instancetype)initWithMarkdown:(NSData *)markdown options:(NSAttributedStringMarkdownParsingOptions *)options
                         baseURL:(NSURL *)baseURL error:(NSError **)error
{
    return [self initWithMarkdownString:nil options:options baseURL:baseURL error:error];
}
- (instancetype)initWithContentsOfMarkdownFileAtURL:(NSURL *)url options:(NSAttributedStringMarkdownParsingOptions *)options
                                            baseURL:(NSURL *)baseURL error:(NSError **)error
{
    return [self initWithMarkdownString:nil options:options baseURL:baseURL error:error];
}
@end
