/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: date pickers (NSDatePicker, NSDatePickerCell), written
 * from Apple's public API documentation.
 *
 * The text styles show the date and time as a row of parts in the
 * locale's order (from NSDateFormatter's dateFormatFromTemplate:, so
 * "M/d/yyyy, h:mm:ss AM" in English), the one being edited highlighted,
 * with a stepper at the right unless the style is plain text. Clicking a
 * part, or Tab and the left and right arrows, choose the part; the up and
 * down arrows and the stepper change it, wrapping within that part (the
 * 31st becomes the 1st, not the next month's); digits type a new value,
 * moving on to the next part once no more digits could fit; "a" and "p"
 * choose AM and PM. The graphical style is a month's calendar, with a
 * clock face beside it when the time is shown: clicking a day chooses it
 * (dragging over days chooses a range in range mode), the arrows go to
 * the month before or after, the dot between them to today, and the arrow
 * keys move by a day or a week.
 *
 * Every change is kept between minDate and maxDate, offered to the
 * delegate's datePickerCell:validateProposedDateValue:timeInterval:, and
 * sent as the action. A text style picker with presentsCalendarOverlay
 * opens a calendar in a popover when its date is clicked.
 *
 * In a nib the cell keeps its date under "NSContents", its elements under
 * "NSDatePickerElements", its style under "NSDatePickerType", its mode
 * under "NSDatePickerMode", and "NSMinDate", "NSMaxDate",
 * "NSTimeInterval", "NSTimeZone", "NSDrawsBackground",
 * "NSBackgroundColor" and "NSTextColor" (names from developers'
 * descriptions of the format, not checked against a nib from a Mac; no
 * Apple code was read). */
#import "AInternal.h"

typedef enum { SegLiteral, SegEra, SegYear, SegMonth, SegDay, SegHour, SegMinute, SegSecond, SegAMPM, SegZone } SegKind;
enum { max_segments = 24 };
typedef struct {
    SegKind kind;
    NSString *text;   /* autoreleased */
    NSRect rect;
} Segment;

static const CGFloat stepper_width = 19, cal_cell_w = 20, cal_cell_h = 18, cal_header = 24, cal_weekdays = 16,
                     cal_margin = 6, clock_size = 112;

static BOOL editable_kind(SegKind k) { return k != SegLiteral && k != SegEra && k != SegZone; }

@interface NSDatePickerCell (FerryDatePicker)
- (NSInteger)_selected;
- (void)_setSelected:(NSInteger)i;
- (BOOL)_stepSelected:(NSInteger)dir;
- (BOOL)_typeDigit:(NSInteger)d;
- (BOOL)_typeAMPM:(BOOL)pm;
- (void)_commitTyping;
- (void)_clearTyping;
- (NSInteger)_moveSelection:(NSInteger)dir;
- (NSInteger)_segmentAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view;
- (NSInteger)_firstEditable;
- (BOOL)_isGraphical;
- (BOOL)_proposeDate:(NSDate *)date interval:(NSTimeInterval)interval;
- (NSRect)_stepperRectInFrame:(NSRect)frame;
- (NSRect)_calendarRectInFrame:(NSRect)frame;
- (NSDate *)_dayAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view;
- (NSInteger)_calendarControlAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view;
- (BOOL)_moveDays:(NSInteger)days months:(NSInteger)months;
- (NSCalendar *)_calendar;
- (BOOL)_dateSegmentAt:(NSInteger)i;
- (void)_setFocused:(BOOL)f;
- (BOOL)_hasTime;
- (BOOL)_hasDate;
@end

@interface NSDatePicker (FerryDatePicker)
- (NSInteger)_pressedHalf;
@end

/* ---- the cell: the date, its parts, stepping and typing, drawing ------------------------- */

@implementation NSDatePickerCell {
    NSDatePickerStyle _style;
    NSDatePickerMode _mode;
    NSDatePickerElementFlags _elements;
    NSDate *_date, *_min, *_max;
    NSTimeInterval _interval;
    NSCalendar *_calendar;
    NSLocale *_locale;
    NSTimeZone *_zone;
    BOOL _drawsBackground, _focused;
    NSColor *_background, *_textColor;
    id _delegate;
    NSInteger _selected;      /* the part being edited, or -1 */
    NSMutableString *_typed;  /* digits typed into it so far */
}

- (void)_setUp
{
    _style = NSDatePickerStyleTextFieldAndStepper;
    _elements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinuteSecond;
    _date = [[NSDate date] retain];
    _drawsBackground = YES;
    _selected = -1;
    _typed = [[NSMutableString alloc] init];
}
- (instancetype)initTextCell:(NSString *)s
{
    if ((self = [super initTextCell:@""])) {
        [self _setUp];
        [self setFont:ADefaultFont()];
    }
    return self;
}
- (instancetype)init { return [self initTextCell:@""]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setUp];
    if (![self font])
        [self setFont:ADefaultFont()];
    id d = [coder decodeObjectForKey:@"NSContents"];
    if ([d isKindOfClass:[NSDate class]]) {
        id wasDate = _date;
        _date = [d copy];
        [wasDate release];
    }
    if ([coder containsValueForKey:@"NSDatePickerElements"])
        _elements = [coder decodeIntegerForKey:@"NSDatePickerElements"];
    _style = [coder decodeIntegerForKey:@"NSDatePickerType"];
    _mode = [coder decodeIntegerForKey:@"NSDatePickerMode"];
    id min = [coder decodeObjectForKey:@"NSMinDate"], max = [coder decodeObjectForKey:@"NSMaxDate"];
    if ([min isKindOfClass:[NSDate class]])
        _min = [min copy];
    if ([max isKindOfClass:[NSDate class]])
        _max = [max copy];
    _interval = [coder decodeDoubleForKey:@"NSTimeInterval"];
    id zone = [coder decodeObjectForKey:@"NSTimeZone"];
    if ([zone isKindOfClass:[NSTimeZone class]])
        _zone = [zone copy];
    if ([coder containsValueForKey:@"NSDrawsBackground"])
        _drawsBackground = [coder decodeBoolForKey:@"NSDrawsBackground"];
    id bg = [coder decodeObjectForKey:@"NSBackgroundColor"], fg = [coder decodeObjectForKey:@"NSTextColor"];
    if ([bg isKindOfClass:[NSColor class]])
        _background = [bg copy];
    if ([fg isKindOfClass:[NSColor class]])
        _textColor = [fg copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_date forKey:@"NSContents"];
    [coder encodeInteger:_elements forKey:@"NSDatePickerElements"];
    [coder encodeInteger:_style forKey:@"NSDatePickerType"];
    [coder encodeInteger:_mode forKey:@"NSDatePickerMode"];
    if (_min)
        [coder encodeObject:_min forKey:@"NSMinDate"];
    if (_max)
        [coder encodeObject:_max forKey:@"NSMaxDate"];
    [coder encodeDouble:_interval forKey:@"NSTimeInterval"];
    if (_zone)
        [coder encodeObject:_zone forKey:@"NSTimeZone"];
    [coder encodeBool:_drawsBackground forKey:@"NSDrawsBackground"];
    if (_background)
        [coder encodeObject:_background forKey:@"NSBackgroundColor"];
    if (_textColor)
        [coder encodeObject:_textColor forKey:@"NSTextColor"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSDatePickerCell *c = [super copyWithZone:zone];
    c->_style = _style;
    c->_mode = _mode;
    c->_elements = _elements;
    [c->_date release];
    c->_date = [_date copy];
    c->_min = [_min copy];
    c->_max = [_max copy];
    c->_interval = _interval;
    c->_calendar = [_calendar copy];
    c->_locale = [_locale copy];
    c->_zone = [_zone copy];
    c->_drawsBackground = _drawsBackground;
    c->_background = [_background copy];
    c->_textColor = [_textColor copy];
    c->_delegate = _delegate;
    return c;
}
- (void)dealloc
{
    [_date release];
    [_min release];
    [_max release];
    [_calendar release];
    [_locale release];
    [_zone release];
    [_background release];
    [_textColor release];
    [_typed release];
    [super dealloc];
}

#define COPY_SETTER(setter, ivar)  \
    -(void)setter(id)v             \
    {                              \
        v = [v copy];              \
        [ivar release];            \
        ivar = v;                  \
    }
- (NSDatePickerStyle)datePickerStyle { return _style; }
- (void)setDatePickerStyle:(NSDatePickerStyle)s { _style = s; }
- (NSDatePickerMode)datePickerMode { return _mode; }
- (void)setDatePickerMode:(NSDatePickerMode)m { _mode = m; }
- (NSDatePickerElementFlags)datePickerElements { return _elements; }
- (void)setDatePickerElements:(NSDatePickerElementFlags)e
{
    _elements = e;
    _selected = -1;
    [_typed setString:@""];
}
- (NSDate *)dateValue { return _date; }
- (void)setDateValue:(NSDate *)d
{
    if (!d)
        return;
    if (_min && [d compare:_min] == NSOrderedAscending)
        d = _min;
    if (_max && [d compare:_max] == NSOrderedDescending)
        d = _max;
    d = [d copy];
    [_date release];
    _date = d;
}
- (id)objectValue { return _date; }
- (void)setObjectValue:(id)v
{
    if ([v isKindOfClass:[NSDate class]])
        [self setDateValue:v];
}
/* A new limit brings the date within it. */
- (NSDate *)minDate { return _min; }
- (void)setMinDate:(NSDate *)d
{
    d = [d copy];
    [_min release];
    _min = d;
    [self setDateValue:_date];
}
- (NSDate *)maxDate { return _max; }
- (void)setMaxDate:(NSDate *)d
{
    d = [d copy];
    [_max release];
    _max = d;
    [self setDateValue:_date];
}
- (NSTimeInterval)timeInterval { return _mode == NSDatePickerModeRange ? _interval : 0; }
- (void)setTimeInterval:(NSTimeInterval)t { _interval = t; }
- (NSCalendar *)calendar { return _calendar; }
COPY_SETTER(setCalendar:, _calendar)
- (NSLocale *)locale { return _locale; }
COPY_SETTER(setLocale:, _locale)
- (NSTimeZone *)timeZone { return _zone; }
COPY_SETTER(setTimeZone:, _zone)
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f { _drawsBackground = f; }
- (NSColor *)backgroundColor { return _background ?: [NSColor controlBackgroundColor]; }
COPY_SETTER(setBackgroundColor:, _background)
- (NSColor *)textColor { return _textColor ?: [NSColor controlTextColor]; }
COPY_SETTER(setTextColor:, _textColor)
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSString *)stringValue
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateFormat:[self _pattern]];
    [f setTimeZone:[self _zone]];
    [f setCalendar:[self _calendar]];
    return [f stringFromDate:_date];
}

