import Foundation

// MARK: - Emoji

/// One emoji and the words a person might type to find it.
///
/// `keywords` is a single space-separated string rather than an array of words: it keeps the
/// catalogue below readable as a table, and it matches how the search works — every word of the
/// query has to appear somewhere in that string.
public struct Emoji: Equatable {
    public let char: String
    /// Already folded (lowercased, no diacritics) by `EmojiCatalog`.
    public let keywords: String

    public init(char: String, keywords: String) {
        self.char = char
        self.keywords = keywords
    }
}

/// The emoji that `:` offers.
///
/// Raycast's picker is a short, curated list rather than the full Unicode set — a search for
/// "serce" should find the heart, not forty near-identical hearts. The list below is hand-picked
/// and ordered roughly by how often each one is used, so an empty query shows the most useful
/// rows first. Keywords carry both Polish and English words, because the app is used in Polish
/// but habits are often English.
public enum EmojiCatalog {

    /// Search results shown at once. Eight columns by six rows fills the picker exactly, so most
    /// searches need no scrolling.
    public static let pageSize = 48

    public static func search(_ query: String, limit: Int = EmojiCatalog.pageSize) -> [Emoji] {
        let words = TextFold.fold(query)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return Array(all.prefix(limit)) }

        // Every word must match, and a word that starts a keyword ("smile" in "usmiech smile")
        // ranks above one found halfway through ("face" in "twarz face"). 1000 keeps the two
        // groups apart without needing a tuple comparison.
        var scored: [(rank: Int, index: Int, emoji: Emoji)] = []
        for (index, emoji) in all.enumerated() {
            var rank = 0
            var matches = true
            for word in words {
                guard let found = emoji.keywords.range(of: word) else {
                    matches = false
                    break
                }
                let position = emoji.keywords.distance(from: emoji.keywords.startIndex, to: found.lowerBound)
                let startsWord = position == 0 || emoji.keywords[emoji.keywords.index(before: found.lowerBound)] == " "
                rank += startsWord ? position : position + 1000
            }
            if matches { scored.append((rank, index, emoji)) }
        }
        scored.sort { $0.rank == $1.rank ? $0.index < $1.index : $0.rank < $1.rank }
        return scored.prefix(limit).map(\.emoji)
    }

    public static let all: [Emoji] = raw.map {
        Emoji(char: $0.char, keywords: TextFold.fold($0.keywords))
    }

    // MARK: catalogue

    private static let raw: [Emoji] = [        // Faces and moods
        Emoji(char: "😀", keywords: "usmiech radosc szczescie smile happy grin twarz"),
        Emoji(char: "😄", keywords: "usmiech radosc smile happy"),
        Emoji(char: "😊", keywords: "usmiech rumieniec blush smile"),
        Emoji(char: "🙂", keywords: "usmiech smile"),
        Emoji(char: "😉", keywords: "oczko wink"),
        Emoji(char: "😂", keywords: "placz smiechu lzy laugh joy tears"),
        Emoji(char: "🤣", keywords: "rotfl smiech laugh lol"),
        Emoji(char: "😆", keywords: "smiech laugh happy"),
        Emoji(char: "🥰", keywords: "zakochany serca love hearts"),
        Emoji(char: "😍", keywords: "zakochanie serca oczy love heart eyes"),
        Emoji(char: "🤩", keywords: "gwiazdy ekscytacja star struck wow"),
        Emoji(char: "😘", keywords: "calus kiss"),
        Emoji(char: "😋", keywords: "pyszne pycha yummy"),
        Emoji(char: "😜", keywords: "jezyk oczko tongue wink"),
        Emoji(char: "🤪", keywords: "szalony wariacki crazy zany"),
        Emoji(char: "🤗", keywords: "przytul hug"),
        Emoji(char: "🤔", keywords: "myslenie zastanowienie thinking hmm"),
        Emoji(char: "🤭", keywords: "chichot giggle"),
        Emoji(char: "🤫", keywords: "cisza cicho shush quiet"),
        Emoji(char: "🙄", keywords: "przewracanie oczu roll eyes"),
        Emoji(char: "😏", keywords: "usmieszek smirk"),
        Emoji(char: "😐", keywords: "neutralny neutral"),
        Emoji(char: "😔", keywords: "smutny przygnebiony sad pensive"),
        Emoji(char: "😢", keywords: "placz lzy cry tear"),
        Emoji(char: "😭", keywords: "placz lzy szloch sob cry"),
        Emoji(char: "😤", keywords: "duma tryumf triumph"),
        Emoji(char: "😡", keywords: "zlosc wscieklosc anger rage"),
        Emoji(char: "🤯", keywords: "eksplodujaca glowa mind blown"),
        Emoji(char: "😱", keywords: "krzyk strach scream fear"),
        Emoji(char: "😳", keywords: "zawstydzenie rumieniec flushed"),
        Emoji(char: "🥺", keywords: "blaganie proszenie pleading"),
        Emoji(char: "😴", keywords: "sen spiacy sleep zzz"),
        Emoji(char: "🥱", keywords: "ziewanie nuda yawn"),
        Emoji(char: "🤒", keywords: "termometr chory thermometer sick"),
        Emoji(char: "🥵", keywords: "goraco hot"),
        Emoji(char: "🥶", keywords: "zimno cold"),
        Emoji(char: "😎", keywords: "okulary cool fajny sunglasses"),
        Emoji(char: "🤓", keywords: "kujon nerd okulary"),
        Emoji(char: "🥳", keywords: "impreza urodziny party"),
        Emoji(char: "🤠", keywords: "kowboj cowboy"),
        Emoji(char: "😇", keywords: "aniol aureola angel halo"),

        // Gestures and people
        Emoji(char: "👍", keywords: "kciuk gore ok dobrze thumbs up"),
        Emoji(char: "👎", keywords: "kciuk dol zle thumbs down"),
        Emoji(char: "👌", keywords: "ok dobrze ok sign"),
        Emoji(char: "✌️", keywords: "victory peace dwa palce"),
        Emoji(char: "🤞", keywords: "kciuki szczescie fingers crossed"),
        Emoji(char: "🤟", keywords: "love you"),
        Emoji(char: "👏", keywords: "brawa oklaski clap"),
        Emoji(char: "🙌", keywords: "rece gore raise hands"),
        Emoji(char: "🙏", keywords: "prosba dziekuje modlitwa pray thanks"),
        Emoji(char: "🤝", keywords: "uscisku dloni handshake umowa"),
        Emoji(char: "👋", keywords: "czesc machanie wave hello"),
        Emoji(char: "✋", keywords: "reka stop hand"),
        Emoji(char: "🤙", keywords: "call me zadzwon"),
        Emoji(char: "💪", keywords: "miesien sila strong muscle"),
        Emoji(char: "🧠", keywords: "mozg brain"),
        Emoji(char: "👀", keywords: "oczy patrzenie eyes look"),
        Emoji(char: "👂", keywords: "ucho ear"),
        Emoji(char: "🦷", keywords: "zab tooth"),
        Emoji(char: "🦴", keywords: "kosc bone"),
        Emoji(char: "🫀", keywords: "anatomiczne serce organ heart"),
        Emoji(char: "✍️", keywords: "pisanie writing"),
        Emoji(char: "🧘", keywords: "joga medytacja yoga meditate"),
        Emoji(char: "🏃", keywords: "bieg bieganie run"),
        Emoji(char: "🚶", keywords: "spacer chodzenie walk"),

        // Hearts and symbols
        Emoji(char: "❤️", keywords: "serce milosc love heart"),
        Emoji(char: "🧡", keywords: "serce pomaranczowe orange heart"),
        Emoji(char: "💛", keywords: "serce zolte yellow heart"),
        Emoji(char: "💚", keywords: "serce zielone green heart"),
        Emoji(char: "💙", keywords: "serce niebieskie blue heart"),
        Emoji(char: "💜", keywords: "serce fioletowe purple heart"),
        Emoji(char: "🖤", keywords: "serce czarne black heart"),
        Emoji(char: "🤍", keywords: "serce biale white heart"),
        Emoji(char: "💔", keywords: "zlamane serce broken heart"),
        Emoji(char: "💕", keywords: "serca milosc hearts love"),
        Emoji(char: "💖", keywords: "iskrzace serce sparkling heart"),
        Emoji(char: "💘", keywords: "serce strzala cupid"),
        Emoji(char: "💝", keywords: "serce wstazka gift heart"),
        Emoji(char: "✨", keywords: "iskry gwiazdki sparkles"),
        Emoji(char: "⭐", keywords: "gwiazda star"),
        Emoji(char: "🌟", keywords: "swiecaca gwiazda star"),
        Emoji(char: "💫", keywords: "zawroty gwiazda dizzy"),
        Emoji(char: "⚡", keywords: "blyskawica piorun lightning"),
        Emoji(char: "🔥", keywords: "ogien plomien fire"),
        Emoji(char: "💥", keywords: "wybuch eksplozja boom"),
        Emoji(char: "💧", keywords: "kropla woda drop water"),
        Emoji(char: "🌈", keywords: "tecza rainbow"),
        Emoji(char: "☀️", keywords: "slonce pogoda sun sunny"),
        Emoji(char: "🌙", keywords: "ksiezyc noc moon"),
        Emoji(char: "☁️", keywords: "chmura cloud"),
        Emoji(char: "🌧️", keywords: "deszcz rain"),
        Emoji(char: "⛈️", keywords: "burza storm"),
        Emoji(char: "❄️", keywords: "snieg sniezynka snow"),

        // Work, marks and feedback
        Emoji(char: "✅", keywords: "zrobione tak gotowe check done"),
        Emoji(char: "☑️", keywords: "zaznaczone check"),
        Emoji(char: "❌", keywords: "blad nie cross error"),
        Emoji(char: "⚠️", keywords: "uwaga ostrzezenie warning"),
        Emoji(char: "❗", keywords: "wykrzyknik exclamation"),
        Emoji(char: "❓", keywords: "pytanie question"),
        Emoji(char: "💡", keywords: "zarowka pomysl idea bulb"),
        Emoji(char: "🔔", keywords: "dzwonek bell"),
        Emoji(char: "🔕", keywords: "dzwonek wyciszony bell muted"),
        Emoji(char: "📌", keywords: "pinezka pin"),
        Emoji(char: "📍", keywords: "pinezka lokalizacja pin location"),
        Emoji(char: "📎", keywords: "spinacz paperclip"),
        Emoji(char: "🔗", keywords: "link odnosnik chain"),
        Emoji(char: "📝", keywords: "notatka notatnik note memo"),
        Emoji(char: "📄", keywords: "dokument dokumenty document page"),
        Emoji(char: "📋", keywords: "schowek clipboard"),
        Emoji(char: "📊", keywords: "wykres slupki chart bar"),
        Emoji(char: "📈", keywords: "wykres wzrost chart up"),
        Emoji(char: "📉", keywords: "wykres spadek chart down"),
        Emoji(char: "📅", keywords: "kalendarz data calendar"),
        Emoji(char: "🗓️", keywords: "kalendarz calendar"),
        Emoji(char: "⏰", keywords: "budzik alarm clock"),
        Emoji(char: "⏳", keywords: "klepsydra hourglass"),
        Emoji(char: "🕐", keywords: "zegar czas clock"),
        Emoji(char: "📦", keywords: "paczka pudelko box package"),
        Emoji(char: "💰", keywords: "pieniadze money"),
        Emoji(char: "💳", keywords: "karta platnicza card"),
        Emoji(char: "🧾", keywords: "paragon rachunek receipt"),
        Emoji(char: "🧪", keywords: "probowka test tube"),
        Emoji(char: "🧬", keywords: "dna gen"),
        Emoji(char: "⚙️", keywords: "zebatka ustawienia gear settings"),
        Emoji(char: "🛠️", keywords: "narzedzia tools"),
        Emoji(char: "🔑", keywords: "klucz key"),
        Emoji(char: "🔒", keywords: "zamkniety zamek lock"),
        Emoji(char: "🔓", keywords: "otwarty zamek unlock"),
        Emoji(char: "🛡️", keywords: "tarcza ochrona shield"),
        Emoji(char: "⚖️", keywords: "waga sprawiedliwosc balance justice"),
        Emoji(char: "🎯", keywords: "cel tarcza bullseye target"),
        Emoji(char: "🏆", keywords: "puchar trofeum trophy"),
        Emoji(char: "🥇", keywords: "zloty medal pierwszy gold first"),
        Emoji(char: "🎉", keywords: "impreza konfetti party"),
        Emoji(char: "🎊", keywords: "konfetti confetti"),
        Emoji(char: "🎈", keywords: "balon balloon"),
        Emoji(char: "🎁", keywords: "prezent podarunek gift"),
        Emoji(char: "🎓", keywords: "dyplom czapka graduation"),
        Emoji(char: "📢", keywords: "megafon ogloszenie megaphone"),
        Emoji(char: "🚀", keywords: "rakieta start rocket launch"),
        Emoji(char: "🔍", keywords: "lupa szukaj search"),
        Emoji(char: "📚", keywords: "ksiazki books"),
        Emoji(char: "📖", keywords: "otwarta ksiazka book"),
        Emoji(char: "📰", keywords: "gazeta newspaper"),
        Emoji(char: "🧩", keywords: "puzzle"),
        Emoji(char: "🎨", keywords: "paleta malowanie art paint"),
        Emoji(char: "✏️", keywords: "olowek pencil"),
        Emoji(char: "🖊️", keywords: "dlugopis pen"),
        Emoji(char: "💬", keywords: "wiadomosc dymek message"),
        Emoji(char: "💭", keywords: "mysli myslenie thought"),

        // Tech
        Emoji(char: "💻", keywords: "laptop komputer computer"),
        Emoji(char: "🖥️", keywords: "monitor komputer desktop"),
        Emoji(char: "⌨️", keywords: "klawiatura keyboard"),
        Emoji(char: "🖱️", keywords: "myszka mouse"),
        Emoji(char: "🖨️", keywords: "drukarka printer"),
        Emoji(char: "💾", keywords: "dyskietka zapis save"),
        Emoji(char: "📱", keywords: "telefon komorka phone mobile"),
        Emoji(char: "📞", keywords: "telefon rozmowa call"),
        Emoji(char: "📧", keywords: "email mail"),
        Emoji(char: "📨", keywords: "koperta mail envelope"),
        Emoji(char: "📤", keywords: "wyslij upload"),
        Emoji(char: "📥", keywords: "odbierz pobierz download inbox"),
        Emoji(char: "🎮", keywords: "gra pad game"),
        Emoji(char: "🎧", keywords: "sluchawki headphones"),
        Emoji(char: "🎵", keywords: "nuta muzyka music"),
        Emoji(char: "🎤", keywords: "mikrofon singing"),
        Emoji(char: "🎬", keywords: "klaps film movie"),
        Emoji(char: "📷", keywords: "aparat zdjecie camera"),
        Emoji(char: "🤖", keywords: "robot ai"),
        Emoji(char: "🔬", keywords: "mikroskop lab microscope"),
        Emoji(char: "🔭", keywords: "teleskop telescope"),

        // Nature and animals
        Emoji(char: "🐶", keywords: "piesek pies dog"),
        Emoji(char: "🐱", keywords: "kotek kot cat"),
        Emoji(char: "🐭", keywords: "mysz mouse"),
        Emoji(char: "🐹", keywords: "chomik hamster"),
        Emoji(char: "🐰", keywords: "krolik zajac rabbit bunny"),
        Emoji(char: "🦊", keywords: "lis fox"),
        Emoji(char: "🐻", keywords: "niedzwiedz bear"),
        Emoji(char: "🐼", keywords: "panda"),
        Emoji(char: "🦁", keywords: "lew lion"),
        Emoji(char: "🐯", keywords: "tygrys tiger"),
        Emoji(char: "🐮", keywords: "krowa cow"),
        Emoji(char: "🐷", keywords: "swinka pig"),
        Emoji(char: "🐸", keywords: "zaba frog"),
        Emoji(char: "🐵", keywords: "malpa monkey"),
        Emoji(char: "🐔", keywords: "kura chicken"),
        Emoji(char: "🐧", keywords: "pingwin penguin"),
        Emoji(char: "🐦", keywords: "ptak bird"),
        Emoji(char: "🦆", keywords: "kaczka duck"),
        Emoji(char: "🦉", keywords: "sowa owl"),
        Emoji(char: "🐺", keywords: "wilk wolf"),
        Emoji(char: "🐴", keywords: "kon horse"),
        Emoji(char: "🦄", keywords: "jednorozec unicorn"),
        Emoji(char: "🐝", keywords: "pszczola bee"),
        Emoji(char: "🦋", keywords: "motyl butterfly"),
        Emoji(char: "🐌", keywords: "slimak snail"),
        Emoji(char: "🐞", keywords: "biedronka ladybug"),
        Emoji(char: "🐢", keywords: "zolw turtle"),
        Emoji(char: "🐍", keywords: "waz snake"),
        Emoji(char: "🐙", keywords: "osmiornica octopus"),
        Emoji(char: "🦀", keywords: "krab crab"),
        Emoji(char: "🐟", keywords: "ryba fish"),
        Emoji(char: "🐬", keywords: "delfin dolphin"),
        Emoji(char: "🐳", keywords: "wieloryb whale"),
        Emoji(char: "🦈", keywords: "rekin shark"),
        Emoji(char: "🌸", keywords: "kwiat wisnia flower cherry blossom"),
        Emoji(char: "🌹", keywords: "roza kwiat rose"),
        Emoji(char: "🌻", keywords: "slonecznik kwiat sunflower"),
        Emoji(char: "🌳", keywords: "drzewo tree"),
        Emoji(char: "🌵", keywords: "kaktus cactus"),
        Emoji(char: "🍀", keywords: "koniczyna szczescie clover luck"),
        Emoji(char: "🍁", keywords: "lisc klon lisci maple leaf"),
        Emoji(char: "🍂", keywords: "liscie jesien leaves autumn"),
        Emoji(char: "🪴", keywords: "roslina doniczka plant"),
        Emoji(char: "🌍", keywords: "ziemia glob swiat earth world"),
        Emoji(char: "🌋", keywords: "wulkan volcano"),
        Emoji(char: "🏔️", keywords: "gory mountain"),
        Emoji(char: "🌊", keywords: "fala morze woda wave sea"),

        // Food and drink
        Emoji(char: "☕", keywords: "kawa coffee"),
        Emoji(char: "🍵", keywords: "herbata tea"),
        Emoji(char: "🥛", keywords: "mleko milk"),
        Emoji(char: "🍺", keywords: "piwo beer"),
        Emoji(char: "🍷", keywords: "wino wine"),
        Emoji(char: "🥂", keywords: "szampan toast champagne"),
        Emoji(char: "🍸", keywords: "koktajl cocktail"),
        Emoji(char: "🥤", keywords: "napoj kubek drink cup"),
        Emoji(char: "🍎", keywords: "jablko apple"),
        Emoji(char: "🍋", keywords: "cytryna lemon"),
        Emoji(char: "🍌", keywords: "banan banana"),
        Emoji(char: "🍉", keywords: "arbuz watermelon"),
        Emoji(char: "🍇", keywords: "winogrona grapes"),
        Emoji(char: "🍓", keywords: "truskawka strawberry"),
        Emoji(char: "🍒", keywords: "wisnie cherries"),
        Emoji(char: "🍑", keywords: "brzoskwinia peach"),
        Emoji(char: "🥭", keywords: "mango"),
        Emoji(char: "🍍", keywords: "ananas pineapple"),
        Emoji(char: "🥑", keywords: "awokado avocado"),
        Emoji(char: "🍅", keywords: "pomidor tomato"),
        Emoji(char: "🥕", keywords: "marchewka carrot"),
        Emoji(char: "🌽", keywords: "kukurydza corn"),
        Emoji(char: "🥦", keywords: "brokul broccoli"),
        Emoji(char: "🍞", keywords: "chleb bread"),
        Emoji(char: "🥐", keywords: "rogalik croissant"),
        Emoji(char: "🧀", keywords: "ser cheese"),
        Emoji(char: "🥚", keywords: "jajko egg"),
        Emoji(char: "🍳", keywords: "jajecznica patelnia fried egg"),
        Emoji(char: "🥞", keywords: "nalesniki pancakes"),
        Emoji(char: "🍔", keywords: "hamburger burger"),
        Emoji(char: "🍟", keywords: "frytki fries"),
        Emoji(char: "🍕", keywords: "pizza"),
        Emoji(char: "🌭", keywords: "hot dog"),
        Emoji(char: "🥪", keywords: "kanapka sandwich"),
        Emoji(char: "🌮", keywords: "taco"),
        Emoji(char: "🥗", keywords: "salatka salad"),
        Emoji(char: "🍝", keywords: "spaghetti makaron pasta"),
        Emoji(char: "🍜", keywords: "zupa ramen noodles"),
        Emoji(char: "🍣", keywords: "sushi"),
        Emoji(char: "🍩", keywords: "paczki donut"),
        Emoji(char: "🍪", keywords: "ciasteczko cookie"),
        Emoji(char: "🎂", keywords: "tort urodziny cake birthday"),
        Emoji(char: "🍰", keywords: "ciasto tort cake slice"),
        Emoji(char: "🍫", keywords: "czekolada chocolate"),
        Emoji(char: "🍬", keywords: "cukierek candy"),
        Emoji(char: "🍯", keywords: "miod honey"),
        Emoji(char: "🧊", keywords: "kostka lodu ice"),

        // Places and things
        Emoji(char: "🏠", keywords: "dom house"),
        Emoji(char: "🏢", keywords: "biuro budynek office"),
        Emoji(char: "🏫", keywords: "szkola school"),
        Emoji(char: "🏥", keywords: "szpital hospital"),
        Emoji(char: "🏖️", keywords: "plaza urlop beach holiday"),
        Emoji(char: "🚗", keywords: "samochod auto car"),
        Emoji(char: "🚕", keywords: "taksowka taxi"),
        Emoji(char: "🚲", keywords: "rower bicycle"),
        Emoji(char: "🚂", keywords: "pociag train"),
        Emoji(char: "🚁", keywords: "helikopter helicopter"),
        Emoji(char: "✈️", keywords: "samolot lot plane flight"),
        Emoji(char: "🚢", keywords: "statek ship"),
        Emoji(char: "🛒", keywords: "wozek zakupy cart shopping"),
        Emoji(char: "🛍️", keywords: "torby zakupy bags shopping"),
        Emoji(char: "🎒", keywords: "plecak backpack"),
        Emoji(char: "🧳", keywords: "walizka luggage"),
        Emoji(char: "⌚", keywords: "zegarek watch"),
        Emoji(char: "💍", keywords: "pierscionek ring"),
        Emoji(char: "💎", keywords: "diament diamond"),
        Emoji(char: "👓", keywords: "okulary glasses"),
        Emoji(char: "🕶️", keywords: "okulary sloneczne sunglasses"),
        Emoji(char: "👕", keywords: "koszulka tshirt"),
        Emoji(char: "👔", keywords: "krawat koszula tie shirt"),
        Emoji(char: "🧥", keywords: "kurtka coat"),
        Emoji(char: "👟", keywords: "buty sportowe sneakers"),
        Emoji(char: "🎩", keywords: "kapelusz cylinder hat"),
        Emoji(char: "🧢", keywords: "czapka cap"),
        Emoji(char: "🧴", keywords: "buteleczka lotion"),
        Emoji(char: "🧻", keywords: "papier toaletowy toilet paper"),
        Emoji(char: "🧹", keywords: "miotla broom"),
        Emoji(char: "🛁", keywords: "wanna bath"),

        // Sport and play
        Emoji(char: "⚽", keywords: "pilka nozna football soccer"),
        Emoji(char: "🏀", keywords: "koszykowka basketball"),
        Emoji(char: "🎾", keywords: "tenis tennis"),
        Emoji(char: "🏐", keywords: "siatkowka volleyball"),
        Emoji(char: "🏓", keywords: "ping pong tenis stolowy"),
        Emoji(char: "🚴", keywords: "rower kolarstwo cycling"),
        Emoji(char: "🏊", keywords: "plywanie swim"),
        Emoji(char: "🏋️", keywords: "sila cwiczenia weight lifting"),
        Emoji(char: "♟️", keywords: "szachy chess"),
        Emoji(char: "🎲", keywords: "kostka gra dice"),
        Emoji(char: "🃏", keywords: "karty joker"),
        Emoji(char: "🕹️", keywords: "joystick gra game"),
    ]
}

