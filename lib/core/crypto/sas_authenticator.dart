import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_pkg;

/// Represents a single curated emoji entry with glyph and descriptive name.
class SasEmoji {
  final int index;
  final String emoji;
  final String name;

  const SasEmoji(this.index, this.emoji, this.name);

  @override
  String toString() => '$emoji ($name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SasEmoji &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          emoji == other.emoji;

  @override
  int get hashCode => index.hashCode ^ emoji.hashCode;
}

/// SAS verification code bundle containing 6-digit numeric string and 4-emoji visual tuple.
class SasCode {
  /// Formatted 6-digit decimal code e.g. "482-913".
  final String numericCode;

  /// Raw numeric integer value (0..999,999).
  final int numericValue;

  /// 4-emoji visual tuple with rich glyph & descriptive name.
  final List<SasEmoji> emojis;

  /// Raw 4 bytes derived from HKDF expansion.
  final Uint8List rawBytes;

  /// SHA-256 transcript hash (32 bytes).
  final Uint8List transcriptHash;

  const SasCode({
    required this.numericCode,
    required this.numericValue,
    required this.emojis,
    required this.rawBytes,
    required this.transcriptHash,
  });

  /// List of raw emoji glyph strings e.g. ["🦊", "⚡", "🪐", "💎"].
  List<String> get emojiGlyphList => emojis.map((e) => e.emoji).toList();

  /// Space-separated glyph string: "🦊 ⚡ 🪐 💎".
  String get emojiGlyphs => emojis.map((e) => e.emoji).join(' ');

  /// Descriptive accessible string: "🦊 (Fox), ⚡ (Lightning), 🪐 (Saturn), 💎 (Gem Stone)".
  String get emojiTextDescription => emojis.map((e) => e.toString()).join(', ');

  /// Verifies equality against another SasCode using constant-time comparison.
  bool matches(SasCode other) {
    if (rawBytes.length != other.rawBytes.length) return false;
    int diff = 0;
    for (int i = 0; i < rawBytes.length; i++) {
      diff |= rawBytes[i] ^ other.rawBytes[i];
    }
    return diff == 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SasCode &&
          runtimeType == other.runtimeType &&
          numericCode == other.numericCode &&
          matches(other);

  @override
  int get hashCode => numericCode.hashCode ^ rawBytes.fold<int>(0, (prev, elem) => prev ^ elem);

  @override
  String toString() => '$numericCode [$emojiGlyphs]';
}

/// Short Authentication String (SAS) generator and validator.
class SasAuthenticator {
  static const String sasHkdfInfo = 'SLFT-SAS-v1';