- (NSCalendar *)_calendar
{
    NSCalendar *c = [[(_calendar ?: [NSCalendar currentCalendar]) copy] autorelease];
    [c setTimeZone:[self _zone]];
    return c;
}
- (NSTimeZone *)_zone { return _zone ?: [NSTimeZone defaultTimeZone]; }
- (NSLocale *)_locale { return _locale ?: [NSLocale currentLocale]; }
- (BOOL)_isGraphical { return _style == NSDatePickerStyleClockAndCalendar; }
- (BOOL)_hasDate { return (_elements & NSDatePickerElementFlagYearMonth) != 0; }
- (BOOL)_hasTime { return (_elements & NSDatePickerElementFlagHourMinute) != 0; }
- (NSInteger)_selected { return _selected; }
- (void)_setSelected:(NSInteger)i
{
    if (i != _selected)
        [self _commitTyping];
    _selected = i;
}
- (void)_setFocused:(BOOL)f { _focused = f; }

/* ---- the parts ---- */

/* The pattern of the parts, in the locale's order. */
- (NSString *)_pattern
{
    NSMutableArray *parts = [NSMutableArray array];
    NSLocale *locale = [self _locale];
    if ([self _hasDate]) {
        BOOL day = (_elements & NSDatePickerElementFlagYearMonthDay) == NSDatePickerElementFlagYearMonthDay;
        NSString *tmpl = day ? @"yMd" : @"yM";
        if (_elements & NSDatePickerElementFlagEra)
            tmpl = [@"G" stringByAppendingString:tmpl];
        NSString *p = [NSDateFormatter dateFormatFromTemplate:tmpl options:0 locale:locale];
        [parts addObject:p ?: (day ? @"M/d/y" : @"M/y")];
    }
    if ([self _hasTime]) {
        BOOL seconds = (_elements & NSDatePickerElementFlagHourMinuteSecond) == NSDatePickerElementFlagHourMinuteSecond;
        NSString *tmpl = seconds ? @"jms" : @"jm";
        if (_elements & NSDatePickerElementFlagTimeZone)
            tmpl = [tmpl stringByAppendingString:@"z"];
        NSString *p = [NSDateFormatter dateFormatFromTemplate:tmpl options:0 locale:locale];
        [parts addObject:p ?: (seconds ? @"h:mm:ss a" : @"h:mm a")];
    }
    return [parts componentsJoinedByString:@", "];
}