// MARK: - EmojiTrigger

/// Recognising and replacing the `:` that opens the picker.
///
/// This lives in the core so the fiddly part — exactly which characters a picked emoji swallows —
/// is covered by the check suite rather than only by clicking around in the app. The trigger is a
/// colon that starts a line and still sits immediately behind the caret, so the characters typed
/// after it are already in the note and nothing has to be copied back and forth. A colon followed
/// by a space, or a colon in the middle of a sentence, is ordinary prose: that is what keeps `: `
/// writable in a note that talks about markdown.
public enum EmojiTrigger {

    /// The query a trailing `:` is holding, or nil when there is no trigger at the caret.
    public static func query(in raw: String, caret: Int) -> String? {
        guard let line = lineRange(in: raw, caret: caret), line.length >= 1 else { return nil }
        let ns = raw as NSString
        // The caret must be at the end of the line, otherwise the colon is being edited, not used.
        guard caret == line.location + line.length else { return nil }
        guard ns.substring(with: NSRange(location: line.location, length: 1)) == ":" else { return nil }
        let rest = ns.substring(with: NSRange(location: line.location + 1, length: line.length - 1))
        guard !rest.hasPrefix(":"), !rest.hasPrefix(" ") else { return nil }
        return rest
    }

    /// The range a picked emoji replaces: the colon plus the query typed after it.
    public static func range(in raw: String, caret: Int) -> NSRange? {
        guard query(in: raw, caret: caret) != nil, let line = lineRange(in: raw, caret: caret) else { return nil }
        return NSRange(location: line.location, length: caret - line.location)
    }

    /// The note with the trigger replaced, and the caret that belongs just behind the emoji.
    public static func insert(_ emoji: String, in raw: String, caret: Int) -> (raw: String, caret: Int)? {
        guard let range = range(in: raw, caret: caret) else { return nil }
        let updated = (raw as NSString).replacingCharacters(in: range, with: emoji)
        return (updated, range.location + (emoji as NSString).length)
    }

    /// The caret's line without its trailing newline, or nil when the caret is out of bounds.
    private static func lineRange(in raw: String, caret: Int) -> NSRange? {
        let ns = raw as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        var range = ns.lineRange(for: NSRange(location: caret, length: 0))
        while range.length > 0 {
            let index = range.location + range.length - 1
            let last = ns.substring(with: NSRange(location: index, length: 1))
            if last == "\n" || last == "\r" { range.length -= 1 } else { break }
        }
        return range
    }
}
