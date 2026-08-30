import 'dart:isolate';

class WalletSearchDocument {
  const WalletSearchDocument({
    required this.id,
    required this.sortValue,
    required this.searchableText,
    required this.exactValues,
  });

  final String id;
  final String sortValue;
  final String searchableText;
  final List<String> exactValues;
}

/// One immutable search result shared by all vault panes.
class WalletSearchResult {
  const WalletSearchResult({
    required this.query,
    required this.exact,
    required this.revision,
    required this.folderPaths,
    required this.cardIds,
  });

  const WalletSearchResult.empty()
      : query = '',
        exact = false,
        revision = -1,
        folderPaths = const [],
        cardIds = const [];

  final String query;
  final bool exact;
  final int revision;
  final List<String> folderPaths;
  final List<String> cardIds;

  int get count => folderPaths.length + cardIds.length;
}

/// Builds a normalized index once per data revision and caches queries.
class WalletSearchController {
  WalletSearchController({
    this.isolateThreshold = 2000,
    this.maxCachedQueries = 64,
  }) : assert(maxCachedQueries > 0);

  final int isolateThreshold;
  final int maxCachedQueries;
  int _revision = -1;
  List<_IndexedSearchDocument> _folders = const [];
  List<_IndexedSearchDocument> _cards = const [];
  Map<String, Object?> _isolatePayload = const {};
  final Map<_SearchCacheKey, WalletSearchResult> _cache = {};

  int get revision => _revision;
  int get cachedQueryCount => _cache.length;

  void replaceIndex({
    required int revision,
    required Iterable<WalletSearchDocument> folders,
    required Iterable<WalletSearchDocument> cards,
  }) {
    _revision = revision;
    _folders = folders.map(_IndexedSearchDocument.fromDocument).toList();
    _cards = cards.map(_IndexedSearchDocument.fromDocument).toList();
    _isolatePayload = {
      'folders': _folders.map((entry) => entry.toMessage()).toList(),
      'cards': _cards.map((entry) => entry.toMessage()).toList(),
    };
    _cache.clear();
  }

  Future<WalletSearchResult> search(String value, {bool exact = false}) async {
    final query = value.trim();
    if (query.isEmpty) {
      return WalletSearchResult(
        query: '',
        exact: exact,
        revision: _revision,
        folderPaths: const [],
        cardIds: const [],
      );
    }
    final revision = _revision;
    final isolatePayload = _isolatePayload;
    final key = _SearchCacheKey(revision, query, exact);
    final cached = _cache[key];
    if (cached != null) return cached;

    final queryData = _PreparedQuery(query, exact: exact);
    final ({List<String> folders, List<String> cards}) matches;
    if (_folders.length + _cards.length >= isolateThreshold) {
      final response = await Isolate.run(
        () => _searchMessage({
          ...isolatePayload,
          'query': queryData.toMessage(),
        }),
      );
      matches = (
        folders: List<String>.from(response['folders']! as List),
        cards: List<String>.from(response['cards']! as List),
      );
    } else {
      matches = (
        folders: _searchDocuments(_folders, queryData),
        cards: _searchDocuments(_cards, queryData),
      );
    }

    final result = WalletSearchResult(
      query: query,
      exact: exact,
      revision: revision,
      folderPaths: List.unmodifiable(matches.folders),
      cardIds: List.unmodifiable(matches.cards),
    );
    if (revision == _revision) {
      if (_cache.length >= maxCachedQueries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = result;
    }
    return result;
  }

  static bool matches(String text, String query) {
    if (query.trim().isEmpty) return false;
    final document = _IndexedSearchDocument.fromDocument(
      WalletSearchDocument(
        id: '',
        sortValue: '',
        searchableText: text,
        exactValues: [text],
      ),
    );
    return _matchesDocument(document, _PreparedQuery(query, exact: false));
  }
}

class _SearchCacheKey {
  const _SearchCacheKey(this.revision, this.query, this.exact);

  final int revision;
  final String query;
  final bool exact;

  @override
  bool operator ==(Object other) =>
      other is _SearchCacheKey &&
      other.revision == revision &&
      other.query == query &&
      other.exact == exact;

  @override
  int get hashCode => Object.hash(revision, query, exact);
}

class _PreparedQuery {
  _PreparedQuery(String value, {required this.exact})
      : normalized = value.trim().toLowerCase(),
        variants = exact ? const [] : _searchVariants(value).toList();

  _PreparedQuery.fromMessage(Map<Object?, Object?> message)
      : normalized = message['normalized']! as String,
        exact = message['exact']! as bool,
        variants = List<String>.from(message['variants']! as List);

  final String normalized;
  final bool exact;
  final List<String> variants;

  Map<String, Object?> toMessage() => {
        'normalized': normalized,
        'exact': exact,
        'variants': variants,
      };
}

class _IndexedSearchDocument {
  const _IndexedSearchDocument({
    required this.id,
    required this.sortValue,
    required this.exactValues,
    required this.variants,
    required this.wordsByVariant,
  });