/* The parts and their text, from the date (and what's being typed). */
- (NSInteger)_segments:(Segment *)segs
{
    NSString *pattern = [self _pattern];
    NSCalendar *cal = [self _calendar];
    NSDateComponents *c = [cal components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                          NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                                 fromDate:_date];
    NSInteger n = 0;
    NSUInteger len = [pattern length];
    BOOL twelve = [pattern rangeOfString:@"h"].location != NSNotFound || [pattern rangeOfString:@"K"].location != NSNotFound;
    for (NSUInteger i = 0; i < len && n < max_segments;) {
        unichar ch = [pattern characterAtIndex:i];
        NSUInteger j = i;
        if (ch == '\'') {
            /* quoted text */
            NSMutableString *lit = [NSMutableString string];
            j++;
            while (j < len && [pattern characterAtIndex:j] != '\'')
                [lit appendFormat:@"%C", [pattern characterAtIndex:j++]];
            j++;
            segs[n++] = (Segment){SegLiteral, lit, NSZeroRect};
            i = j;
            continue;
        }
        BOOL letter = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
        while (j < len && (letter ? [pattern characterAtIndex:j] == ch
                                  : ![[NSCharacterSet letterCharacterSet] characterIsMember:[pattern characterAtIndex:j]] &&
                                        [pattern characterAtIndex:j] != '\''))
            j++;
        NSUInteger count = j - i;
        Segment s = {SegLiteral, nil, NSZeroRect};
        if (!letter) {
            s.text = [pattern substringWithRange:NSMakeRange(i, count)];
        } else {
            switch (ch) {
            case 'G': s.kind = SegEra; s.text = [cal eraSymbols][[c era] < (NSInteger)[[cal eraSymbols] count] ? [c era] : 0]; break;
            case 'y': case 'u': case 'Y': s.kind = SegYear; s.text = [NSString stringWithFormat:@"%ld", (long)[c year]]; break;
            case 'M': case 'L': s.kind = SegMonth; s.text = [NSString stringWithFormat:count >= 2 ? @"%02ld" : @"%ld", (long)[c month]]; break;
            case 'd': s.kind = SegDay; s.text = [NSString stringWithFormat:count >= 2 ? @"%02ld" : @"%ld", (long)[c day]]; break;
            case 'h': case 'K': case 'H': case 'k': {
                NSInteger h = [c hour];
                if (ch == 'h') h = h % 12 ? h % 12 : 12;
                else if (ch == 'K') h = h % 12;
                else if (ch == 'k') h = h ? h : 24;
                s.kind = SegHour;
                s.text = [NSString stringWithFormat:count >= 2 ? @"%02ld" : @"%ld", (long)h];
                break;
            }
            case 'm': s.kind = SegMinute; s.text = [NSString stringWithFormat:@"%02ld", (long)[c minute]]; break;
            case 's': s.kind = SegSecond; s.text = [NSString stringWithFormat:@"%02ld", (long)[c second]]; break;
            case 'a': s.kind = SegAMPM; s.text = [c hour] < 12 ? [cal AMSymbol] : [cal PMSymbol]; break;
            case 'z': case 'v': case 'V': case 'Z': case 'O':
                s.kind = SegZone;
                s.text = [[self _zone] abbreviationForDate:_date] ?: [[self _zone] name];
                break;
            default: s.text = [pattern substringWithRange:NSMakeRange(i, count)]; break;
            }
        }
        (void)twelve;
        segs[n++] = s;
        i = j;
    }
    if (_selected >= 0 && _selected < n && [_typed length])
        segs[_selected].text = [[_typed copy] autorelease];
    return n;
}
- (NSInteger)_segmentCount
{
    Segment segs[max_segments];
    return [self _segments:segs];
}
- (SegKind)_kindAt:(NSInteger)i
{
    Segment segs[max_segments];
    NSInteger n = [self _segments:segs];
    return i >= 0 && i < n ? segs[i].kind : SegLiteral;
}
- (BOOL)_dateSegmentAt:(NSInteger)i
{
    SegKind k = [self _kindAt:i];
    return k == SegYear || k == SegMonth || k == SegDay || k == SegEra;
}
- (BOOL)_twelveHour
{
    NSString *p = [self _pattern];
    return [p rangeOfString:@"h"].location != NSNotFound || [p rangeOfString:@"K"].location != NSNotFound;
}
- (NSInteger)_firstEditable
{
    Segment segs[max_segments];
    NSInteger n = [self _segments:segs];
    for (NSInteger i = 0; i < n; i++)
        if (editable_kind(segs[i].kind))
            return i;
    return -1;
}
/* The next or previous part that can be edited, or -1 at the end. */
- (NSInteger)_moveSelection:(NSInteger)dir
{
    Segment segs[max_segments];
    NSInteger n = [self _segments:segs];
    for (NSInteger i = _selected + dir; i >= 0 && i < n; i += dir)
        if (editable_kind(segs[i].kind))
            return i;
    return -1;
}

/* ---- changing the date ---- */

/* A new date (and range), kept between the limits and offered to the
 * delegate; YES if it changed. */
