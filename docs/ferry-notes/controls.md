# Ferry notes: steppers, date pickers, combo boxes, colour wells, level indicators, popovers, path controls, sounds and token fields

These are the notes for this change, kept apart from `docs/ferry-gui.md`,
`docs/ferry-compat.md` and `ferry/README.md` because other changes are
editing those files at the same time. Each section below is the text meant
for one of them, to be merged in once those changes are in.

The classes are `NSStepper`, `NSLevelIndicator`, `NSColorWell` (with a
basic `NSColorPanel`), `NSDatePicker`, `NSComboBox`, `NSPopover`,
`NSPathControl`, `NSSound` and `NSTokenField`, each with its cell where a
Mac has one (`NSStepperCell`, `NSLevelIndicatorCell`, `NSDatePickerCell`,
`NSComboBoxCell`, `NSPathCell` with `NSPathComponentCell` and
`NSPathControlItem`, `NSTokenFieldCell`). Each is in its own file in
`ferry/appkit/`. The test is `ferry/tests/appkit/more_controls.m`, with the
nib `MoreControls.nib` made by `make_nibs.py`.

## A row for the test table in docs/ferry-gui.md

| Test | Proves |
| --- | --- |
| `appkit_more_controls` | Steppers by click, keys and holding the mouse down (autorepeat, wrapping or stopping at the ends, the value kept within the limits); level indicators in each style (tick marks and their rectangles, a click or drag setting the level when editable, continuous actions, the arrow keys, rating stars); colour wells taking turns with the shared colour panel (one active well, `changeColor:` sent to the active well and down the responder chain, a second click letting go, closing the panel letting go); date pickers in text-and-stepper style (each part stepped by the arrows without carrying into the next, typed digits moving on to the next part, a year typed short, AM and PM, the stepper, the minimum and maximum, the delegate's validation) and graphical style (days clicked, months turned, a range dragged, the clock beside the calendar); combo boxes with their own items and with a data source (the list opened by the button or the keys, chosen by Return or a click, closed by Escape or a click outside, the four notifications in order, completion keeping what was typed, the arrows stepping through the items with the list closed); popovers in each behaviour (shown beside a rectangle on any edge, moved to the other side when there is no room, kept in the window, closed by Escape, a click outside, `performClose:` or the delegate's refusal, the four notifications) and view controllers presented as popovers; path controls (components from a file URL and a web address, clicks and double clicks, own items, a placeholder, long paths cut in the middle, the pop-up style's menu); `NSSound` played through a stand-in player (named sounds, a sound from data, the volume, pause and resume, stop, looping, the delegate told whether it finished); token fields (tokens made at commas or at a character set, Return and end of editing, Backspace selecting then removing a token, the delegate's represented objects, display strings and refusals); and all of them loaded from a nib with their targets and actions |

## Not done (for docs/ferry-gui.md)

- `NSPopover`: detaching into a window (`detachableWindowForPopover:`),
  animation (`animates` is kept and ignored), and the appearance options;
  the bubble has a soft edge in place of a shadow, since Ferry draws no
  shadows.
- `NSPathControl`: dragging files on and off, the "Choose…" item and its
  open panel (`NSPathControlDelegate`'s open-panel methods are never
  called), and editing the path.
- `NSTokenField`: the completion list (`completionsForSubstring:` is never
  asked), tokens wrapping onto more lines, editing a token again,
  copying and pasting tokens as tokens, and tokens' menus.
