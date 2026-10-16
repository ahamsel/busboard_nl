/// Where a trip is heading, for short labels like "10 → Downtown".
///
/// Metrobus headsigns list the way a trip goes, ending at its destination
/// ("AVALON MALL - MUN CENTRE - DOWNTOWN"), so the last segment is kept.
/// "MUN-CNA-MI" separates single words with bare hyphens and is split too;
/// a hyphenated place name ("PORTUGAL COVE-ST. PHILIP'S") is left whole.
/// All-caps text is made readable by [readableHeadsign]; mixed-case text is kept as written.
String headsignDestination(String headsign) {
  final trimmed = headsign.trim();
  if (trimmed.isEmpty) return '';
  var parts = trimmed.split(' - ');
  if (parts.length == 1) {
    final words = trimmed.split('-');
    if (words.length > 1 && words.every((w) => w.isNotEmpty && !w.contains(' '))) parts = words;
  }
  return readableHeadsign(parts.last.trim());
}

/// A trip name as riders read it: the feed's all-caps headsigns ("AVALON MALL - MUN CENTRE - DOWNTOWN") in title
/// case ("Avalon Mall - MUN Centre - Downtown"). Acronyms stay in capitals: the known ones ([_acronyms]) and any other
/// word of 2 to 4 letters with no vowel (A, E, I, O, U or Y: "CBS", "NLCC"), except the street words ("St", "Dr",
/// "Rd"). Small words ("to", "via") are lower case inside a part. Text with any lower-case letter is left as written.
/// For display and screen readers only: matching uses the feed's own text.
String readableHeadsign(String headsign) {
  if (headsign != headsign.toUpperCase() || !headsign.contains(_letter)) return headsign;
  return headsign.split(' - ').map(_titlePart).join(' - ');
}

final _letter = RegExp('[A-Z]');
final _notLetter = RegExp('[^A-Z]');
final _digit = RegExp('[0-9]');
final _vowel = RegExp('[AEIOUY]');

/// Acronyms kept in capitals although they may have a vowel.
const _acronyms = {'MUN', 'HSC', 'CNA', 'NL', 'YYT', 'DFO', 'MI'};

/// Vowel-less street words, read as words: "Water St", "Kelsey Dr", "Mount Scio Rd".
const _streetWords = {'ST', 'DR', 'RD', 'PL', 'CT', 'CRT', 'BLVD'};
const _smallWords = {'to', 'via', 'and', 'of', 'the', 'at', 'on'};

/// One " - " part of a headsign: its first word is capitalised whatever it is.
String _titlePart(String part) {
  final words = part.split(' ');
  final firstWord = words.indexWhere((w) => w.isNotEmpty);
  return [
    for (var i = 0; i < words.length; i++) words[i].isEmpty ? '' : _titleWord(words[i], first: i == firstWord),
  ].join(' ');
}

String _titleWord(String word, {required bool first}) {
  final core = word.replaceAll(_notLetter, '');
  if (!first && !word.contains('-') && _smallWords.contains(core.toLowerCase())) return word.toLowerCase();
  // Each hyphen piece on its own: "COVE-ST." is "Cove-St.", "MUN-CNA-MI" stays as it is.
  return word.split('-').map(_titlePiece).join('-');
}

String _titlePiece(String piece) {
  final core = piece.replaceAll(_notLetter, '');
  if (core.isEmpty || piece.contains(_digit)) return piece;
  if (_streetWords.contains(core)) return _capitalised(piece);
  if (_acronyms.contains(core)) return piece;
  if (core.length >= 2 && core.length <= 4 && !core.contains(_vowel)) return piece;
  return _capitalised(piece);
}

/// [piece] in lower case with its first letter in capitals: "(AIRPORT)" is "(Airport)", "JOHN'S" is "John's".
String _capitalised(String piece) {
  final lower = piece.toLowerCase();
  final at = lower.indexOf(RegExp('[a-z]'));
  return at < 0 ? lower : lower.substring(0, at) + lower[at].toUpperCase() + lower.substring(at + 1);
}