- (BOOL)_proposeDate:(NSDate *)date interval:(NSTimeInterval)interval
{
    if (!date)
        return NO;
    if (_min && [date compare:_min] == NSOrderedAscending)
        date = _min;
    if (_max && [date compare:_max] == NSOrderedDescending)
        date = _max;
    if ([_delegate respondsToSelector:@selector(datePickerCell:validateProposedDateValue:timeInterval:)]) {
        NSDate *d = date;
        NSTimeInterval t = interval;
        [_delegate datePickerCell:self validateProposedDateValue:&d timeInterval:&t];
        if (!d)
            return NO;
        date = d;
        interval = t;
    }
    BOOL changed = ![date isEqualToDate:_date] || interval != _interval;
    [self setDateValue:date];
    _interval = _mode == NSDatePickerModeRange ? interval : 0;
    return changed;
}
- (NSDateComponents *)_components
{
    return [[self _calendar] components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                        NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                               fromDate:_date];
}
- (NSInteger)_daysInYear:(NSInteger)y month:(NSInteger)m
{
    NSCalendar *cal = [self _calendar];
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setYear:y];
    [c setMonth:m];
    [c setDay:1];
    [c setHour:12];
    NSDate *d = [cal dateFromComponents:c];
    return d ? (NSInteger)[cal rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:d].length : 31;
}
- (BOOL)_proposeComponents:(NSDateComponents *)c
{
    NSInteger days = [self _daysInYear:[c year] month:[c month]];
    if ([c day] > days)
        [c setDay:days];
    double frac = [_date timeIntervalSinceReferenceDate] - floor([_date timeIntervalSinceReferenceDate]);
    NSDate *d = [[self _calendar] dateFromComponents:c];
    return [self _proposeDate:[d dateByAddingTimeInterval:frac] interval:_interval];
}
static NSInteger wrap(NSInteger v, NSInteger lo, NSInteger hi)
{
    NSInteger span = hi - lo + 1;
    return ((v - lo) % span + span) % span + lo;
}
- (BOOL)_stepSelected:(NSInteger)dir
{
    [self _commitTyping];
    NSDateComponents *c = [self _components];
    switch ([self _kindAt:_selected]) {
    case SegYear: [c setYear:MAX(1, MIN(9999, [c year] + dir))]; break;
    case SegMonth: [c setMonth:wrap([c month] + dir, 1, 12)]; break;
    case SegDay: [c setDay:wrap([c day] + dir, 1, [self _daysInYear:[c year] month:[c month]])]; break;
    case SegHour: [c setHour:wrap([c hour] + dir, 0, 23)]; break;
    case SegMinute: [c setMinute:wrap([c minute] + dir, 0, 59)]; break;
    case SegSecond: [c setSecond:wrap([c second] + dir, 0, 59)]; break;
    case SegAMPM: [c setHour:([c hour] + 12) % 24]; break;
    default: return NO;
    }
    return [self _proposeComponents:c];
}
- (void)_clearTyping { [_typed setString:@""]; }
/* A year typed short is taken as this century's. */
- (void)_commitTyping
{
    if (![_typed length])
        return;
    if ([self _kindAt:_selected] == SegYear) {
        NSInteger y = [_typed integerValue];
        [_typed setString:@""];
        if (y < 100)
            y += 2000;
        NSDateComponents *c = [self _components];
        [c setYear:MAX(1, y)];
        [self _proposeComponents:c];
        return;
    }
    [_typed setString:@""];
}
- (BOOL)_typeDigit:(NSInteger)d
{
    SegKind k = [self _kindAt:_selected];
    if (!editable_kind(k) || k == SegAMPM)
        return NO;
    NSDateComponents *c = [self _components];
    BOOL twelve = [self _twelveHour];
    NSInteger max = 59, digits = 2;
    switch (k) {
    case SegYear: max = 9999; digits = 4; break;
    case SegMonth: max = 12; break;
    case SegDay: max = [self _daysInYear:[c year] month:[c month]]; break;
    case SegHour: max = twelve ? 12 : 23; break;
    default: break;
    }
    NSString *next = [_typed stringByAppendingFormat:@"%ld", (long)d];
    if ((NSInteger)[next length] > digits || [next integerValue] > max)
        next = [NSString stringWithFormat:@"%ld", (long)d];
    [_typed setString:next];
    NSInteger v = [next integerValue];
    BOOL full = (NSInteger)[next length] >= digits || v * 10 > max;
    if (k == SegYear) {
        if ((NSInteger)[next length] >= digits) {
            [_typed setString:@""];
            [c setYear:MAX(1, v)];
            [self _proposeComponents:c];
        }
        return full;
    }
    BOOL zeroOK = k == SegMinute || k == SegSecond || (k == SegHour && !twelve);
    if (v == 0 && !zeroOK)
        return NO;   /* wait for the next digit */
    switch (k) {
    case SegMonth: [c setMonth:v]; break;
    case SegDay: [c setDay:v]; break;
    case SegHour: [c setHour:twelve ? v % 12 + ([c hour] >= 12 ? 12 : 0) : v]; break;
    case SegMinute: [c setMinute:v]; break;
    case SegSecond: [c setSecond:v]; break;
    default: break;
    }
    [self _proposeComponents:c];
    if (full)
        [_typed setString:@""];
    return full;
}
- (BOOL)_typeAMPM:(BOOL)pm
{
    if ([self _kindAt:_selected] != SegAMPM)
        return NO;
    NSDateComponents *c = [self _components];
    if (([c hour] >= 12) == pm)
        return NO;
    [c setHour:([c hour] + 12) % 24];
    return [self _proposeComponents:c];
}

/* ---- the calendar ---- */

/* Moves the date by days or months (keeping the day within the month). */
- (BOOL)_moveDays:(NSInteger)days months:(NSInteger)months
{
    NSDateComponents *c = [self _components];
    if (months) {
        NSInteger m = [c month] - 1 + months;
        [c setYear:[c year] + (NSInteger)floor(m / 12.0)];
        [c setMonth:wrap(m, 0, 11) + 1];
        return [self _proposeComponents:c];
    }
    NSDate *d = [[self _calendar] dateByAddingUnit:NSCalendarUnitDay value:days toDate:_date options:0];
    return [self _proposeDate:d interval:_interval];
}
- (NSRect)_calendarRectInFrame:(NSRect)frame
{
    return NSMakeRect(NSMinX(frame), NSMinY(frame), cal_cell_w * 7 + cal_margin * 2,
                      cal_header + cal_weekdays + cal_cell_h * 6 + cal_margin * 2);
}
/* A rectangle given from the top of frame, in the view's coordinates. */
static NSRect from_top(NSRect frame, CGFloat x, CGFloat y, CGFloat w, CGFloat h, BOOL flipped)
{
    return NSMakeRect(NSMinX(frame) + x, flipped ? NSMinY(frame) + y : NSMaxY(frame) - y - h, w, h);
}
/* The first day shown (a Sunday, or the calendar's first weekday, on or
 * before the 1st), and the month shown. */
- (NSDate *)_gridStart:(NSInteger *)month
{
    NSCalendar *cal = [self _calendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:_date];
    [c setDay:1];
    [c setHour:12];
    NSDate *first = [cal dateFromComponents:c];
    NSInteger weekday = [cal component:NSCalendarUnitWeekday fromDate:first];
    NSInteger back = wrap(weekday - (NSInteger)[cal firstWeekday], 0, 6);
    if (month)
        *month = [c month];
    return [cal dateByAddingUnit:NSCalendarUnitDay value:-back toDate:first options:0];
}
- (NSDate *)_dayAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    NSRect grid = from_top(frame, cal_margin, cal_margin + cal_header + cal_weekdays, cal_cell_w * 7, cal_cell_h * 6, flipped);
    if (!NSPointInRect(p, grid))
        return nil;
    NSInteger col = (NSInteger)((p.x - NSMinX(grid)) / cal_cell_w);
    NSInteger row = (NSInteger)((flipped ? p.y - NSMinY(grid) : NSMaxY(grid) - p.y) / cal_cell_h);
    col = MAX(0, MIN(6, col));
    row = MAX(0, MIN(5, row));
    NSDate *start = [self _gridStart:NULL];
    return [[self _calendar] dateByAddingUnit:NSCalendarUnitDay value:row * 7 + col toDate:start options:0];
}
/* -1: the previous month's arrow, 1: the next month's, 2: today, 0: none */
- (NSInteger)_calendarControlAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    CGFloat w = cal_cell_w * 7 + cal_margin * 2;
    if (NSPointInRect(p, from_top(frame, w - cal_margin - 44, cal_margin, 16, cal_header, flipped)))
        return -1;
    if (NSPointInRect(p, from_top(frame, w - cal_margin - 28, cal_margin, 12, cal_header, flipped)))
        return 2;
    if (NSPointInRect(p, from_top(frame, w - cal_margin - 16, cal_margin, 16, cal_header, flipped)))
        return 1;
    return 0;
}