- `NSDatePicker`: the clock face is drawn but can't be set by dragging its
  hands; time zones read from nibs (Ferry can't decode `NSTimeZone` yet, so
  a nib's time zone is left out and the picker uses the default one).
- `NSComboBox`: the list is drawn inside the window, so a long list can't
  reach past it (the same limit as pop-up buttons' menus).
- `NSColorPanel`: a basic panel. On a display it opens GTK's colour
  chooser; it has no modes, swatches, opacity slider or eyedropper, and
  `setColor:` on the panel answers no well.
- `NSSound`: seeking (`currentTime` is read only), changing the volume of a
  sound already playing, `playbackDeviceIdentifier`, and formats other than
  what the player takes (the duration is read only from WAV files).
- `NSProgressIndicator` wasn't changed here; `NSProgress` isn't there.

## Not compared with a Mac (for docs/ferry-gui.md)

These were written from Apple's published documentation and general
knowledge of how the controls behave, and couldn't be checked against a
real Mac:

- `NSStepper`: the defaults (0 to 59 by 1, autorepeat and wrapping on),
  and that wrapping goes from the maximum to the minimum, not past it.
- `NSLevelIndicator`: the default maximum of 2, the colours at the warning
  and critical values, and how a click between two stars rounds.
- `NSColorWell` and `NSColorPanel`: that a second click on an active well
  lets go of the panel, that closing the panel lets go of every well, and
  that the panel's `setColor:` reaches no well.
- `NSDatePicker`: that stepping a part wraps without carrying into the next
  (the 31st up goes to the 1st of the same month), that typing moves on to
  the next part once a part is full, that a two-digit year is taken as
  20xx, and that setting a limit brings the date within it at once.
- `NSComboBox`: that the arrow keys step through the items while the list
  is closed, that choosing sends the action, that completion keeps the
  case of what was typed, and the order of the notifications.
- `NSPopover`: that a click outside a transient popover goes on to what
  was clicked as well as closing it, and where the bubble goes when there
  is no room on either side.
- `NSPathControl`: "Computer" as the root's name, the pop-up menu's order
  (the last component first), and which components are cut first when the
  path is long.
- `NSSound`: that `stop` tells the delegate the sound didn't finish, and
  that a named sound is kept and handed out again by `soundNamed:`.
- `NSTokenField`: that `stringValue` joins the tokens with ", ".
- The nib keys these classes read (`NSIncrement`, `NSAutorepeat`,
  `NSValueWraps`, `NSIndicatorStyle`, `NSDatePickerElements`,
  `NSPopUpListData`, `NSUsesDataSource`, `NSPathStyle`, `NSTokenStyle`,
  `NSBehavior`, `NSContentViewController` and the rest) are the names
  published descriptions of the format give; a nib that names something
  differently loads with the default.
- How each control looks next to the real one: they are drawn by Ferry's
  own code in freemac's look, not compared side by side.

## A section for docs/ferry-compat.md

### Steppers, date pickers, combo boxes, colour wells, popovers, path controls, sounds and token fields

`NSStepper`, `NSLevelIndicator`, `NSColorWell`, `NSColorPanel`,
`NSDatePicker`, `NSComboBox`, `NSPopover`, `NSPathControl`, `NSSound` and
`NSTokenField` are in Ferry now, with their cells, all read from nibs and
drawn by Ferry's own code in freemac's look. Steppers step by click, the
arrow keys and holding the mouse down. Level indicators draw the
continuous, discrete, relevancy and rating styles with tick marks, and can
be set by the mouse and keys when editable. A colour well opens the shared
colour panel (GTK's colour chooser on a display) and sends `changeColor:`
when a colour is chosen. Date pickers show their parts in the user's
locale's order, are typed into and stepped part by part, keep within their
limits and ask their delegate; the graphical style shows a month calendar
(with ranges) and a clock, and a text picker can open its calendar in a
popover. Combo boxes take their items or a data source, complete what is
typed and open their list inside the window. Popovers open beside a
rectangle in the window, on the side with room, and close as their
behaviour says; view controllers can be presented as popovers. Path
controls show a file's folders (or a web address's parts) with icons, in
the standard, navigation-bar and pop-up styles. `NSSound` plays through
`pw-play`, `paplay` or `aplay`, whichever is there, and `soundNamed:` finds
the Mac's alert sounds' names in freemac's own sounds in
`/usr/share/sounds/freemac`. Token fields turn what is typed into tokens at
commas. Not done yet: detaching popovers, dragging files onto path
controls, the token field's completion list, setting the clock by its
hands, and time zones read from nibs.

## A paragraph for ferry/README.md

From this change, steppers, level indicators, colour wells (with a basic
colour panel), date pickers (text with a stepper, or a calendar and a
clock), combo boxes, popovers, path controls and token fields are there
too, with their cells and read from nibs, and `NSSound` plays sounds
through PipeWire's `pw-play` (or `paplay` or `aplay`), finding the Mac's
alert sounds by name among freemac's own.
