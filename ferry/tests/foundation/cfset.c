/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.220, Ferry 0.44.0): Core Foundation's sets and
 * bags from C. A set of C strings with callbacks of its own (copied in,
 * compared and hashed by their text, freed as they go), one of plain
 * numbers with no callbacks, and the CFType one with strings; adding,
 * replacing, setting and removing; copies; the applier and the values; and
 * a bag that counts its values, of numbers and of strings. Orders that a
 * hash table doesn't keep are sorted before printing. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int frees, retains;
static const void *cstr_retain(CFAllocatorRef a, const void *v)
{
    retains++;
    return strdup(v);
}
static void cstr_release(CFAllocatorRef a, const void *v)
{
    frees++;
    free((void *)v);
}
static Boolean cstr_equal(const void *a, const void *b) { return strcmp(a, b) == 0; }
static CFHashCode cstr_hash(const void *v)
{
    CFHashCode h = 5381;
    for (const unsigned char *p = v; *p; p++)
        h = h * 33 + *p;
    return h;
}
static CFStringRef cstr_describe(const void *v)
{
    return CFStringCreateWithCString(NULL, v, kCFStringEncodingUTF8);
}
static const CFSetCallBacks cstr_callbacks = {0, cstr_retain, cstr_release, cstr_describe, cstr_equal, cstr_hash};