/* ---- size and drawing ---- */

- (NSRect)_stepperRectInFrame:(NSRect)frame
{
    if (_style != NSDatePickerStyleTextFieldAndStepper)
        return NSZeroRect;
    return NSMakeRect(NSMaxX(frame) - stepper_width, NSMinY(frame), stepper_width, frame.size.height);
}
- (NSRect)_textBoxInFrame:(NSRect)frame
{
    NSRect b = frame;
    if (_style == NSDatePickerStyleTextFieldAndStepper)
        b.size.width -= stepper_width + 2;
    b.size.height = fmin(b.size.height, 22);
    b.origin.y = floor(NSMidY(frame) - b.size.height / 2);
    return b;
}
- (NSInteger)_layout:(Segment *)segs inFrame:(NSRect)frame
{
    NSInteger n = [self _segments:segs];
    NSRect box = [self _textBoxInFrame:frame];
    CGFloat x = NSMinX(box) + 4;
    NSFont *font = [self font] ?: ADefaultFont();
    for (NSInteger i = 0; i < n; i++) {
        CGFloat w = ceil(ALineSize(AAttributed(segs[i].text, font, nil), NULL, NULL).width);
        if (editable_kind(segs[i].kind))
            w += 2;
        segs[i].rect = NSMakeRect(x, NSMinY(box) + 3, w, box.size.height - 6);
        x += w;
    }
    return n;
}
- (NSInteger)_segmentAt:(NSPoint)p frame:(NSRect)frame view:(NSView *)view
{
    Segment segs[max_segments];
    NSInteger n = [self _layout:segs inFrame:frame], best = -1;
    CGFloat bestDist = 1e9;
    for (NSInteger i = 0; i < n; i++) {
        if (!editable_kind(segs[i].kind))
            continue;
        CGFloat dist = p.x < NSMinX(segs[i].rect) ? NSMinX(segs[i].rect) - p.x : p.x > NSMaxX(segs[i].rect) ? p.x - NSMaxX(segs[i].rect) : 0;
        if (dist < bestDist) {
            bestDist = dist;
            best = i;
        }
    }
    return best;
}

- (NSSize)cellSize
{
    if ([self _isGraphical]) {
        NSRect cal = [self _calendarRectInFrame:NSZeroRect];
        NSSize s = [self _hasDate] ? cal.size : NSMakeSize(0, clock_size + cal_margin * 2);
        if ([self _hasTime])
            s.width += clock_size + cal_margin * ([self _hasDate] ? 1 : 2);
        return s;
    }
    Segment segs[max_segments];
    NSInteger n = [self _segments:segs];
    CGFloat w = 8;
    NSFont *font = [self font] ?: ADefaultFont();
    for (NSInteger i = 0; i < n; i++)
        w += ceil(ALineSize(AAttributed(segs[i].text, font, nil), NULL, NULL).width) + (editable_kind(segs[i].kind) ? 2 : 0);
    /* room for the widest values */
    w += 8;
    if (_style == NSDatePickerStyleTextFieldAndStepper)
        return NSMakeSize(ceil(w) + stepper_width + 2, 27);
    return NSMakeSize(ceil(w), 22);
}

static void draw_text(NSString *s, NSRect r, NSFont *font, NSColor *color, BOOL flipped, BOOL center)
{
    NSAttributedString *a = AAttributed(s, font, color);
    CGFloat asc, desc;
    NSSize size = ALineSize(a, &asc, &desc);
    CGFloat x = center ? NSMidX(r) - size.width / 2 : NSMinX(r) + 1;
    CGFloat base = flipped ? NSMidY(r) + (asc - desc) / 2 : NSMidY(r) - (asc - desc) / 2;
    ADrawLine(a, round(x), round(base));
}

- (void)_drawTextStyleInFrame:(NSRect)frame inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    BOOL enabled = [self isEnabled];
    NSRect box = [self _textBoxInFrame:frame];
    if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(box);
    }
    [[NSColor colorWithWhite:0 alpha:0.25] setFill];
    NSFrameRect(box);
    Segment segs[max_segments];
    NSInteger n = [self _layout:segs inFrame:frame];
    NSFont *font = [self font] ?: ADefaultFont();
    NSColor *text = enabled ? [self textColor] : [NSColor disabledControlTextColor];
    for (NSInteger i = 0; i < n; i++) {
        BOOL sel = i == _selected && _focused && enabled;
        if (sel)
            AFillRoundedRect(segs[i].rect, 3, [NSColor controlAccentColor], nil);
        draw_text(segs[i].text, segs[i].rect, font, sel ? [NSColor whiteColor] : text, flipped, editable_kind(segs[i].kind));
    }
    if (_style == NSDatePickerStyleTextFieldAndStepper) {
        NSStepperCell *stepper = [[[NSStepperCell alloc] initTextCell:@""] autorelease];
        [stepper setEnabled:enabled];
        [stepper drawWithFrame:[self _stepperRectInFrame:frame] inView:view];
    }
}

