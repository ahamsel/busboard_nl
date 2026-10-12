/// Where a trip is heading, for short labels like "10 → Downtown".
///
/// Metrobus headsigns list the way a trip goes, ending at its destination
/// ("AVALON MALL - MUN CENTRE - DOWNTOWN"), so the last segment is kept.
/// "MUN-CNA-MI" separates single words with bare hyphens and is split too;
/// a hyphenated place name ("PORTUGAL COVE-ST. PHILIP'S") is left whole.
/// All-caps text is title-cased; mixed-case text is kept as written.
String headsignDestination(String headsign) {
  final trimmed = headsign.trim();
  if (trimmed.isEmpty) return '';
  var parts = trimmed.split(' - ');
  if (parts.length == 1) {
    final words = trimmed.split('-');
    if (words.length > 1 && words.every((w) => w.isNotEmpty && !w.contains(' '))) parts = words;
  }
  final destination = parts.last.trim();
  return destination == destination.toUpperCase() ? _titleCase(destination) : destination;
}

const _acronyms = {'MUN', 'CNA', 'MI', 'HSC'};
const _smallWords = {'to', 'via', 'and', 'of'};

String _titleCase(String text) {
  final words = text.split(' ');
  return [
    for (var i = 0; i < words.length; i++) _titleWord(words[i], first: i == 0),
  ].join(' ');
}

String _titleWord(String word, {required bool first}) {
  if (_acronyms.contains(word)) return word;
  final lower = word.toLowerCase();
  if (!first && _smallWords.contains(lower)) return lower;
  // Capitalise the start of each hyphen part: "COVE-ST." -> "Cove-St.".
  return lower.split('-').map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join('-');
}
