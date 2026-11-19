/// Small words that stay lowercase inside a title ("City of Ghosts",
/// "Into the Hive"), unless they open or close it.
const Set<String> _minorWords = {
  'a', 'an', 'and', 'at', 'in', 'of', 'on', 'the', 'to',
};

/// Display title case for level / sector names, which are stored in caps
/// (`CampaignCatalog`): "CITY OF GHOSTS" -> "City of Ghosts",
/// "QUEEN'S LAIR" -> "Queen's Lair". The first and last words are always
/// capitalised.
String titleCaseName(String s) {
  final words = s.trim().toLowerCase().split(RegExp(r'\s+'));
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final edge = i == 0 || i == words.length - 1;
    if (w.isEmpty || (!edge && _minorWords.contains(w))) {
      out.add(w);
    } else {
      out.add(w[0].toUpperCase() + w.substring(1));
    }
  }
  return out.join(' ');
}