  /// Complete curated 256-word dictionary of distinct, high-clarity emojis.
  static const List<SasEmoji> emojiDictionary = [
    // 0..15: Mammals (Small/Medium)
    SasEmoji(0, '🦊', 'Fox'),
    SasEmoji(1, '🐺', 'Wolf'),
    SasEmoji(2, '🦁', 'Lion'),
    SasEmoji(3, '🐯', 'Tiger'),
    SasEmoji(4, '🐻', 'Bear'),
    SasEmoji(5, '🐼', 'Panda'),
    SasEmoji(6, '🐨', 'Koala'),
    SasEmoji(7, '🐵', 'Monkey'),
    SasEmoji(8, '🦍', 'Gorilla'),
    SasEmoji(9, '🐶', 'Dog'),
    SasEmoji(10, '🐱', 'Cat'),
    SasEmoji(11, '🐰', 'Rabbit'),
    SasEmoji(12, '🐭', 'Mouse'),
    SasEmoji(13, '🐹', 'Hamster'),
    SasEmoji(14, '🦔', 'Hedgehog'),
    SasEmoji(15, '🐿️', 'Squirrel'),

    // 16..31: Mammals (Large/Aquatic)
    SasEmoji(16, '🐘', 'Elephant'),
    SasEmoji(17, '🦒', 'Giraffe'),
    SasEmoji(18, '🦓', 'Zebra'),
    SasEmoji(19, '🐴', 'Horse'),
    SasEmoji(20, '🦌', 'Deer'),
    SasEmoji(21, '🐫', 'Camel'),
    SasEmoji(22, '🦘', 'Kangaroo'),
    SasEmoji(23, '🦏', 'Rhino'),
    SasEmoji(24, '🦛', 'Hippo'),
    SasEmoji(25, '🐳', 'Whale'),
    SasEmoji(26, '🐬', 'Dolphin'),
    SasEmoji(27, '🐙', 'Octopus'),
    SasEmoji(28, '🦈', 'Shark'),
    SasEmoji(29, '🦭', 'Seal'),
    SasEmoji(30, '🦦', 'Otter'),
    SasEmoji(31, '🦫', 'Beaver'),

    // 32..47: Birds & Reptiles
    SasEmoji(32, '🦅', 'Eagle'),
    SasEmoji(33, '🦉', 'Owl'),
    SasEmoji(34, '🐧', 'Penguin'),
    SasEmoji(35, '🦩', 'Flamingo'),
    SasEmoji(36, '🦚', 'Peacock'),
    SasEmoji(37, '🦜', 'Parrot'),
    SasEmoji(38, '🦢', 'Swan'),
    SasEmoji(39, '🦆', 'Duck'),
    SasEmoji(40, '🐢', 'Turtle'),
    SasEmoji(41, '🐸', 'Frog'),
    SasEmoji(42, '🐊', 'Crocodile'),
    SasEmoji(43, '🐍', 'Snake'),
    SasEmoji(44, '🦎', 'Lizard'),
    SasEmoji(45, '🦖', 'Dinosaur'),
    SasEmoji(46, '🦕', 'Sauropod'),
    SasEmoji(47, '🐉', 'Dragon'),

    // 48..63: Insects & Marine Life
    SasEmoji(48, '🦋', 'Butterfly'),
    SasEmoji(49, '🐝', 'Honeybee'),
    SasEmoji(50, '🐜', 'Ant'),
    SasEmoji(51, '🐞', 'Ladybug'),
    SasEmoji(52, '🦗', 'Cricket'),
    SasEmoji(53, '🕷️', 'Spider'),
    SasEmoji(54, '🦂', 'Scorpion'),
    SasEmoji(55, '🐌', 'Snail'),
    SasEmoji(56, '🦀', 'Crab'),
    SasEmoji(57, '🦞', 'Lobster'),
    SasEmoji(58, '🦐', 'Shrimp'),
    SasEmoji(59, '🦑', 'Squid'),
    SasEmoji(60, '🦇', 'Bat'),
    SasEmoji(61, '🦡', 'Badger'),
    SasEmoji(62, '🦃', 'Turkey'),
    SasEmoji(63, '🐓', 'Rooster'),

    // 64..79: Celestial & Sky
    SasEmoji(64, '☀️', 'Sun'),
    SasEmoji(65, '🌙', 'Crescent Moon'),
    SasEmoji(66, '⭐', 'Star'),
    SasEmoji(67, '🌟', 'Glowing Star'),
    SasEmoji(68, '🌠', 'Shooting Star'),
    SasEmoji(69, '🪐', 'Saturn'),
    SasEmoji(70, '🌍', 'Earth'),
    SasEmoji(71, '☄️', 'Comet'),
    SasEmoji(72, '☁️', 'Cloud'),
    SasEmoji(73, '⚡', 'Lightning'),
    SasEmoji(74, '🌈', 'Rainbow'),
    SasEmoji(75, '❄️', 'Snowflake'),
    SasEmoji(76, '🔥', 'Fire'),
    SasEmoji(77, '🌊', 'Ocean Wave'),
    SasEmoji(78, '🌪️', 'Tornado'),
    SasEmoji(79, '🌋', 'Volcano'),

    // 80..95: Nature & Plants
    SasEmoji(80, '🏔️', 'Snow Mountain'),
    SasEmoji(81, '🏝️', 'Desert Island'),
    SasEmoji(82, '🌲', 'Evergreen Tree'),
    SasEmoji(83, '🌳', 'Deciduous Tree'),
    SasEmoji(84, '🌴', 'Palm Tree'),
    SasEmoji(85, '🌵', 'Cactus'),
    SasEmoji(86, '🌾', 'Sheaf of Rice'),
    SasEmoji(87, '🌿', 'Herb'),
    SasEmoji(88, '🍀', 'Four Leaf Clover'),
    SasEmoji(89, '🍁', 'Maple Leaf'),
    SasEmoji(90, '🍂', 'Fallen Leaf'),
    SasEmoji(91, '🍄', 'Mushroom'),
    SasEmoji(92, '🌷', 'Tulip'),
    SasEmoji(93, '🌹', 'Rose'),
    SasEmoji(94, '🌻', 'Sunflower'),
    SasEmoji(95, '🌺', 'Hibiscus'),

    // 96..111: Fruits & Berries
    SasEmoji(96, '🍎', 'Red Apple'),
    SasEmoji(97, '🍏', 'Green Apple'),
    SasEmoji(98, '🍐', 'Pear'),
    SasEmoji(99, '🍊', 'Tangerine'),
    SasEmoji(100, '🍋', 'Lemon'),
    SasEmoji(101, '🍌', 'Banana'),
    SasEmoji(102, '🍉', 'Watermelon'),
    SasEmoji(103, '🍇', 'Grapes'),
    SasEmoji(104, '🍓', 'Strawberry'),
    SasEmoji(105, '🫐', 'Blueberries'),
    SasEmoji(106, '🍒', 'Cherries'),
    SasEmoji(107, '🍑', 'Peach'),
    SasEmoji(108, '🍍', 'Pineapple'),
    SasEmoji(109, '🥥', 'Coconut'),
    SasEmoji(110, '🥝', 'Kiwi'),
    SasEmoji(111, '🥑', 'Avocado'),

    // 112..127: Vegetables & Staples
    SasEmoji(112, '🥦', 'Broccoli'),
    SasEmoji(113, '🌽', 'Ear of Corn'),
    SasEmoji(114, '🥕', 'Carrot'),
    SasEmoji(115, '🧄', 'Garlic'),
    SasEmoji(116, '🧅', 'Onion'),
    SasEmoji(117, '🥔', 'Potato'),
    SasEmoji(118, '🍞', 'Bread'),
    SasEmoji(119, '🥐', 'Croissant'),
    SasEmoji(120, '🥨', 'Pretzel'),
    SasEmoji(121, '🥯', 'Bagel'),
    SasEmoji(122, '🥞', 'Pancakes'),
    SasEmoji(123, '🧇', 'Waffle'),
    SasEmoji(124, '🧀', 'Cheese Wedge'),
    SasEmoji(125, '🍳', 'Fried Egg'),
    SasEmoji(126, '🥓', 'Bacon'),
    SasEmoji(127, '🥩', 'Cut of Meat'),

    // 128..143: Meals & Fast Food
    SasEmoji(128, '🍔', 'Hamburger'),
    SasEmoji(129, '🍟', 'French Fries'),
    SasEmoji(130, '🍕', 'Pizza'),
    SasEmoji(131, '🌭', 'Hot Dog'),
    SasEmoji(132, '🥪', 'Sandwich'),
    SasEmoji(133, '🌮', 'Taco'),
    SasEmoji(134, '🌯', 'Burrito'),
    SasEmoji(135, '🥙', 'Stuffed Flatbread'),
    SasEmoji(136, '🍿', 'Popcorn'),
    SasEmoji(137, '🍣', 'Sushi'),
    SasEmoji(138, '🥟', 'Dumpling'),
    SasEmoji(139, '🍜', 'Steaming Bowl'),
    SasEmoji(140, '🍝', 'Spaghetti'),
    SasEmoji(141, '🍲', 'Pot of Food'),
    SasEmoji(142, '🍛', 'Curry Rice'),
    SasEmoji(143, '🍱', 'Bento Box'),

    // 144..159: Sweets & Drinks
    SasEmoji(144, '🍦', 'Soft Ice Cream'),
    SasEmoji(145, '🍧', 'Shaved Ice'),
    SasEmoji(146, '🍨', 'Ice Cream Bowl'),
    SasEmoji(147, '🍩', 'Doughnut'),
    SasEmoji(148, '🍪', 'Cookie'),
    SasEmoji(149, '🎂', 'Birthday Cake'),
    SasEmoji(150, '🍰', 'Shortcake'),
    SasEmoji(151, '🧁', 'Cupcake'),
    SasEmoji(152, '🥧', 'Pie'),
    SasEmoji(153, '🍫', 'Chocolate Bar'),
    SasEmoji(154, '🍬', 'Candy'),
    SasEmoji(155, '🍭', 'Lollipop'),
    SasEmoji(156, '🍮', 'Custard'),
    SasEmoji(157, '🍯', 'Honey Pot'),
    SasEmoji(158, '☕', 'Hot Beverage'),
    SasEmoji(159, '🧃', 'Juice Box'),

    // 160..175: Transport & Vehicles
    SasEmoji(160, '🚀', 'Rocket'),
    SasEmoji(161, '🛰️', 'Satellite'),
    SasEmoji(162, '🛸', 'Flying Saucer'),
    SasEmoji(163, '🚁', 'Helicopter'),
    SasEmoji(164, '✈️', 'Airplane'),
    SasEmoji(165, '⛵', 'Sailboat'),
    SasEmoji(166, '🚤', 'Speedboat'),
    SasEmoji(167, '🚢', 'Ship'),
    SasEmoji(168, '⚓', 'Anchor'),
    SasEmoji(169, '🚗', 'Automobile'),
    SasEmoji(170, '🚕', 'Taxi'),
    SasEmoji(171, '🚌', 'Bus'),
    SasEmoji(172, '🚓', 'Police Car'),
    SasEmoji(173, '🚑', 'Ambulance'),
    SasEmoji(174, '🚒', 'Fire Engine'),
    SasEmoji(175, '🚜', 'Tractor'),

    // 176..191: Rail, Cycles & Transit
    SasEmoji(176, '🚲', 'Bicycle'),
    SasEmoji(177, '🛴', 'Kick Scooter'),
    SasEmoji(178, '🛹', 'Skateboard'),
    SasEmoji(179, '🛼', 'Roller Skate'),
    SasEmoji(180, '🚂', 'Locomotive'),
    SasEmoji(181, '🚆', 'Train'),
    SasEmoji(182, '🚇', 'Metro'),
    SasEmoji(183, '🚊', 'Tram'),
    SasEmoji(184, '🛶', 'Canoe'),
    SasEmoji(185, '🪂', 'Parachute'),
    SasEmoji(186, '🚡', 'Aerial Tramway'),
    SasEmoji(187, '🛵', 'Motor Scooter'),
    SasEmoji(188, '🏍️', 'Motorcycle'),
    SasEmoji(189, '🚨', 'Police Light'),
    SasEmoji(190, '🚥', 'Traffic Light'),
    SasEmoji(191, '⛽', 'Fuel Pump'),

    // 192..207: Tools & Hardware
    SasEmoji(192, '🔨', 'Hammer'),
    SasEmoji(193, '🪓', 'Axe'),
    SasEmoji(194, '⛏️', 'Pickaxe'),
    SasEmoji(195, '🔧', 'Wrench'),
    SasEmoji(196, '🪛', 'Screwdriver'),
    SasEmoji(197, '🔩', 'Nut and Bolt'),
    SasEmoji(198, '⚙️', 'Gear'),
    SasEmoji(199, '🧰', 'Toolbox'),
    SasEmoji(200, '🪜', 'Ladder'),
    SasEmoji(201, '🧲', 'Magnet'),
    SasEmoji(202, '💡', 'Light Bulb'),
    SasEmoji(203, '🔦', 'Flashlight'),
    SasEmoji(204, '🔋', 'Battery'),
    SasEmoji(205, '🔌', 'Electric Plug'),
    SasEmoji(206, '🧭', 'Compass'),
    SasEmoji(207, '⌛', 'Hourglass'),

    // 208..223: Science, Security & Valuables
    SasEmoji(208, '🔭', 'Telescope'),
    SasEmoji(209, '🔬', 'Microscope'),
    SasEmoji(210, '🧪', 'Test Tube'),
    SasEmoji(211, '🧬', 'DNA'),
    SasEmoji(212, '🔑', 'Key'),
    SasEmoji(213, '🔒', 'Locked Padlock'),
    SasEmoji(214, '🔓', 'Unlocked Padlock'),
    SasEmoji(215, '🛡️', 'Shield'),
    SasEmoji(216, '⚔️', 'Crossed Swords'),
    SasEmoji(217, '🏹', 'Bow and Arrow'),
    SasEmoji(218, '🎯', 'Bullseye'),
    SasEmoji(219, '👑', 'Crown'),
    SasEmoji(220, '💍', 'Ring'),
    SasEmoji(221, '💎', 'Gem Stone'),
    SasEmoji(222, '🏆', 'Trophy'),
    SasEmoji(223, '🥇', '1st Place Medal'),

    // 224..239: Arts, Music & Comm
    SasEmoji(224, '🪄', 'Magic Wand'),
    SasEmoji(225, '🎨', 'Artist Palette'),
    SasEmoji(226, '🧵', 'Thread'),
    SasEmoji(227, '🧶', 'Yarn'),
    SasEmoji(228, '📷', 'Camera'),
    SasEmoji(229, '🎸', 'Guitar'),
    SasEmoji(230, '🎻', 'Violin'),
    SasEmoji(231, '🥁', 'Drum'),
    SasEmoji(232, '🎺', 'Trumpet'),
    SasEmoji(233, '🎹', 'Musical Keyboard'),
    SasEmoji(234, '🔔', 'Bell'),
    SasEmoji(235, '📣', 'Megaphone'),
    SasEmoji(236, '📖', 'Open Book'),
    SasEmoji(237, '📜', 'Scroll'),
    SasEmoji(238, '✉️', 'Envelope'),
    SasEmoji(239, '📦', 'Package'),

    // 240..255: Sports, Games, Toys & Celebration
    SasEmoji(240, '🔮', 'Crystal Ball'),
    SasEmoji(241, '🎲', 'Game Die'),
    SasEmoji(242, '♟️', 'Chess Pawn'),
    SasEmoji(243, '🧩', 'Puzzle Piece'),
    SasEmoji(244, '🪁', 'Kite'),
    SasEmoji(245, '🎈', 'Balloon'),
    SasEmoji(246, '🎉', 'Party Popper'),
    SasEmoji(247, '🪅', 'Pinata'),
    SasEmoji(248, '🎀', 'Ribbon'),
    SasEmoji(249, '🎁', 'Wrapped Gift'),
    SasEmoji(250, '⚽', 'Soccer Ball'),
    SasEmoji(251, '🏀', 'Basketball'),
    SasEmoji(252, '🏈', 'American Football'),
    SasEmoji(253, '🎾', 'Tennis'),
    SasEmoji(254, '🎳', 'Bowling'),
    SasEmoji(255, '❤️', 'Red Heart'),
  ];

