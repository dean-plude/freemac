# SPDX-License-Identifier: GPL-3.0-or-later
"""The freemac Guide: short topics on how to do everyday things.

Help in the menu bar lists the topics that match what you type, under the
menu items, and Seek finds them too; either opens the topic in Guide. Kept
apart from guide.py, with no GTK, so the menu bar and Seek can read it
without loading the Guide window. Original freemac text.

Each topic is (title, usual words, paragraphs). A paragraph that starts
with "- " is a line of a list.
"""

TOPICS = {
    "keys": ("Use the Command key", "command cmd alt key shortcut copy paste keyboard ctrl control", [
        "Command (⌘) is the key right next to the space bar: Alt on most PC keyboards. "
        "Option (⌥) is the key beside it.",
        "Command with a letter does what Ctrl does on other PCs, in every app:",
        "- ⌘C copies, ⌘V pastes and ⌘X cuts.",
        "- ⌘Z undoes and ⇧⌘Z redoes.",
        "- ⌘S saves, ⌘O opens and ⌘P prints.",
        "- ⌘W closes the window and ⌘Q quits the app.",
        "With a Mac keyboard, choose Dials > Keyboard and make the Windows key Command.",
    ]),
    "apps": ("Open and switch apps", "launch start open app switch tab dock marina launcher", [
        "Click an app in the Dock, or press ⌘Space and type the first letters of its name, then Return.",
        "Press F4 for every app on one screen. Drag an app onto another to make a folder.",
        "To switch apps, hold ⌘ and press Tab until the app you want is chosen, then let go. "
        "⌘` goes to the app's next window.",
        "An app stays open after its last window closes, with a dot under it in the Dock. "
        "⌘Q quits it.",
    ]),
    "windows": ("Arrange windows", "window close tile half fill minimize zoom full screen resize move desktop", [
        "The three round buttons at the top left of a window close it, minimize it into the Dock, "
        "and zoom it.",
        "Drag a window to the left or right edge to fill that half of the screen, "
        "or press Control+⌘ with an arrow key.",
        "- ⌘M minimizes the window.",
        "- Control+⌘F makes it full screen.",
        "- ⌘H hides the app and ⌥⌘H hides the others.",
        "- Control+Up shows every window; click one to bring it forward.",
        "Window > Fill and Window > Center in the menu bar work on the window in front.",
    ]),
    "desktops": ("Use more than one desktop", "desktop space workspace virtual swipe overview", [
        "freemac has four desktops. Control+Left and Control+Right move between them, "
        "as a three-finger swipe does.",
        "Control+Down shows all four. Control+Shift with an arrow key takes the window in front "
        "to the next desktop.",
    ]),
    "seek": ("Search with Seek", "seek search find spotlight calculate sum file", [
        "Press ⌘Space, type, and press Return to open the first result. The arrow keys move "
        "down the list.",
        "Seek finds apps, settings, the menu items of the app in front, files by their names "
        "and by the words inside them.",
        "Type a sum such as 12*7 to see the answer; Return copies it.",
    ]),
    "help": ("Find a menu item", "help menu item command search find", [
        "Click Help at the end of the menu bar and just type. The menu items that match show "
        "under the search field, with the menu they're in and their shortcut.",
        "Press Return to choose the first one; it does exactly what it does in its own menu.",
        "Guide topics that match are listed under them.",
    ]),
    "files": ("Find and organize files", "drawer files folder finder documents downloads trash copy rename", [
        "Drawer shows your files. Click it in the Dock.",
        "- ⌘1, ⌘2 and ⌘3 show icons, a list or columns.",
        "- Space shows a quick preview of the file you chose.",
        "- F2 renames, and Delete moves a file to the Trash.",
        "- ⌘I shows a file's information, and ⌘T opens a tab.",
        "Click the Trash in the Dock to see it and empty it.",
    ]),
    "screenshot": ("Take a screenshot", "screenshot screen picture capture record print lens", [
        "- ⇧⌘3 takes a picture of the whole screen.",
        "- ⇧⌘4 lets you drag around part of it.",
        "- ⇧⌘5 records part of the screen; press it again to stop.",
        "The pictures go on the desktop and are copied, ready to paste. A small preview shows in the "
        "corner for a moment.",
    ]),
    "wifi": ("Join a Wi-Fi network", "wifi wi-fi wireless internet network password connect", [
        "Click the network icon in the menu bar, or choose Dials > Network, and choose the network.",
        "Type its password when asked. freemac remembers it next time.",
    ]),
    "appearance": ("Change the look", "dark light mode wallpaper theme accent background appearance", [
        "Choose Dials > Appearance for light or dark, and Dials > Wallpaper for the picture on the desktop.",
        "Each wallpaper has a day and a night version, and follows light and dark.",
    ]),
    "sound": ("Change the volume", "sound volume mute speaker headphones audio output", [
        "Use the volume keys, or click the sound icon in the menu bar and drag the slider.",
        "Choose Dials > Sound to pick the output, such as headphones.",
    ]),
    "install": ("Install apps", "install app store harbor download update software", [
        "Harbor lists free apps. Click Install beside one; it shows in the Dock and in F4 when it's ready.",
        "Harbor also installs updates for freemac itself.",
        "Apps from the Mac App Store don't run on freemac.",
    ]),
    "lock": ("Lock, restart or shut down", "lock shut down restart reboot log out power off", [
        "Control+⌘Q locks the screen. Type your password to come back.",
        "The freemac menu at the left end of the menu bar has Lock Screen, Restart, Shut Down and Log Out.",
    ]),
    "stuck": ("When an app stops answering", "force quit frozen stuck hang not responding crash", [
        "Press ⌥⌘⎋ (Option, Command and Escape), or choose Force Quit in the freemac menu, "
        "then choose the app and Force Quit.",
        "Anything not saved in that app is lost.",
        "To see which app is slowing the computer down, open Gauge and look at the % CPU column.",
    ]),
    "busy": ("See what's using your computer", "activity monitor gauge slow cpu memory processor busy fan hot process task manager", [
        "Gauge shows each open app with how much of the processor and memory it's using. Press ⌘Space, "
        "type Gauge and press Return.",
        "Click CPU or Memory at the top to switch. Click a column's heading to sort by it.",
        "Under the list, a graph shows the last two minutes.",
        "- View > My Processes or All Processes lists every program, not only apps.",
        "- To quit one, select it and click ✕ at the top left, or press Delete. Quit asks it to close; "
        "Force Quit ends it at once and loses what it hasn't saved.",
    ]),
    "disk-utility": ("Rename, erase or eject a drive", "disk utility hull drive usb stick format erase rename eject space full exfat fat", [
        "Hull shows every drive, how full it is and what kind it is. Press ⌘Space, type Hull and press Return.",
        "Choose a drive or a volume on the left, then use the buttons at the top.",
        "- Rename: type a new name. Double-clicking a volume does the same.",
        "- Erase: deletes everything on it. Choose ExFAT for a drive you'll also use with a Mac or "
        "Windows computer.",
        "- Eject: do this before you unplug a drive, so nothing being saved is lost.",
        "Hull won't change the disk freemac is running from.",
    ]),
    "camera": ("Take a picture of yourself", "camera webcam selfie photo picture pose effects booth countdown", [
        "Pose takes pictures with the computer's camera. Press ⌘Space, type Pose and press Return.",
        "Click the red button (or press Space). Pose counts down 3, 2, 1 so you can get ready, then "
        "takes the picture. Click 3 seconds to take pictures straight away instead.",
        "Click Effects for fun ones: bend your face, make it a comic or an old movie, and more. "
        "The picture is taken with the effect you choose.",
        "Your pictures are saved in the Pose folder in Pictures, and show along the bottom of the window. "
        "Double-click one to open it, or right-click it to move it to the Trash.",
        "If Pose says no camera is connected, plug one in. If another app is using the camera, quit it first.",
    ]),
    "weather": ("See the weather", "weather forecast sky temperature rain snow sun hourly week celsius fahrenheit", [
        "Sky shows the weather. Press ⌘Space, type Sky and press Return.",
        "The first time, Sky shows the weather for the city of your time zone. Click + and type a city "
        "or town to add more places, then click a place on the left to see its weather.",
        "You'll see the temperature now, the next 24 hours, the next 10 days, and how it feels, the wind "
        "and when the sun rises or sets.",
        "To switch between °F and °C, choose View > Fahrenheit or View > Celsius. To remove a place, "
        "right-click it and choose Remove.",
        "Sky needs the internet. If it can't connect, it shows the last weather it got.",
    ]),
    "stickies": ("Leave yourself a sticky note", "sticky note notes stickies memo reminder desktop post-it", [
        "Stickies puts little coloured notes on your desktop. Press ⌘Space, type Stickies and press Return, "
        "or click Stickies in the Dock, and a new note appears. Just start typing.",
        "Drag a note by its top strip to move it, and drag its bottom-right corner to make it bigger. "
        "Click the dots on the strip to change its colour, or + for another note.",
        "Notes stay under your windows. To keep one in front, right-click its strip and choose Float on Top.",
        "Your notes are kept as you type and come back when you log in. To throw one away, click the × on its strip.",
    ]),
    "voice": ("Record your voice", "voice memo record recorder microphone audio echo trim", [
        "Echo records your voice. Press ⌘Space, type Echo and press Return.",
        "Click the big red button to start recording, and Done when you've finished. "
        "Your recording appears at the top of the list.",
        "Press Space to play it. Click the waveform to jump to a part, or skip back and forward 15 seconds.",
        "Click the recording's name to rename it. Click Trim and drag the yellow handles to keep only the "
        "part you want.",
        "Recordings are kept in the Echo folder in Music. If Echo can't hear you, plug in a microphone "
        "or choose one in Dials > Sound.",
    ]),
    "drawing": ("Draw a picture", "draw drawing paint sketch doodle pen easel art sticker", [
        "Easel is for drawing. Press ⌘Space, type Easel and press Return.",
        "Pick a pen, the highlighter or a shape at the top, then a colour and a size, and draw. "
        "Hold Shift while you draw a shape for a perfect square, circle or straight line.",
        "Click the smiley for stickers, or the A to type words. The eraser rubs out whatever it goes over.",
        "Click the arrow to pick up something you drew and move it. Press Delete to throw it away. "
        "⌘Z undoes your last change.",
        "Your drawings are kept as you go and listed on the left. Click Export to save one as a picture "
        "you can share.",
    ]),
    "chess": ("Play chess", "chess game play board checkmate rook computer friend", [
        "Rook plays chess. Press ⌘Space, type Rook and press Return.",
        "Click a piece to see where it can go, then click where you want it, or drag it there.",
        "Click New Game to play the computer on Easy, Medium or Hard, or a friend on the same screen.",
        "Stuck? Click Hint for a good move. The undo arrow takes your last move back.",
        "Your game is kept, so you can stop and carry on later.",
    ]),
    "patience": ("Play Patience (solitaire)", "solitaire patience cards card game klondike", [
        "Patience is the classic card game. Press ⌘Space, type Patience and press Return.",
        "Build each suit from Ace to King at the top right. On the seven columns, put cards in falling "
        "order, red on black and black on red. Only a King goes in an empty column.",
        "Click the deck to turn cards over. Drag a card to move it, or double-click it to send it home.",
        "Stuck? Click Hint. ⌘Z undoes a move. Once every card is face up, click Finish.",
    ]),
    "mines": ("Play Mines", "mines minesweeper puzzle game flag", [
        "Mines is a puzzle game. Press ⌘Space, type Mines and press Return.",
        "Click a square to open it. A number tells how many squares around it hide a mine. "
        "The first click is always safe.",
        "Right-click, or hold Control and click, to flag a square you think hides a mine. Click a number "
        "whose mines are all flagged to open everything around it.",
        "Pick Small, Medium or Large at the top. Your best time for each is kept.",
    ]),
    "books": ("Read e-books", "books ebook epub read reader library novel kindle", [
        "Books reads EPUB e-books. Press ⌘Space, type Books and press Return.",
        "Click Add Books to bring books in, or put EPUB files in the Books folder in your home. "
        "Many free classics are on Project Gutenberg.",
        "Click a book to read it. Click the right side of the page or press → for the next page.",
        "Click the list button for the contents, and Aa for bigger text or sepia and night pages. "
        "Books keeps your place in every book.",
    ]),
    "piano": ("Play the piano", "piano ivory music keyboard instrument organ notes play record tune", [
        "Ivory is a piano. Press ⌘Space, type Ivory and press Return.",
        "Click the keys, or play on the computer's keyboard: the bottom row of letters plays the lower notes "
        "and the top row plays the higher ones. The letters are shown on the keys.",
        "Choose another sound, like organ, music box or flute, from the menu at the top left. "
        "The arrows move the keyboard higher or lower.",
        "Click Record, play a tune, then click Stop. Click Play to hear it again.",
    ]),
    "dictionary": ("Look up a word", "dictionary words define definition meaning synonym thesaurus spelling", [
        "Words is a dictionary that works without the internet. Press ⌘Space, type Words and press Return.",
        "Type a word in the search box at the top and press Return. Words finds a word from its other forms "
        "too, so ran finds run.",
        "Click any blue word, like one that means the same, to look that up. The arrows go back and forward.",
        "Words shows a new word of the day each time you open it.",
    ]),
    "typing": ("Learn to type", "typing typist keyboard lessons practice touch type speed", [
        "Typist teaches typing without looking at the keys. Press ⌘Space, type Typist and press Return.",
        "Start with lesson 1. Rest your fingers on the middle row of keys and type the letters you see. "
        "The keyboard on the screen lights up the next key in the colour of the finger to use.",
        "A wrong key turns red, and you can carry on once you type the right one.",
        "At the end of a lesson you see your speed and accuracy and earn up to three stars. "
        "Press Return for the next lesson.",
    ]),
    "screentime": ("See your screen time and set limits", "screen time logbook usage hours limit parental controls kids apps time", [
        "Logbook shows how long each app was used. Press ⌘Space, type Logbook and press Return.",
        "Today shows each hour of the day, and Last 7 Days shows each day of the week, with the apps used most "
        "at the top. Time only counts while someone is using the computer, not while it's locked or left alone.",
        "To limit an app, click Set Limit beside it and choose how long it may be used each day. Five minutes "
        "before the time is up a notice says so, and at the limit its windows close until the next day.",
        "Choose Limits ▸ Passcode… to set a passcode, so that only someone who knows it can change a limit.",
    ]),
    "sudoku": ("Play a number puzzle", "sudoku nine number puzzle game logic grid", [
        "Nine is a number puzzle. Press ⌘Space, type Nine and press Return.",
        "Fill the grid so that every row, every column and every 3 × 3 box has each number from 1 to 9 once. "
        "Click a square, then click a number at the bottom or type it.",
        "Turn on the pencil (or press P) to jot small numbers you think might fit. Hold Shift while typing a "
        "number to do the same.",
        "Choose Easy to Expert at the top. Hint fills in one square, and ⌘Z undoes a move.",
    ]),
    "fonts": ("See and add fonts", "fonts font book typecase typeface install font add font letters", [
        "Typecase shows every font on the computer. Press ⌘Space, type Typecase and press Return.",
        "Click a font to see all of its styles. Type in the box at the top to see your own words in it, and "
        "drag the slider to make it bigger or smaller.",
        "To add a font, double-click its file and click Install Font, or click + in Typecase and choose the files. "
        "Every app can use it after that.",
        "Fonts you added are under My Fonts. To take one away, choose it and click Remove Font.",
    ]),
    "memory-game": ("Play the memory game", "memory game pairs match matching cards concentration kids two players", [
        "Pairs is a memory game. Press ⌘Space, type Pairs and press Return.",
        "Click a card to turn it over, then click another. If the pictures match, they stay up. If not, they "
        "turn back over, so try to remember where they were.",
        "Choose the size and the pictures at the top. With 2 Players, you take turns, and finding a pair "
        "gives you another go.",
    ]),
    "graphs": ("Draw a graph of an equation", "graph graphing plot equation function curve math maths calculator", [
        "Plot draws equations. Press ⌘Space, type Plot and press Return.",
        "Type an equation in a box on the left, such as y = x^2 - 3 or sin(x). Use ^ for powers, and you can "
        "write 2x for 2 times x. Click Add Equation for another one in a new colour.",
        "Drag the graph to move it and scroll to zoom. Point at a curve to read its value there.",
        "Put the letter a in an equation, such as a·x^2, and drag the slider for a to watch the curve change.",
    ]),
    "whiteboard": ("Plan ideas on a board", "whiteboard board corkboard sticky notes ideas brainstorm plan pictures", [
        "Corkboard is a big board for notes and pictures. Press ⌘Space, type Corkboard and press Return.",
        "Click Note, Text, Shape or Picture at the top, or double-click anywhere on the board for a note. "
        "Double-click a note or shape to write in it.",
        "Drag things to move them, and drag the small square at the corner to make them bigger. Choose a "
        "colour with the round button at the top.",
        "Drag empty space to move around the board, and hold ⌘ while you scroll to zoom. Click New Board "
        "for another board.",
    ]),
    "jigsaw": ("Do a jigsaw puzzle", "jigsaw puzzle pieces picture photo kids game", [
        "Jigsaw cuts a picture into puzzle pieces. Press ⌘Space, type Jigsaw and press Return.",
        "Click New Puzzle… to pick a picture, or Choose a Photo… to use one of yours, and pick how many pieces.",
        "Drag pieces onto the board. Pieces that fit click together, and pieces in the right place lock into "
        "the frame.",
        "Click Peek to see the whole picture faintly behind the board, and Spread Out to tidy loose pieces.",
    ]),
    "about-computer": ("See what's inside this computer", "about this computer system information specs hardware "
                       "processor memory storage graphics usb version report", [
        "Click the freemac menu at the left of the menu bar and choose About freemac.",
        "You'll see the processor, graphics, memory, free space and the version of freemac.",
        "Click More Info… for the full report: disks, displays, USB devices, network, sound and battery. "
        "Click Copy to copy it, for example to send to someone helping you.",
    ]),
    "pick-colour": ("Pick a colour from the screen", "colour color picker eyedropper hex rgb hsl swatch palette", [
        "Swatch picks colours. Press ⌘Space, type Swatch and press Return.",
        "Click Pick from Screen, then click anywhere. The loupe shows the pixels under the pointer.",
        "Click the copy button next to Hex, RGB or HSL to copy that value. Click Add to Palette to keep the "
        "colour for later.",
    ]),
    "tangram": ("Make shapes with Tangram", "tangram shape puzzle pieces triangle kids game", [
        "Tangram has seven flat pieces to make a shape. Press ⌘Space, type Tangram and press Return.",
        "Pick a shape from the menu at the top. Drag pieces onto the grey outline to fill it.",
        "Click a piece to turn it. Right-click the parallelogram to flip it over.",
        "Click Hint to see where one piece goes.",
    ]),
    "podcasts": ("Listen to podcasts and follow news feeds", "podcast feed rss atom news subscribe episode buoy listen", [
        "Buoy follows podcasts and websites. Press ⌘Space, type Buoy and press Return.",
        "Click the + button (or press ⌘N) and type the address of a podcast's feed, or of a website that has a feed.",
        "New posts and episodes show with a blue dot. Click one to read it, and click Play to listen.",
        "Buoy keeps your place in every episode. Change the speed with the button at the right of the player.",
        "To move your podcasts from another app, export them there as OPML and choose File > Import Subscriptions.",
    ]),
    "word-search": ("Play a word search", "word search hunt puzzle letters grid kids game", [
        "Hunt hides words in a grid of letters. Press ⌘Space, type Hunt and press Return.",
        "Drag from the first letter of a word to its last, or click one and then the other.",
        "Pick a theme from the menu at the top, and Small, Medium or Large. Larger grids hide words on "
        "slants and backwards.",
        "Click Hint to see the first letter of a word you haven't found.",
    ]),
    "four-in-a-row": ("Play four in a row", "four in a row connect counters fourway board game kids", [
        "Fourway is four in a row. Press ⌘Space, type Fourway and press Return.",
        "Click a column to drop a counter. Line up four of yours across, down or on a slant to win.",
        "Choose Computer or Friend at the top. Against the computer, pick Easy, Medium or Hard.",
        "Press ⌘Z to take back a move.",
    ]),
    "draughts": ("Play draughts (checkers)", "draughts checkers kings board game crown jump", [
        "Kings is draughts, also called checkers. Press ⌘Space, type Kings and press Return.",
        "Click one of your pieces, then one of the marked squares to move it there.",
        "Taking is compulsory: when one of your pieces can jump, it's ringed and has to. A piece that "
        "reaches the far side becomes a king and can move backwards too.",
        "Choose Computer or Friend at the top, and press ⌘Z to take back a move.",
    ]),
    "tile-matching": ("Play tile matching", "tile matching solitaire cairn pairs stack pictures", [
        "Cairn is a tile-matching game. Press ⌘Space, type Cairn and press Return.",
        "Click two free tiles with the same picture to take them away. A tile is free when nothing is "
        "on top of it and its left or right side is open. Blocked tiles are shaded.",
        "Pick a layout from the menu at the top. Pyramid is the easiest.",
        "Click Hint to see a pair you can take, Shuffle to mix the tiles that are left, or ⌘Z to put a "
        "pair back. Every game can be cleared.",
    ]),
    "maths-practice": ("Practise maths", "maths math sums adding times tables multiply divide sharing kids", [
        "Sums is maths practice. Press ⌘Space, type Sums and press Return.",
        "Pick Adding, Taking Away, Times Tables or Sharing, then a level. A round has ten questions.",
        "Type the answer and press Return. A wrong answer gets one more try, then Sums shows the right one.",
        "Get stars for answers right first time. Click Times Tables at the top to see every times table, "
        "and click a number along the top of the chart to practise just that table.",
    ]),
    "flashcards": ("Study with flashcards", "flashcards cards study revise learn spelling cue deck", [
        "Cue makes flashcards. Press ⌘Space, type Cue and press Return.",
        "Click + to make a deck, then type a question and its answer and click Add Card.",
        "Click Study. Press Space to turn a card over, then Knew It or Didn't Know It. Cards you didn't "
        "know come back sooner, and ones you know well wait longer.",
        "To bring in cards from a spreadsheet, save it as CSV and choose File > Import Cards.",
    ]),
    "scanning": ("Scan a document or photo", "scan scanner scanning document photo printer all-in-one pdf glass", [
        "Glass scans with a scanner or an all-in-one printer, plugged in or on your network. Press ⌘Space, "
        "type Glass and press Return.",
        "Put the page face down on the glass and click Preview. To scan only part of it, drag over the "
        "preview.",
        "Choose Colour or Grey and a resolution, then click Scan. Each scan becomes a page along the bottom.",
        "Click Save to keep the pages as one PDF or as pictures. They go to your Documents folder unless "
        "you choose another.",
    ]),
    "spreadsheet": ("Make a spreadsheet", "spreadsheet table numbers sum formula csv chart budget ledger grades", [
        "Ledger makes spreadsheets. Press ⌘Space, type Ledger and press Return.",
        "Click a cell and type a number or words, then press Return. To work something out, start with =, "
        "for example =SUM(B2:B6) or =AVERAGE(B2:D2). While typing a formula you can click cells to put them in.",
        "Select cells and click Sum to add them up, Chart to draw them, or Sort to put the rows in order. "
        "The total, average and count of the selected cells show along the bottom.",
        "⌘D copies a cell down the selection, changing its formula to fit each row. Ledger opens and saves "
        "CSV files as well as its own.",
    ]),
    "presentation": ("Make a presentation", "presentation slides slideshow lantern talk project school pdf", [
        "Lantern makes slideshows. Press ⌘Space, type Lantern and press Return.",
        "Type the slide's title and its points on the right, one point on each line. Choose… adds a picture.",
        "Click Add Slide for the next slide, and Theme to change the colours of them all.",
        "Click Play to show the slides full screen. Press the right arrow or Space for the next slide and Esc "
        "to stop. File > Export as PDF makes a copy to print or hand in.",
    ]),
    "clipboard": ("Paste something copied earlier", "clipboard history paste copied earlier", [
        "Press ⇧⌘V to see what you copied recently. Click one to copy it again, then paste it with ⌘V.",
    ]),
    "photos": ("Bring in photos from a phone or camera", "photos pictures import camera phone iphone android sd card cove", [
        "Connect the phone or camera with its cable, or put its memory card in. On a phone, allow access "
        "to photos when it asks.",
        "Open Cove. The phone or camera shows in the sidebar under Devices: click it.",
        "Click Import All New Items. Photos already brought in are dimmed with a tick and aren't copied again.",
        "To bring in only some, click one, then ⌘-click the others, and click Import Selected.",
        "The photos go into your Pictures folder, in a folder for each day, and show in Cove under "
        "Recently Added.",
    ]),
    "drives": ("Use a USB drive or memory card", "usb drive stick flash memory card sd disk external eject unmount", [
        "Plug the drive in. Its icon shows on the Desktop, at the top right, and under Locations in "
        "Drawer's sidebar.",
        "Double-click the icon, or click it in Drawer, to see what's on it. Drag files onto it to copy them there.",
        "Before you pull it out, eject it: click the Eject button next to it in Drawer, press ⌘E, or drag its "
        "icon onto the Trash in the Dock. Its icon goes away when it's safe to unplug.",
        "If it says the disk wasn't ejected, an app still has a file open on it. Close that file or quit the app, "
        "and eject it again.",
    ]),
    "calendars": ("Show, hide and colour your calendars", "calendar calendars colour color hide show tide work family", [
        "In Tide, click Calendars at the top left (or press ⌥⌘S) to see the list of your calendars: "
        "Home on this computer, each calendar from an online account, and Birthdays.",
        "Click a calendar's box to show or hide its events. Hidden calendars still sync and still give alerts.",
        "Right-click a calendar to give it another colour.",
        "To move an event to another calendar, double-click it and pick one next to calendar:. "
        "It moves online too, the next time the account syncs.",
    ]),
    "albums": ("Make a photo album and play a slideshow", "album albums photos pictures slideshow cove collection", [
        "In Cove, click + next to My Albums (or press ⌘N), type a name and press Return.",
        "To add photos, drag them onto the album in the sidebar, or select them, right-click and choose Add to Album. "
        "Hold ⌘ or Shift while you click to select more than one.",
        "To take a photo out of an album, open the album, select the photo and press Delete. "
        "It stays in your library.",
        "To play a slideshow, open an album (or the Library) and click the play button at the top right. "
        "Space pauses, the arrow keys go back and forward, and Esc ends it.",
    ]),
    "share": ("Send files by mail or copy them to a drive", "share send mail email attach copy usb drive stick", [
        "In Drawer, Cove or Frame, select what you want to send and click the Share button at the top "
        "(a tray with an arrow), or right-click and choose Share. File > Share… does the same.",
        "Mail opens a new message in Post with the files attached. Type who it's to and click Send.",
        "Copy to puts a copy on a USB drive or memory card that's plugged in. If the drive already has a file "
        "with that name, the copy is called “name 2”, so nothing is replaced.",
        "When the copy is done, Drawer's status line or a notification says so. "
        "Eject the drive before you unplug it.",
    ]),
    "copy-files": ("Copy, move and duplicate files", "copy paste move cut duplicate drag folder undo files "
                   "replace keep both", [
        "Drag files onto a folder, a place in Drawer's sidebar, the Desktop or another Drawer window to move "
        "them there. Onto another disk, such as a USB drive, they're copied instead. Hold ⌥ while you drop "
        "to copy them anyway.",
        "Or select them and press ⌘C, open the folder where they should go, and press ⌘V for a copy, or ⌥⌘V "
        "to move them. Edit > Paste Item and Move Item Here do the same.",
        "⌘D makes a copy beside the original, called “name copy”.",
        "If the folder already has something with that name, you're asked: Keep Both (the new one is called "
        "“name 2”), Stop, or Replace (the old one goes to the Trash).",
        "A long copy shows a small window with how much is left. Click its stop button to stop it; the half-made "
        "copy is removed.",
        "Changed your mind? ⌘Z (Edit > Undo) takes back the last move, copy, rename, new folder or Move to Trash.",
    ]),
    "music": ("Play your music", "music songs album artist play shuffle repeat mp3 shanty itunes playlist", [
        "Shanty plays the music in your Music folder. Click it in the Dock. It finds new songs each time it opens.",
        "To add songs, drag them or their folder onto Shanty's window, or choose File > Add to Library…. "
        "They're copied into your Music folder.",
        "Albums, Artists, Songs and Recently Added are in the sidebar. Double-click a song or an album to play it.",
        "- Space plays and pauses, ⌘→ and ⌘← go to the next and previous song.",
        "- The buttons at the top turn shuffle and repeat on and off. Click repeat again to repeat one song.",
        "- Type in the search field to find a song, an artist or an album.",
        "The song playing shows in the menu bar's quick settings, and the media keys on your keyboard work "
        "even when Shanty is behind other windows.",
    ]),
    "videos": ("Watch a video", "video movie film play watch mp4 mov quicktime player reel full screen", [
        "Reel plays videos. Double-click a video in Drawer. Or press ⌘Space, type Reel, and double-click "
        "one of the videos in your Videos folder.",
        "Move the pointer to show the controls; they fade while the video plays.",
        "- Space plays and pauses. ← and → go back or forward 10 seconds.",
        "- F, or the button at the right of the controls, fills the screen. Esc goes back.",
        "- ↑ and ↓ turn the sound up and down.",
        "Close a video partway through and Reel starts it again where you stopped next time.",
    ]),
    "backups": ("Back up your files", "backup back up time machine lifeboat drive restore copy safe", [
        "Lifeboat copies your home folder to a drive every hour while the drive is plugged in, and keeps "
        "earlier backups, so you can get back a file you deleted or changed.",
        "Plug in a USB drive or another disk, choose Dials > Lifeboat, and pick it next to Backup drive. "
        "The first backup starts within a minute and takes a while; later ones only copy what changed.",
        "If it says the drive can't hold backups, click Erase Drive…. Everything on it is deleted.",
        "Lifeboat keeps every backup of the last day, one a day for a month, and one a week before that. "
        "When the drive is full, the oldest go first.",
        "To eject the drive, eject it as usual. A backup that's running stops and starts again next time.",
    ]),
    "date-time": ("Set the date, time and time zone", "date time clock time zone timezone city 24-hour 12-hour seconds automatic wrong time travel", [
        "Choose Dials > Date & Time.",
        "Turn on Set the time automatically to keep the clock right from the internet. Turn it off to set the date and time yourself with Set….",
        "To change the time zone, click the box under Time zone, type a city and pick it from the list.",
        "Choose 12-hour or 24-hour time, and whether the menu bar shows the day, the date and seconds.",
        "Changing the time or time zone asks for an administrator's password.",
    ]),
    "dock-hide": ("Hide the Dock until you need it", "dock hide hides automatically autohide auto-hide show more room bottom screen", [
        "Choose Dials > Dock and Menu Bar and turn on Automatically hide and show the Dock, or press ⌥⌘D.",
        "The Dock slides away and windows can use the whole screen. Move the pointer to the bottom "
        "edge of the screen and it slides back up.",
        "It stays up while the pointer is on it or one of its menus is open, and hides again when you move away.",
        "Press ⌥⌘D again to keep it on screen all the time.",
    ]),
    "stacks": ("Tidy the desktop with stacks", "stacks stack desktop tidy clean up arrange sort kind messy screenshots get info", [
        "Right-click an empty part of the desktop and choose Use Stacks, or press Control+Command+0. "
        "Files of one kind go into a pile: Images, Screenshots, Documents, PDF Documents and so on.",
        "Click a stack to spread its files out on the desktop, and click it again to gather them up.",
        "New files go straight into their stack, so a desktop full of screenshots stays tidy.",
        "With stacks off, Clean Up By Name, Kind or Date Modified puts every icon back in a neat order. "
        "Get Info (Command+I) tells you about a file.",
    ]),
    "screen-saver": ("Use a screen saver", "screen saver screensaver idle drift clock album photos slideshow", [
        "Choose Dials > Screen Saver and click the one you like: Drift, Clock or Album, which shows the "
        "photos in your Pictures folder.",
        "It starts when nothing has been touched for the time under Start the screen saver after. "
        "Click Preview to see it now.",
        "Move the pointer or press a key to end it. If the screen was due to lock, it asks for your password.",
        "To start it from a corner of the screen, choose it under Hot Corners in Dials > Dock and Menu Bar.",
    ]),
    "recovery": ("Fix a computer that won't start", "recovery mode recover repair fix start startup boot won't start forgotten password reset reinstall disk check ctrl", [
        "freemac Recovery fixes a computer that won't start properly. To open it, hold Ctrl while the "
        "computer starts, or choose Dials > Power > Restart in Recovery….",
        "Type an administrator's password, then choose what to do and click Continue:",
        "- Restore from Lifeboat brings a home folder back from a backup drive. Plug the drive in first.",
        "- Reset a Password chooses a new password for someone who has forgotten theirs.",
        "- Check a Disk looks for problems on a disk and fixes them.",
        "- Reinstall freemac puts a fresh copy on the disk from a freemac USB stick.",
        "- Get Help Online opens these pages on the web. Join a Wi-Fi network first, from the top right.",
        "When you're done, click the power button at the top right and choose Restart.",
    ]),
    "restore": ("Get back a file from a backup", "restore backup lifeboat deleted lost earlier version old file", [
        "Press F4 and click Lifeboat, or choose Go > Browse Backups in Drawer to start at that folder. "
        "The backup drive must be plugged in.",
        "Backups are listed by date on the left. Choose a time, then open folders as you would in Drawer.",
        "The Now column says whether each file is the same now, has changed since, or is gone now.",
        "Double-click a file to open a copy of it. Choose the files you want, then click Restore: copies go back "
        "where they were. If there's already a file with that name, you're asked whether to keep both.",
    ]),
}


def matching(query):
    """Names of the topics whose title or usual words hold every word of the
    query, those whose title has the first word first."""
    words = query.lower().split()
    if not words:
        return []
    found = []
    for name, (title, usual, _body) in TOPICS.items():
        low = title.lower()
        text = (low + " " + usual).split()
        if all(any(t.startswith(w) for t in text) for w in words):
            found.append((0 if any(t.startswith(words[0]) for t in low.split()) else 1, name))
    return [name for _rank, name in sorted(found, key=lambda f: f[0])]
