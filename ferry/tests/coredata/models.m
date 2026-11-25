/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's models from files (freemac 1.209, Ferry 0.35.0): a model's
 * XML source (a .xcdatamodeld folder with two versions and its
 * .xccurrentversion) read by mergedModelFromBundles:, by
 * initWithContentsOfURL: and by NSPersistentContainer's initWithName:, then
 * used; and a compiled model (.momd or .mom), which isn't read: each way of
 * asking for one answers nil, and run.sh checks that stderr said why, once. */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }

static NSString *const contents_v1 =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    @"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\">\n"
    @"    <entity name=\"Book\" representedClassName=\"Book\">\n"
    @"        <attribute name=\"title\" attributeType=\"String\"/>\n"
    @"    </entity>\n"
    @"</model>\n";

static NSString *const contents_v2 =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    @"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\">\n"
    @"    <entity name=\"Author\" representedClassName=\"NSManagedObject\">\n"
    @"        <attribute name=\"name\" attributeType=\"String\" minValueString=\"1\" maxValueString=\"30\"/>\n"
    @"        <relationship name=\"books\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Cascade\""
    @" destinationEntity=\"Book\" inverseName=\"author\" inverseEntity=\"Book\"/>\n"
    @"    </entity>\n"
    @"    <entity name=\"Book\" representedClassName=\"NSManagedObject\">\n"
    @"        <attribute name=\"title\" attributeType=\"String\"/>\n"
    @"        <attribute name=\"pages\" optional=\"YES\" attributeType=\"Integer 32\" defaultValueString=\"100\""
    @" usesScalarValueType=\"YES\"/>\n"
    @"        <attribute name=\"price\" optional=\"YES\" attributeType=\"Double\" defaultValueString=\"9.5\"/>\n"
    @"        <attribute name=\"read\" optional=\"YES\" attributeType=\"Boolean\" defaultValueString=\"NO\"/>\n"
    @"        <attribute name=\"cover\" optional=\"YES\" attributeType=\"Transformable\""
    @" valueTransformerName=\"NSSecureUnarchiveFromData\"/>\n"
    @"        <relationship name=\"author\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\""
    @" destinationEntity=\"Author\" inverseName=\"books\" inverseEntity=\"Author\"/>\n"
    @"    </entity>\n"
    @"    <entity name=\"Ebook\" parentEntity=\"Book\">\n"
    @"        <attribute name=\"format\" optional=\"YES\" attributeType=\"String\" defaultValueString=\"epub\"/>\n"
    @"    </entity>\n"
    @"    <fetchRequest name=\"Long\" entity=\"Book\" predicateString=\"pages &gt; 300\"/>\n"
    @"</model>\n";