- (void)_drawCalendarInFrame:(NSRect)frame inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    BOOL enabled = [self isEnabled];
    NSCalendar *cal = [self _calendar];
    NSFont *font = [self font] ?: ADefaultFont();
    NSFont *small = [NSFont systemFontOfSize:11];
    NSFont *bold = [NSFont boldSystemFontOfSize:[font pointSize]];
    NSColor *text = enabled ? [self textColor] : [NSColor disabledControlTextColor];
    CGFloat w = cal_cell_w * 7 + cal_margin * 2;
    /* the month and year, and the arrows and today's dot */
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setLocale:[self _locale]];
    [f setCalendar:cal];
    [f setTimeZone:[self _zone]];
    [f setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"yMMMM" options:0 locale:[self _locale]] ?: @"MMMM y"];
    draw_text([f stringFromDate:_date], from_top(frame, cal_margin + 2, cal_margin, w, cal_header, flipped), bold, text, flipped, NO);
    NSColor *arrows = enabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor];
    for (int dir = -1; dir <= 1; dir += 2) {
        NSRect r = from_top(frame, w - cal_margin - (dir < 0 ? 44 : 16), cal_margin, 16, cal_header, flipped);
        CGFloat cx = NSMidX(r), cy = NSMidY(r);
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx - dir * 2, cy - 4)];
        [p lineToPoint:NSMakePoint(cx + dir * 2, cy)];
        [p lineToPoint:NSMakePoint(cx - dir * 2, cy + 4)];
        [p setLineWidth:1.5];
        [p setLineCapStyle:NSLineCapStyleRound];
        [p setLineJoinStyle:NSLineJoinStyleRound];
        [arrows setStroke];
        [p stroke];
    }
    NSRect dot = from_top(frame, w - cal_margin - 28, cal_margin, 12, cal_header, flipped);
    [arrows setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(dot) - 2.5, NSMidY(dot) - 2.5, 5, 5)] fill];
    /* the days of the week */
    NSArray *names = [cal veryShortWeekdaySymbols];
    for (NSInteger i = 0; i < 7; i++) {
        NSInteger wd = ((NSInteger)[cal firstWeekday] - 1 + i) % 7;
        NSString *name = wd < (NSInteger)[names count] ? names[wd] : @"";
        draw_text(name, from_top(frame, cal_margin + i * cal_cell_w, cal_margin + cal_header, cal_cell_w, cal_weekdays, flipped),
                  small, [NSColor secondaryLabelColor], flipped, YES);
    }
    /* the days */
    NSInteger month;
    NSDate *day = [self _gridStart:&month];
    NSDate *selStart = [cal startOfDayForDate:_date];
    NSDate *selEnd = [cal startOfDayForDate:[_date dateByAddingTimeInterval:[self timeInterval]]];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    for (NSInteger i = 0; i < 42; i++) {
        NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day];
        NSDate *start = [cal startOfDayForDate:day];
        NSRect r = from_top(frame, cal_margin + (i % 7) * cal_cell_w, cal_margin + cal_header + cal_weekdays + (i / 7) * cal_cell_h,
                            cal_cell_w, cal_cell_h, flipped);
        BOOL selected = [start compare:selStart] != NSOrderedAscending && [start compare:selEnd] != NSOrderedDescending;
        BOOL inMonth = [c month] == month;
        BOOL outOfRange = (_min && [[cal startOfDayForDate:_min] compare:start] == NSOrderedDescending) ||
                          (_max && [[cal startOfDayForDate:_max] compare:start] == NSOrderedAscending);
        NSColor *color = !enabled || outOfRange ? [NSColor disabledControlTextColor]
                         : inMonth             ? text
                                               : [NSColor tertiaryLabelColor];
        if (selected) {
            AFillRoundedRect(NSInsetRect(r, 1, 0.5), 4, _focused ? [NSColor controlAccentColor] : [NSColor colorWithWhite:0 alpha:0.15], nil);
            if (_focused)
                color = [NSColor whiteColor];
        } else if ([start isEqualToDate:today]) {
            color = enabled ? [NSColor controlAccentColor] : color;
        }
        draw_text([NSString stringWithFormat:@"%ld", (long)[c day]], r, small, color, flipped, YES);
        day = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
    }
}

- (void)_drawClockInRect:(NSRect)r inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    NSRect face = NSInsetRect(r, 2, 2);
    CGFloat cx = NSMidX(face), cy = NSMidY(face), radius = face.size.width / 2;
    AFillRoundedRect(face, radius, [NSColor whiteColor], [NSColor colorWithWhite:0 alpha:0.22]);
    [[NSColor colorWithWhite:0 alpha:0.5] setStroke];
    for (int i = 0; i < 12; i++) {
        double a = i * M_PI / 6;
        CGFloat in = radius - (i % 3 ? 5 : 8), out = radius - 2;
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx + in * sin(a), cy + in * cos(a))];
        [p lineToPoint:NSMakePoint(cx + out * sin(a), cy + out * cos(a))];
        [p setLineWidth:i % 3 ? 1 : 1.5];
        [p stroke];
    }
    NSDateComponents *c = [[self _calendar] components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:_date];
    double sec = [c second], min = [c minute] + sec / 60, hour = [c hour] % 12 + min / 60;
    double fy = flipped ? -1 : 1;   /* twelve o'clock is up */
    struct { double angle, length, width; NSColor *color; } hands[3] = {
        {hour * M_PI / 6, radius * 0.5, 3, [NSColor labelColor]},
        {min * M_PI / 30, radius * 0.75, 2, [NSColor labelColor]},
        {sec * M_PI / 30, radius * 0.82, 1, [NSColor controlAccentColor]},
    };
    BOOL seconds = (_elements & NSDatePickerElementFlagHourMinuteSecond) == NSDatePickerElementFlagHourMinuteSecond;
    for (int i = 0; i < (seconds ? 3 : 2); i++) {
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx, cy)];
        [p lineToPoint:NSMakePoint(cx + hands[i].length * sin(hands[i].angle), cy + fy * hands[i].length * cos(hands[i].angle))];
        [p setLineWidth:hands[i].width];
        [p setLineCapStyle:NSLineCapStyleRound];
        [hands[i].color setStroke];
        [p stroke];
    }
    [[NSColor controlAccentColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - 2.5, cy - 2.5, 5, 5)] fill];
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view { [self drawInteriorWithFrame:frame inView:view]; }
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    if (![self _isGraphical]) {
        [self _drawTextStyleInFrame:frame inView:view];
        return;
    }
    if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(frame);
    }
    CGFloat x = 0;
    if ([self _hasDate]) {
        [self _drawCalendarInFrame:frame inView:view];
        x = [self _calendarRectInFrame:frame].size.width;
    }
    if ([self _hasTime]) {
        NSRect r = from_top(frame, x + cal_margin, cal_margin, clock_size, clock_size, [view isFlipped]);
        [self _drawClockInRect:r inView:view];
    }
}
@end

/* ---- the control ----------------------------------------------------------------------- */

@implementation NSDatePicker {
    BOOL _loading, _bezeled, _bordered, _overlay;
    NSInteger _pressed, _tracking;   /* the stepper's half: 1 up, -1 down */
    NSTimer *_repeat;
    BOOL _fast, _dragging;
    NSDate *_anchor;                 /* where a range drag started */
    NSPopover *_popover;
}