  /// Computes the 32-byte SHA-256 transcript hash over:
  /// pk_A (32B) || pk_B (32B) || N_A (32B) || N_B (32B) || Z (32B).
  static Uint8List computeTranscriptHash({
    required Uint8List initiatorPublicKey,
    required Uint8List receiverPublicKey,
    required Uint8List initiatorNonce,
    required Uint8List receiverNonce,
    required Uint8List sharedSecret,
  }) {
    if (initiatorPublicKey.length != 32) {
      throw ArgumentError('initiatorPublicKey must be 32 bytes');
    }
    if (receiverPublicKey.length != 32) {
      throw ArgumentError('receiverPublicKey must be 32 bytes');
    }
    if (initiatorNonce.length != 32) {
      throw ArgumentError('initiatorNonce must be 32 bytes');
    }
    if (receiverNonce.length != 32) {
      throw ArgumentError('receiverNonce must be 32 bytes');
    }
    if (sharedSecret.length != 32) {
      throw ArgumentError('sharedSecret must be 32 bytes');
    }

    final transcript = Uint8List(160);
    transcript.setRange(0, 32, initiatorPublicKey);
    transcript.setRange(32, 64, receiverPublicKey);
    transcript.setRange(64, 96, initiatorNonce);
    transcript.setRange(96, 128, receiverNonce);
    transcript.setRange(128, 160, sharedSecret);

    final digest = crypto_pkg.sha256.convert(transcript);
    return Uint8List.fromList(digest.bytes);
  }