  factory _IndexedSearchDocument.fromDocument(WalletSearchDocument document) {
    final variants = _searchVariants(document.searchableText).toList();
    return _IndexedSearchDocument(
      id: document.id,
      sortValue: document.sortValue.toLowerCase(),
      exactValues: document.exactValues
          .map((value) => value.trim().toLowerCase())
          .toList(growable: false),
      variants: variants,
      wordsByVariant: variants
          .map(_latinWords)
          .map((words) => words.toList(growable: false))
          .toList(growable: false),
    );
  }

  factory _IndexedSearchDocument.fromMessage(Map<Object?, Object?> message) {
    return _IndexedSearchDocument(
      id: message['id']! as String,
      sortValue: message['sortValue']! as String,
      exactValues: List<String>.from(message['exactValues']! as List),
      variants: List<String>.from(message['variants']! as List),
      wordsByVariant: (message['wordsByVariant']! as List)
          .map((words) => List<String>.from(words as List))
          .toList(growable: false),
    );
  }

  final String id;
  final String sortValue;
  final List<String> exactValues;
  final List<String> variants;
  final List<List<String>> wordsByVariant;

  Map<String, Object?> toMessage() => {
        'id': id,
        'sortValue': sortValue,
        'exactValues': exactValues,
        'variants': variants,
        'wordsByVariant': wordsByVariant,
      };
}

Map<String, Object?> _searchMessage(Map<String, Object?> message) {
  final query = _PreparedQuery.fromMessage(
    Map<Object?, Object?>.from(message['query']! as Map),
  );
  final folders = (message['folders']! as List)
      .map((entry) => _IndexedSearchDocument.fromMessage(
            Map<Object?, Object?>.from(entry as Map),
          ))
      .toList(growable: false);
  final cards = (message['cards']! as List)
      .map((entry) => _IndexedSearchDocument.fromMessage(
            Map<Object?, Object?>.from(entry as Map),
          ))
      .toList(growable: false);
  return {
    'folders': _searchDocuments(folders, query),
    'cards': _searchDocuments(cards, query),
  };
}

List<String> _searchDocuments(
  List<_IndexedSearchDocument> documents,
  _PreparedQuery query,
) {
  final matches = documents
      .where((document) => _matchesDocument(document, query))
      .toList(growable: false)
    ..sort((left, right) {
      final byName = left.sortValue.compareTo(right.sortValue);
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
  return matches.map((entry) => entry.id).toList(growable: false);
}

bool _matchesDocument(_IndexedSearchDocument document, _PreparedQuery query) {
  if (query.exact) return document.exactValues.contains(query.normalized);
  for (final queryVariant in query.variants) {
    if (document.variants.any((text) => text.contains(queryVariant))) {
      return true;
    }
    final queryWords = _latinWords(queryVariant)
        .where((word) => word.length >= 4)
        .toList(growable: false);
    if (queryWords.isEmpty) continue;
    for (final textWords in document.wordsByVariant) {
      if (queryWords.every((queryWord) {
        final tolerance = queryWord.length >= 8 ? 2 : 1;
        return textWords.any(
          (textWord) =>
              (textWord.length - queryWord.length).abs() <= tolerance &&
              _editDistance(textWord, queryWord) <= tolerance,
        );
      })) {
        return true;
      }
    }
  }
  return false;
}

const _englishKeyboard = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
const _russianKeyboard = 'ёйцукенгшщзхъфывапролджэячсмитьбю';

String _swapKeyboardLayout(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final englishIndex = _englishKeyboard.indexOf(character);
    if (englishIndex >= 0) {
      buffer.write(_russianKeyboard[englishIndex]);
      continue;
    }
    final russianIndex = _russianKeyboard.indexOf(character);
    buffer
        .write(russianIndex >= 0 ? _englishKeyboard[russianIndex] : character);
  }
  return buffer.toString();
}

String _transliterate(String value) {
  const replacements = <String, String>{
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'e',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'h',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'sch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(replacements[character] ?? character);
  }
  return buffer.toString();
}

Set<String> _searchVariants(String value) {
  final normalized = value.toLowerCase().trim();
  final swapped = _swapKeyboardLayout(normalized);
  return {
    normalized,
    swapped,
    _transliterate(normalized),
    _transliterate(swapped),
  }..removeWhere((entry) => entry.isEmpty);
}

Iterable<String> _latinWords(String value) => _transliterate(value)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty);

int _editDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = <int>[leftIndex + 1];
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitution =
          previous[rightIndex] + (left[leftIndex] == right[rightIndex] ? 0 : 1);
      final deletion = current[rightIndex] + 1;
      final insertion = previous[rightIndex + 1] + 1;
      var minimum = deletion < insertion ? deletion : insertion;
      if (substitution < minimum) minimum = substitution;
      current.add(minimum);
    }
    previous = current;
  }
  return previous.last;
}