static int by_text(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
static int by_number(const void *a, const void *b)
{
    intptr_t x = *(const intptr_t *)a, y = *(const intptr_t *)b;
    return x < y ? -1 : x > y;
}
static int by_cfstring(const void *a, const void *b)
{
    return (int)CFStringCompare(*(CFStringRef const *)a, *(CFStringRef const *)b, 0);
}

static void show_cstrings(const char *label, CFSetRef set)
{
    CFIndex n = CFSetGetCount(set);
    const char **v = malloc(sizeof(char *) * (size_t)(n + 1));
    CFSetGetValues(set, (const void **)v);
    qsort(v, (size_t)n, sizeof *v, by_text);
    printf("%s (%ld):", label, (long)n);
    for (CFIndex i = 0; i < n; i++)
        printf(" %s", v[i]);
    printf("\n");
    free(v);
}

static void add_up(const void *value, void *ctx) { *(intptr_t *)ctx += (intptr_t)value; }
static void count_calls(const void *value, void *ctx) { (*(int *)ctx)++; }

int main(void)
{
    /* C strings, held by their text */
    char word[16];
    CFMutableSetRef words = CFSetCreateMutable(NULL, 0, &cstr_callbacks);
    strcpy(word, "pear");
    CFSetAddValue(words, word);
    strcpy(word, "apple");
    CFSetAddValue(words, word);
    CFSetAddValue(words, "pear");         /* there already: kept, not copied again */
    show_cstrings("words", words);
    printf("copied in %d, a set of its own %d\n", retains, CFGetTypeID(words) == CFSetGetTypeID());
    printf("has pear %d, has fig %d, count of apple %ld\n", CFSetContainsValue(words, "pear"),
           CFSetContainsValue(words, "fig"), (long)CFSetGetCountOfValue(words, "apple"));
    const void *found = NULL;
    const char *pear = "pear";
    printf("the pear it holds is its own copy %d\n",
           CFSetGetValueIfPresent(words, pear, &found) && found != (const void *)pear && strcmp(found, pear) == 0);
    CFSetReplaceValue(words, "fig");      /* not there: nothing */
    CFSetReplaceValue(words, "pear");     /* there: a new copy, the old one freed */
    CFSetSetValue(words, "fig");          /* not there: added */
    show_cstrings("after replace and set", words);
    printf("copied in %d, freed %d\n", retains, frees);
    CFSetRef copy = CFSetCreateCopy(NULL, words);
    CFSetRemoveValue(words, "apple");
    CFSetRemoveValue(words, "plum");
    show_cstrings("removed apple", words);
    show_cstrings("the copy", copy);
    CFStringRef described = CFCopyDescription(copy);
    printf("the copy describes its words %d\n",
           CFStringFind(described, CFSTR("apple"), 0).location != kCFNotFound &&
               CFStringFind(described, CFSTR("fig"), 0).location != kCFNotFound);
    CFRelease(described);
    CFSetRemoveAllValues(words);
    printf("emptied: %ld\n", (long)CFSetGetCount(words));
    int before = frees;
    CFRelease(copy);
    CFRelease(words);
    printf("freed with the copy %d\n", frees - before);

    /* plain numbers, no callbacks */
    const void *numbers[] = {(const void *)3, (const void *)1, (const void *)4, (const void *)1, (const void *)5};
    CFSetRef ns = CFSetCreate(NULL, numbers, 5, NULL);
    intptr_t sum = 0;
    CFSetApplyFunction(ns, add_up, &sum);
    intptr_t vals[8];
    CFSetGetValues(ns, (const void **)vals);
    qsort(vals, (size_t)CFSetGetCount(ns), sizeof *vals, by_number);
    printf("numbers: %ld, sum %ld, smallest %ld, largest %ld, has 4 %d, has 9 %d\n", (long)CFSetGetCount(ns),
           (long)sum, (long)vals[0], (long)vals[CFSetGetCount(ns) - 1], CFSetContainsValue(ns, (const void *)4),
           CFSetContainsValue(ns, (const void *)9));
    CFMutableSetRef more = CFSetCreateMutableCopy(NULL, 0, ns);
    CFSetAddValue(more, (const void *)9);
    printf("a mutable copy: %ld, the first still %ld\n", (long)CFSetGetCount(more), (long)CFSetGetCount(ns));
    CFRelease(more);
    CFRelease(ns);

    /* the CFType callbacks: an NSSet underneath */
    CFStringRef names[] = {CFSTR("b"), CFSTR("a"), CFSTR("b")};
    CFSetRef strings = CFSetCreate(NULL, (const void **)names, 3, &kCFTypeSetCallBacks);
    CFMutableSetRef ms = CFSetCreateMutableCopy(NULL, 0, strings);
    CFSetAddValue(ms, CFSTR("c"));
    CFSetSetValue(ms, CFSTR("a"));
    CFSetRemoveValue(ms, CFSTR("b"));
    CFStringRef got[4];
    CFSetGetValues(ms, (const void **)got);
    qsort(got, (size_t)CFSetGetCount(ms), sizeof *got, by_cfstring);
    char a[8], c[8];
    CFStringGetCString(got[0], a, sizeof a, kCFStringEncodingUTF8);
    CFStringGetCString(got[1], c, sizeof c, kCFStringEncodingUTF8);
    printf("strings: %ld, then %ld: %s %s, a set %d, equal to a copy %d\n", (long)CFSetGetCount(strings),
           (long)CFSetGetCount(ms), a, c, CFGetTypeID(strings) == CFSetGetTypeID(),
           CFEqual(ms, CFSetCreateCopy(NULL, ms)));
    CFRelease(ms);
    CFRelease(strings);

    /* bags count their values */
    CFMutableBagRef bag = CFBagCreateMutable(NULL, 0, NULL);
    CFBagAddValue(bag, (const void *)7);
    CFBagAddValue(bag, (const void *)7);
    CFBagAddValue(bag, (const void *)2);
    CFBagAddValue(bag, (const void *)7);
    printf("bag: %ld values, 7 three times %ld, 2 once %ld, 5 never %ld, a bag %d\n", (long)CFBagGetCount(bag),
           (long)CFBagGetCountOfValue(bag, (const void *)7), (long)CFBagGetCountOfValue(bag, (const void *)2),
           (long)CFBagGetCountOfValue(bag, (const void *)5), CFGetTypeID(bag) == CFBagGetTypeID());
    sum = 0;
    int calls = 0;
    CFBagApplyFunction(bag, add_up, &sum);
    CFBagApplyFunction(bag, count_calls, &calls);
    printf("applied %d times, sum %ld\n", calls, (long)sum);
    CFBagRef bag_copy = CFBagCreateCopy(NULL, bag);
    CFBagRemoveValue(bag, (const void *)7);
    CFBagReplaceValue(bag, (const void *)2);
    CFBagSetValue(bag, (const void *)5);
    printf("one 7 taken: %ld values, 7 twice %ld, 5 once %ld; the copy %ld values, equal %d, to itself %d\n",
           (long)CFBagGetCount(bag), (long)CFBagGetCountOfValue(bag, (const void *)7),
           (long)CFBagGetCountOfValue(bag, (const void *)5), (long)CFBagGetCount(bag_copy), CFEqual(bag, bag_copy),
           CFEqual(bag_copy, CFBagCreateCopy(NULL, bag_copy)));
    CFBagRemoveAllValues(bag);
    printf("emptied: %ld, has 7 %d\n", (long)CFBagGetCount(bag), CFBagContainsValue(bag, (const void *)7));
    CFRelease(bag);
    CFRelease(bag_copy);

    /* a bag of strings, counted by their text */
    CFMutableBagRef sb = CFBagCreateMutable(NULL, 0, &kCFTypeBagCallBacks);
    CFStringRef dynamic = CFStringCreateWithCString(NULL, "tag", kCFStringEncodingUTF8);
    CFBagAddValue(sb, CFSTR("tag"));
    CFBagAddValue(sb, dynamic);
    CFBagAddValue(sb, CFSTR("other"));
    const void *held = CFBagGetValue(sb, dynamic);
    printf("strings in a bag: %ld, tag twice %ld, holds the first tag %d\n", (long)CFBagGetCount(sb),
           (long)CFBagGetCountOfValue(sb, CFSTR("tag")), held == (const void *)CFSTR("tag"));
    CFRelease(dynamic);
    CFRelease(sb);
    return 0;
}