static void write_text(NSString *path, NSString *text)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void describe(const char *what, NSManagedObjectModel *m)
{
    if (!m) {
        printf("%s: nil\n", what);
        return;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSEntityDescription *e in [m.entities sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]]) {
        NSMutableArray *props = [NSMutableArray array];
        for (NSString *k in [e.propertiesByName.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSPropertyDescription *p = e.propertiesByName[k];
            if ([p isKindOfClass:[NSAttributeDescription class]])
                [props addObject:[NSString stringWithFormat:@"%@:%lu%@%@", k, (unsigned long)[(id)p attributeType],
                                                           p.isOptional ? @"?" : @"",
                                                           [(id)p defaultValue] ? [NSString stringWithFormat:@"=%@", [(id)p defaultValue]] : @""]];
            else
                [props addObject:[NSString stringWithFormat:@"%@->%@%@", k, [(id)p destinationEntity].name,
                                                           [(id)p isToMany] ? @"*" : @""]];
        }
        [parts addObject:[NSString stringWithFormat:@"%@%@(%@)", e.name, e.superentity ? [@":" stringByAppendingString:e.superentity.name] : @"",
                                                   [props componentsJoinedByString:@" "]]];
    }
    printf("%s: %s\n", what, [[parts componentsJoinedByString:@" "] UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_models"];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];

        /* a model's source, in a bundle */
        NSString *source = [tmp stringByAppendingPathComponent:@"Source.bundle/Contents/Resources/Library.xcdatamodeld"];
        write_text([source stringByAppendingPathComponent:@"Library.xcdatamodel/contents"], contents_v1);
        write_text([source stringByAppendingPathComponent:@"Library 2.xcdatamodel/contents"], contents_v2);
        [@{ @"_XCCurrentVersionName" : @"Library 2.xcdatamodel" }
            writeToFile:[source stringByAppendingPathComponent:@".xccurrentversion"] atomically:YES];
        NSDictionary *info = @{ @"CFBundleIdentifier" : @"org.freemac.test.models", @"CFBundlePackageType" : @"BNDL" };
        [info writeToFile:[tmp stringByAppendingPathComponent:@"Source.bundle/Contents/Info.plist"] atomically:YES];
        NSBundle *bundle = [NSBundle bundleWithPath:[tmp stringByAppendingPathComponent:@"Source.bundle"]];
        NSManagedObjectModel *m = [NSManagedObjectModel mergedModelFromBundles:@[ bundle ]];
        describe("merged from the bundle", m);
        describe("from the source's URL", [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:source]]);
        describe("one version's folder",
                 [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[source stringByAppendingPathComponent:@"Library.xcdatamodel"]]]);
        NSFetchRequest *tpl = [m fetchRequestTemplateForName:@"Long"];
        printf("template: %s %s\n", str(tpl.entityName ?: tpl.entity.name), str(tpl.predicate.predicateFormat));

        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:m];
        [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
        NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        moc.persistentStoreCoordinator = psc;
        NSManagedObject *author = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:moc];
        [author setValue:@"Ida" forKey:@"name"];
        NSManagedObject *book = [NSEntityDescription insertNewObjectForEntityForName:@"Ebook" inManagedObjectContext:moc];
        [book setValue:@"Tides" forKey:@"title"];
        [book setValue:author forKey:@"author"];
        [book setValue:@[ @"blue", @"waves" ] forKey:@"cover"];
        NSError *error = nil;
        printf("used: saved %d, book pages %s price %s format %s, author's books %lu, cover %s\n", [moc save:&error],
               str([book valueForKey:@"pages"]), str([book valueForKey:@"price"]), str([book valueForKey:@"format"]),
               (unsigned long)[[author valueForKey:@"books"] count], str([[book valueForKey:@"cover"] componentsJoinedByString:@"+"]));
        id v = @"";
        printf("a name shorter than its minimum: valid %d, error %ld\n", [author validateValue:&v forKey:@"name" error:&error],
               (long)error.code);

        /* a container finds the source in the main bundle */
        NSString *main = [[NSBundle mainBundle] resourcePath];
        NSString *inMain = [main stringByAppendingPathComponent:@"CDTestShelf.xcdatamodeld"];
        [[NSFileManager defaultManager] removeItemAtPath:inMain error:NULL];
        write_text([inMain stringByAppendingPathComponent:@"CDTestShelf.xcdatamodel/contents"], contents_v2);
        NSPersistentContainer *c = [NSPersistentContainer persistentContainerWithName:@"CDTestShelf"];
        describe("the container's model", c.managedObjectModel);
        [[NSFileManager defaultManager] removeItemAtPath:inMain error:NULL];

        /* compiled models aren't read */
        NSString *compiled = [tmp stringByAppendingPathComponent:@"Compiled.bundle/Contents/Resources"];
        write_text([compiled stringByAppendingPathComponent:@"Shop.momd/Shop.mom"], @"not ours to read");
        write_text([compiled stringByAppendingPathComponent:@"Shop.momd/VersionInfo.plist"], @"<plist/>");
        [info writeToFile:[tmp stringByAppendingPathComponent:@"Compiled.bundle/Contents/Info.plist"] atomically:YES];
        NSBundle *cb = [NSBundle bundleWithPath:[tmp stringByAppendingPathComponent:@"Compiled.bundle"]];
        describe("merged from a bundle with only a .momd", [NSManagedObjectModel mergedModelFromBundles:@[ cb ]]);
        describe("a .momd's URL", [[NSManagedObjectModel alloc]
                                      initWithContentsOfURL:[cb URLForResource:@"Shop" withExtension:@"momd"]]);
        describe("a .mom's URL", [[NSManagedObjectModel alloc]
                                     initWithContentsOfURL:[NSURL fileURLWithPath:[compiled stringByAppendingPathComponent:@"Shop.momd/Shop.mom"]]]);
        NSString *mom = [main stringByAppendingPathComponent:@"CDTestShop.momd"];
        write_text([mom stringByAppendingPathComponent:@"CDTestShop.mom"], @"not ours to read");
        NSPersistentContainer *shop = [[NSPersistentContainer alloc] initWithName:@"CDTestShop"];
        describe("a container named for a .momd", shop.managedObjectModel);
        [shop loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *d, NSError *e) {
            printf("loading its store: error %ld\n", (long)e.code);
        }];
        [[NSFileManager defaultManager] removeItemAtPath:mom error:NULL];
    }
    return 0;
}
