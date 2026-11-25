/* SPDX-License-Identifier: GPL-3.0-or-later
 * What VLC's Mac interface calls besides (freemac 1.233, Ferry 0.57.0):
 * CoreMedia's times, the media keys' command center and Now Playing, the
 * displays, string comparison in a range, the writing direction of a
 * language, slider cells' parts, a control's selected cell, paragraph
 * alignment, volumes' parameters, I/O Kit with no registry, capture
 * devices and the address book, both empty. */
#import <Cocoa/Cocoa.h>
#import <CoreMedia/CoreMedia.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AddressBook/AddressBook.h>
#import <AVFoundation/AVFoundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/storage/IOMedia.h>
#import <CoreServices/CoreServices.h>

@interface Player : NSObject
@property NSInteger plays;
@end
@implementation Player
- (MPRemoteCommandHandlerStatus)play:(MPRemoteCommandEvent *)event
{
    self.plays++;
    return MPRemoteCommandHandlerStatusSuccess;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        CMTime a = CMTimeMake(3, 2), b = CMTimeMakeWithSeconds(0.5, 600);
        CMTime sum = CMTimeAdd(a, b);
        printf("times: %.2f + %.2f = %.2f, compare %d, invalid %d\n", CMTimeGetSeconds(a), CMTimeGetSeconds(b),
               CMTimeGetSeconds(sum), (int)CMTimeCompare(a, b), (int)CMTIME_IS_VALID(kCMTimeInvalid));

        MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
        Player *player = [Player new];
        [center.playCommand addTarget:player action:@selector(play:)];
        __block int handled = 0;
        [center.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
            handled++;
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        [center.playCommand performSelector:@selector(_ferrySend)];
        [center.pauseCommand performSelector:@selector(_ferrySend)];
        [center.playCommand removeTarget:player];
        [center.playCommand performSelector:@selector(_ferrySend)];
        printf("media keys: play %ld, pause %d\n", (long)player.plays, handled);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = @{MPMediaItemPropertyTitle : @"Big Buck Bunny"};
        printf("now playing: %s\n",
               [[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo objectForKey:MPMediaItemPropertyTitle] UTF8String]);

        CGDirectDisplayID main = CGMainDisplayID();
        uint32_t count = 0;
        CGGetActiveDisplayList(0, NULL, &count);
        CGRect bounds = CGDisplayBounds(main);
        printf("displays: main is one %d, count %s, has size %d\n", main != kCGNullDirectDisplay, count ? "some" : "none",
               bounds.size.width > 0 && bounds.size.height > 0);

        NSString *s = @"VLC media player";
        printf("compare in range: %d %d\n", (int)[s compare:@"MEDIA" options:NSCaseInsensitiveSearch range:NSMakeRange(4, 5)],
               (int)[s compare:@"media" options:0 range:NSMakeRange(0, 3)]);
        printf("replaced: %s\n", [[s stringByReplacingCharactersInRange:NSMakeRange(0, 3) withString:@"Ferry"] UTF8String]);
        printf("directions: en %d, he %d\n", (int)[NSLocale characterDirectionForLanguage:@"en"],
               (int)[NSLocale characterDirectionForLanguage:@"he"]);

        NSSliderCell *cell = [NSSliderCell new];
        cell.minValue = 0;
        cell.maxValue = 100;
        cell.doubleValue = 50;
        NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        slider.cell = cell;
        NSRect knob = [cell knobRectFlipped:NO], bar = [cell barRectFlipped:NO];
        printf("slider: knob %.0f wide, centred %d, bar inside %d\n", knob.size.width,
               fabs(NSMidX(knob) - NSMidX(bar)) < 1.5, NSContainsRect(slider.bounds, bar));
        printf("selected cell is the cell: %d\n", slider.selectedCell == cell);

        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"centred"];
        [text setAlignment:NSTextAlignmentCenter range:NSMakeRange(0, 7)];
        NSParagraphStyle *style = [text attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
        printf("alignment centred: %d\n", style.alignment == NSTextAlignmentCenter);

        GetVolParmsInfoBuffer parms;
        printf("volume parameters: %d, device %p\n", (int)FSGetVolumeParms(1, &parms, sizeof parms), parms.vMDeviceID);
        io_service_t media = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOMediaClass));
        printf("I/O Kit media: %u\n", (unsigned)media);
        printf("capture devices: %lu, default video %s\n", (unsigned long)[[AVCaptureDevice devices] count],
               [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] ? "some" : "none");
        printf("address book people: %lu\n", (unsigned long)[[[ABAddressBook sharedAddressBook] people] count]);
        printf("removable media listed: %d\n", [[NSWorkspace sharedWorkspace] mountedRemovableMedia] != nil);
    }
    return 0;
}