+ (Class)cellClass { return [NSDatePickerCell class]; }
- (NSDatePickerCell *)_dateCell { return (NSDatePickerCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    _bezeled = YES;
    if (!_loading && ![[self cell] isKindOfClass:[NSDatePickerCell class]]) {
        NSDatePickerCell *cell = [[NSDatePickerCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSDatePickerCell class]]) {
        NSDatePickerCell *cell = [[NSDatePickerCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    if ([coder containsValueForKey:@"NSPresentsCalendarOverlay"])
        _overlay = [coder decodeBoolForKey:@"NSPresentsCalendarOverlay"];
    return self;
}
- (void)dealloc
{
    [_repeat invalidate];
    [_repeat release];
    [_anchor release];
    [_popover close];
    [_popover release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }

/* ---- the settings, kept in the cell ---- */

#define FORWARD(type, getter, setter)                       \
    -(type)getter { return [[self _dateCell] getter]; }     \
    -(void)setter(type)v                                    \
    {                                                       \
        [[self _dateCell] setter v];                        \
        [self invalidateIntrinsicContentSize];              \
        [self setNeedsDisplay:YES];                         \
    }
FORWARD(NSDatePickerStyle, datePickerStyle, setDatePickerStyle:)
FORWARD(NSDatePickerMode, datePickerMode, setDatePickerMode:)
FORWARD(NSDatePickerElementFlags, datePickerElements, setDatePickerElements:)
FORWARD(NSDate *, minDate, setMinDate:)
FORWARD(NSDate *, maxDate, setMaxDate:)
FORWARD(NSTimeInterval, timeInterval, setTimeInterval:)
FORWARD(NSCalendar *, calendar, setCalendar:)
FORWARD(NSLocale *, locale, setLocale:)
FORWARD(NSTimeZone *, timeZone, setTimeZone:)
FORWARD(BOOL, drawsBackground, setDrawsBackground:)
FORWARD(NSColor *, backgroundColor, setBackgroundColor:)
FORWARD(NSColor *, textColor, setTextColor:)
- (id)delegate { return [[self _dateCell] delegate]; }
- (void)setDelegate:(id)d { [[self _dateCell] setDelegate:d]; }
- (NSDate *)dateValue { return [[self _dateCell] dateValue]; }
- (void)setDateValue:(NSDate *)d
{
    [[self _dateCell] setDateValue:d];
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return [self dateValue]; }
- (void)setObjectValue:(id)v
{
    if ([v isKindOfClass:[NSDate class]])
        [self setDateValue:v];
}
- (NSString *)stringValue { return [[self _dateCell] stringValue]; }
- (BOOL)isBezeled { return _bezeled; }
- (void)setBezeled:(BOOL)f { _bezeled = f; [self setNeedsDisplay:YES]; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f { _bordered = f; [self setNeedsDisplay:YES]; }
- (BOOL)presentsCalendarOverlay { return _overlay; }
- (void)setPresentsCalendarOverlay:(BOOL)f { _overlay = f; }
- (NSInteger)_pressedHalf { return _pressed; }

- (NSSize)intrinsicContentSize { return [[self _dateCell] cellSize]; }

/* A change made here: shown, pushed to bindings and sent. */
- (void)_changed
{
    [self setNeedsDisplay:YES];
    ABindingsPush(self, NO);
    [self sendAction:[self action] to:[self target]];
}

/* ---- the keyboard ---- */

- (BOOL)acceptsFirstResponder { return [self isEnabled]; }
- (BOOL)becomeFirstResponder
{
    NSDatePickerCell *c = [self _dateCell];
    [c _setFocused:YES];
    if (![c _isGraphical] && [c _selected] < 0)
        [c _setSelected:[c _firstEditable]];
    [self setNeedsDisplay:YES];
    return YES;
}
- (BOOL)resignFirstResponder
{
    NSDatePickerCell *c = [self _dateCell];
    NSDate *before = [[[c dateValue] retain] autorelease];
    [c _commitTyping];
    [c _setSelected:-1];
    [c _setFocused:NO];
    if (![before isEqualToDate:[c dateValue]])
        [self _changed];
    [self setNeedsDisplay:YES];
    return YES;
}
- (void)keyDown:(NSEvent *)e
{
    NSDatePickerCell *c = [self _dateCell];
    NSString *s = [e characters];
    if (![c _isGraphical] && [s length] == 1 && !([e modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        unichar ch = [s characterAtIndex:0];
        if (ch >= '0' && ch <= '9') {
            NSDate *before = [[[c dateValue] retain] autorelease];
            BOOL advance = [c _typeDigit:ch - '0'];
            if (![before isEqualToDate:[c dateValue]])
                [self _changed];
            if (advance) {
                NSInteger next = [c _moveSelection:1];
                if (next >= 0)
                    [c _setSelected:next];
            }
            [self setNeedsDisplay:YES];
            return;
        }
        if (ch == 'a' || ch == 'A' || ch == 'p' || ch == 'P') {
            if ([c _typeAMPM:ch == 'p' || ch == 'P'])
                [self _changed];
            return;
        }
        if (ch == '/' || ch == ':' || ch == '.' || ch == '-' || ch == ',') {
            [self moveRight:nil];
            return;
        }
    }
    [self interpretKeyEvents:@[ e ]];
}
- (void)_step:(NSInteger)dir
{
    NSDatePickerCell *c = [self _dateCell];
    if ([c _isGraphical]) {
        if ([c _moveDays:dir * -7 months:0])
            [self _changed];
        return;
    }
    if ([c _selected] < 0)
        [c _setSelected:[c _firstEditable]];
    if ([c _stepSelected:dir])
        [self _changed];
    [self setNeedsDisplay:YES];
}
- (void)moveUp:(id)sender { [self _step:1]; }
- (void)moveDown:(id)sender { [self _step:-1]; }
- (void)_moveSideways:(NSInteger)dir
{
    NSDatePickerCell *c = [self _dateCell];
    if ([c _isGraphical]) {
        if ([c _moveDays:dir months:0])
            [self _changed];
        return;
    }
    NSInteger next = [c _moveSelection:dir];
    if (next >= 0)
        [c _setSelected:next];
    [self setNeedsDisplay:YES];
}
- (void)moveLeft:(id)sender { [self _moveSideways:-1]; }
- (void)moveRight:(id)sender { [self _moveSideways:1]; }
- (void)pageUp:(id)sender
{
    if ([[self _dateCell] _moveDays:0 months:-1])
        [self _changed];
}
- (void)pageDown:(id)sender
{
    if ([[self _dateCell] _moveDays:0 months:1])
        [self _changed];
}
- (void)scrollPageUp:(id)sender { [self pageUp:sender]; }
- (void)scrollPageDown:(id)sender { [self pageDown:sender]; }
- (void)insertTab:(id)sender
{
    NSDatePickerCell *c = [self _dateCell];
    NSInteger next = [c _isGraphical] ? -1 : [c _moveSelection:1];
    if (next >= 0) {
        [c _setSelected:next];
        [self setNeedsDisplay:YES];
    } else {
        [[self window] selectNextKeyView:self];
    }
}
- (void)insertBacktab:(id)sender
{
    NSDatePickerCell *c = [self _dateCell];
    NSInteger prev = [c _isGraphical] ? -1 : [c _moveSelection:-1];
    if (prev >= 0) {
        [c _setSelected:prev];
        [self setNeedsDisplay:YES];
    } else {
        [[self window] selectPreviousKeyView:self];
    }
}
- (void)deleteBackward:(id)sender
{
    [[self _dateCell] _clearTyping];
    [self setNeedsDisplay:YES];
}
- (void)insertNewline:(id)sender
{
    NSDatePickerCell *c = [self _dateCell];
    NSDate *before = [[[c dateValue] retain] autorelease];
    [c _commitTyping];
    if (![before isEqualToDate:[c dateValue]])
        [self _changed];
    else
        [self sendAction:[self action] to:[self target]];
}
- (void)cancelOperation:(id)sender
{
    [[self _dateCell] _clearTyping];
    [self setNeedsDisplay:YES];
}

/* ---- the mouse ---- */

- (void)_stopRepeat
{
    [_repeat invalidate];
    [_repeat release];
    _repeat = nil;
}
- (void)_repeatStep:(NSTimer *)t
{
    if (_pressed == _tracking && _tracking)
        [self _step:_tracking];
    if (!_fast) {
        _fast = YES;
        [self _stopRepeat];
        _repeat = [[NSTimer scheduledTimerWithTimeInterval:0.075 target:self selector:@selector(_repeatStep:)
                                                  userInfo:nil repeats:YES] retain];
    }
}
- (NSInteger)_stepperHalfAt:(NSPoint)p
{
    NSRect r = [[self _dateCell] _stepperRectInFrame:[self bounds]];
    if (!NSPointInRect(p, r))
        return 0;
    return p.y < NSMidY(r) ? 1 : -1;   /* flipped: the top half is up */
}
- (void)_showOverlay
{
    if (!_popover) {
        NSDatePicker *cal = [[[NSDatePicker alloc] initWithFrame:NSZeroRect] autorelease];
        [cal setDatePickerStyle:NSDatePickerStyleClockAndCalendar];
        [cal setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
        [cal setTarget:self];
        [cal setAction:@selector(_overlayChose:)];
        [cal setFrameSize:[cal intrinsicContentSize]];
        NSViewController *vc = [[[NSViewController alloc] init] autorelease];
        [vc setView:cal];
        _popover = [[NSPopover alloc] init];
        [_popover setContentViewController:vc];
        [_popover setBehavior:NSPopoverBehaviorTransient];
    }
    NSDatePicker *cal = (NSDatePicker *)[[_popover contentViewController] view];
    [cal setCalendar:[self calendar]];
    [cal setTimeZone:[self timeZone]];
    [cal setLocale:[self locale]];
    [cal setMinDate:[self minDate]];
    [cal setMaxDate:[self maxDate]];
    [cal setDateValue:[self dateValue]];
    [_popover showRelativeToRect:[self bounds] ofView:self preferredEdge:NSRectEdgeMaxY];
}
- (void)_overlayChose:(NSDatePicker *)cal
{
    NSDatePickerCell *c = [self _dateCell];
    NSCalendar *calendar = [c _calendar];
    NSDateComponents *day = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[cal dateValue]];
    NSDateComponents *time = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:[self dateValue]];
    [day setHour:[time hour]];
    [day setMinute:[time minute]];
    [day setSecond:[time second]];
    if ([c _proposeDate:[calendar dateFromComponents:day] interval:[c timeInterval]])
        [self _changed];
}

- (void)mouseDown:(NSEvent *)e
{
    if (![self isEnabled])
        return;
    NSDatePickerCell *c = [self _dateCell];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSRect b = [self bounds];
    if ([[self window] firstResponder] != self)
        [[self window] makeFirstResponder:self];
    if ([c _isGraphical]) {
        if (![c _hasDate])
            return;
        NSInteger control = [c _calendarControlAt:p frame:b view:self];
        if (control) {
            BOOL changed = control == 2 ? [c _proposeDate:[NSDate date] interval:0] : [c _moveDays:0 months:control];
            if (changed)
                [self _changed];
            return;
        }
        NSDate *day = [c _dayAt:p frame:b view:self];
        if (!day)
            return;
        id wasAnchor = _anchor;
        _anchor = [day retain];
        [wasAnchor release];
        _dragging = YES;
        [self _chooseDaysFrom:day to:day];
        return;
    }
    NSInteger half = [self _stepperHalfAt:p];
    if (half) {
        _pressed = _tracking = half;
        _fast = NO;
        [self _step:half];
        [self _stopRepeat];
        _repeat = [[NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(_repeatStep:)
                                                  userInfo:nil repeats:NO] retain];
        [self setNeedsDisplay:YES];
        return;
    }
    NSInteger seg = [c _segmentAt:p frame:b view:self];
    if (seg >= 0)
        [c _setSelected:seg];
    [self setNeedsDisplay:YES];
    if (_overlay && seg >= 0 && [c _dateSegmentAt:seg])
        [self _showOverlay];
}
/* Chooses a day, keeping the time of day, or a range of days. */
- (void)_chooseDaysFrom:(NSDate *)a to:(NSDate *)b
{
    NSDatePickerCell *c = [self _dateCell];
    NSCalendar *cal = [c _calendar];
    if ([a compare:b] == NSOrderedDescending) {
        NSDate *t = a;
        a = b;
        b = t;
    }
    NSDateComponents *day = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:a];
    NSDateComponents *time = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:[c dateValue]];
    [day setHour:[time hour]];
    [day setMinute:[time minute]];
    [day setSecond:[time second]];
    NSTimeInterval interval = [c datePickerMode] == NSDatePickerModeRange
                                  ? [[cal startOfDayForDate:b] timeIntervalSinceDate:[cal startOfDayForDate:a]]
                                  : 0;
    if ([c _proposeDate:[cal dateFromComponents:day] interval:interval])
        [self _changed];
}
- (void)mouseDragged:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    if (_dragging) {
        NSDate *day = [[self _dateCell] _dayAt:p frame:[self bounds] view:self];
        if (day && [[self _dateCell] datePickerMode] == NSDatePickerModeRange)
            [self _chooseDaysFrom:_anchor to:day];
        else if (day)
            [self _chooseDaysFrom:day to:day];
        return;
    }
    if (_tracking) {
        NSInteger over = [self _stepperHalfAt:p];
        if (over != _pressed) {
            _pressed = over == _tracking ? _tracking : 0;
            [self setNeedsDisplay:YES];
        }
    }
}
- (void)mouseUp:(NSEvent *)e
{
    _dragging = NO;
    [self _stopRepeat];
    if (_tracking) {
        _pressed = _tracking = 0;
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirty
{
    NSDatePickerCell *c = [self _dateCell];
    BOOL focused = [[self window] firstResponder] == self && [[self window] isKeyWindow];
    [c _setFocused:focused];
    [c drawWithFrame:[self bounds] inView:self];
    if (focused && [c _isGraphical]) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect([c _calendarRectInFrame:[self bounds]], 1, 1)];
        [ring setLineWidth:2];
        [[NSColor keyboardFocusIndicatorColor] setStroke];
        [ring stroke];
    } else if (focused) {
        NSRect box = [self bounds];
        if ([c datePickerStyle] == NSDatePickerStyleTextFieldAndStepper)
            box.size.width -= stepper_width + 2;
        box.size.height = fmin(box.size.height, 22);
        box.origin.y = floor(NSMidY([self bounds]) - box.size.height / 2);
        NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect(box, 1, 1)];
        [ring setLineWidth:2];
        [[NSColor keyboardFocusIndicatorColor] setStroke];
        [ring stroke];
    }
}
@end
