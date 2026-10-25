import '../../core/models/track.dart';

/// Centralized service for artist unification, collaboration indexing, and catalogue mapping.
///
/// Ensures artists are unified into canonical individual profiles:
/// - "Drake feat. 21 Savage" -> ["Drake", "21 Savage"]
/// - "Drake & Future" -> ["Drake", "Future"]
/// - "Kanye West, Lil Wayne & Eminem" -> ["Kanye West", "Lil Wayne", "Eminem"]
/// - Title: "Jimmy Cooks (feat. 21 Savage)" -> ["21 Savage"]
///
/// Features and collaborations appear across the catalogues of all participating artists.
class ArtistHelper {
  // Regex to detect featuring/collaboration in title or parenthesis/brackets
  // Examples: (feat. 21 Savage), [ft. Rihanna], (featuring Travis Scott), (with Daft Punk)
  static final RegExp _titleFeatRegex = RegExp(
    r'[\(\[](?:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]',
    caseSensitive: false,
  );

  // Common collaboration delimiters in artist strings:
  // - Commas: ,
  // - Semicolons: ;
  // - Slashes with spaces or double slashes: ' / ', ' // '
  // - Ampersand: ' & ' or '&'
  // - ' feat. ', ' ft. ', ' featuring ', ' with '
  // - ' x ' or ' X ' (standalone)
  // - ' and ' (standalone)
  static final RegExp _artistSplitRegex = RegExp(
    r'(?:\s*[,;]\s*|\s+(?:&|and|with|feat\.?|ft\.?|featuring|x|X|\+)\s+|\s+&\s*|\s*\/\/\s*|\s+\/\s+)',
    caseSensitive: false,
  );

  // Well-known bands with 'and', '&', or '+' in their official canonical name that should not be split
  static const Set<String> _knownEnsembles = {
    'florence + the machine',
    'florence and the machine',
    'of monsters and men',
    'simon & garfunkel',
    'simon and garfunkel',
    'earth, wind & fire',
    'earth wind & fire',
    'kool & the gang',
    'kool and the gang',
    'crosby, stills, nash & young',
    'crosby stills nash & young',
    'tom petty and the heartbreakers',
    'hall & oates',
    'daryl hall & john oates',
    'huey lewis and the news',
    'the mamas & the papas',
    'kc and the sunshine band',
    'iron & wine',
    'echo & the bunnymen',
    'belle and sebastian',
  };

  /// Splits an artist credit string and optional track title into individual unified artist names.
  static List<String> extractArtists(String? rawArtist, [String? trackTitle]) {
    final results = <String>{};

    void process(String text) {
      final cleanText = text.trim();
      if (cleanText.isEmpty) return;

      // If it matches a known canonical ensemble, keep it intact
      if (_knownEnsembles.contains(cleanText.toLowerCase())) {
        results.add(cleanText);
        return;
      }

      final tokens = cleanText.split(_artistSplitRegex);
      for (var token in tokens) {
        token = token.trim();
        // Strip surrounding punctuation, quotes, parentheses, brackets
        token = token.replaceAll(RegExp(r'''^[.,;:"'\(\[\{\s]+|[.,;:"'\)\]\}\s]+$'''), '').trim();
        if (token.isEmpty) continue;

        final lower = token.toLowerCase();
        if (lower == 'unknown artist' ||
            lower == 'various artists' ||
            lower == 'various' ||
            lower == 'unknown') {
          continue;
        }
        results.add(token);
      }
    }

    if (rawArtist != null && rawArtist.trim().isNotEmpty) {
      process(rawArtist);
    }

    if (trackTitle != null && trackTitle.isNotEmpty) {
      final match = _titleFeatRegex.firstMatch(trackTitle);
      if (match != null && match.group(1) != null) {
        process(match.group(1)!);
      }
    }

    if (results.isEmpty && rawArtist != null && rawArtist.trim().isNotEmpty) {
      return [rawArtist.trim()];
    }

    return results.toList();
  }

  /// Determines whether [track] belongs to the specified [artistName]
  /// (as primary artist, collaborator, or featured artist).
  static bool trackBelongsToArtist(Track track, String artistName) {
    final cleanTarget = artistName.trim().toLowerCase();
    if (cleanTarget.isEmpty) return false;

    // 1. Direct match on primary artist
    final rawArtistLower = track.artist.trim().toLowerCase();
    if (rawArtistLower == cleanTarget) {
      return true;
    }

    // 2. Check extracted unified artists from artist credit and title
    final artists = extractArtists(track.artist, track.title);
    for (final a in artists) {
      if (a.toLowerCase() == cleanTarget) {
        return true;
      }
    }

    // 3. Fallback: match cleanTarget as a bounded token within raw artist
    final regex = RegExp(
      r'(?:^|[^\w])' + RegExp.escape(cleanTarget) + r'(?:[^\w]|$)',
      caseSensitive: false,
    );
    if (regex.hasMatch(rawArtistLower)) {
      return true;
    }

    // 4. Fallback: check featured artists in track title
    final titleLower = track.title.toLowerCase();
    if (titleLower.contains(cleanTarget)) {
      final match = _titleFeatRegex.firstMatch(track.title);
      if (match != null && match.group(1) != null) {
        final featText = match.group(1)!.toLowerCase();
        if (regex.hasMatch(featText) || featText.contains(cleanTarget)) {
          return true;
        }
      }
    }

    return false;
  }
}