  /// Generates the complete [SasCode] from a 32-byte [transcriptHash].
  static SasCode generateSas(Uint8List transcriptHash) {
    if (transcriptHash.length != 32) {
      throw ArgumentError('transcriptHash must be 32 bytes');
    }

    // HMAC-SHA256 based HKDF-Expand with info "SLFT-SAS-v1" for 4 bytes output
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, transcriptHash);
    final infoBytes = utf8.encode(sasHkdfInfo);
    final hmacInput = Uint8List(infoBytes.length + 1);
    hmacInput.setRange(0, infoBytes.length, infoBytes);
    hmacInput[infoBytes.length] = 0x01; // HKDF counter byte 1

    final t1 = hmac.convert(hmacInput).bytes;
    final sasBytes = Uint8List.fromList(t1.sublist(0, 4));

    return generateSasFromBytes(sasBytes, transcriptHash);
  }

  /// Alias for generateSas.
  static SasCode computeSas(Uint8List transcriptHash) => generateSas(transcriptHash);

  /// Alias for generateSas.
  static SasCode compute(Uint8List transcriptHash) => generateSas(transcriptHash);

  /// Constructs a [SasCode] from an exact 4-byte derivation slice.
  static SasCode generateSasFromBytes(Uint8List fourBytes, Uint8List transcriptHash) {
    if (fourBytes.length != 4) {
      throw ArgumentError('fourBytes must be exactly 4 bytes');
    }

    // 1. Numeric Code: (rawUint32 % 1,000,000) -> "XXX-XXX"
    final byteData = ByteData.sublistView(fourBytes);
    final rawUint32 = byteData.getUint32(0, Endian.big);
    final numericValue = rawUint32 % 1000000;
    final padded6 = numericValue.toString().padLeft(6, '0');
    final formattedNumeric = '${padded6.substring(0, 3)}-${padded6.substring(3, 6)}';

    // 2. Visual Emoji Tuple
    final selectedEmojis = <SasEmoji>[
      emojiDictionary[fourBytes[0]],
      emojiDictionary[fourBytes[1]],
      emojiDictionary[fourBytes[2]],
      emojiDictionary[fourBytes[3]],
    ];

    return SasCode(
      numericCode: formattedNumeric,
      numericValue: numericValue,
      emojis: List.unmodifiable(selectedEmojis),
      rawBytes: Uint8List.fromList(fourBytes),
      transcriptHash: Uint8List.fromList(transcriptHash),
    );
  }

  /// Constant-time string equality check.
  static bool constantTimeEquals(String a, String b) {
    final aUnits = utf8.encode(a);
    final bUnits = utf8.encode(b);
    if (aUnits.length != bUnits.length) return false;
    int result = 0;
    for (int i = 0; i < aUnits.length; i++) {
      result |= aUnits[i] ^ bUnits[i];
    }
    return result == 0;
  }
}
