import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';

/// The paths one kind of read may take on a site: a fixed number of
/// segments, each a literal or a `{name}`, and the query options it may
/// or must carry.
///
/// Written as a path, such as `/drives/b!D/items/01F:/{name}:/content`.
/// A literal segment is compared decoded, as [PathPrefix] compares them,
/// so `01F%3A` is `01F:`. `{name}` is one segment naming one thing in the
/// place the literals before it lead to, never a way past it: not empty,
/// no `/`, `\` or `:` once decoded, and not only dots. It may end in a
/// fixed literal suffix, as `{name}:` does. There is no wildcard and no
/// "any depth", so a pattern reaches exactly the paths it spells.
final class PathPattern {
  const PathPattern._(this.path, this._segments, this.queryOptions);

  /// [path] as a pattern whose query carries each of [queryOptions] as its
  /// [QueryOptionRule] says, and nothing else; with none, it carries no
  /// query. Null when [path] isn't one: it must start with `/`, name at
  /// least two segments, so the prefix a read is granted under is never
  /// the whole site, and start with a literal.
  static PathPattern? parse(
    String path, {
    Map<QueryOptionName, QueryOptionRule> queryOptions = const {},
  }) {
    if (!path.startsWith('/')) return null;
    final segments = <_Segment>[];
    for (final raw in path.substring(1).split('/')) {
      final segment = _Segment.parse(raw);
      if (segment == null) return null;
      segments.add(segment);
    }
    if (segments.length < 2 || segments.first is _Name) return null;
    return PathPattern._(
      path,
      List.unmodifiable(segments),
      Map.unmodifiable(queryOptions),
    );
  }

  /// The pattern as it was written.
  final String path;
  final List<_Segment> _segments;
  final Map<QueryOptionName, QueryOptionRule> queryOptions;

  /// The prefix a read of [path] is granted under when this pattern
  /// matches it, or null when it doesn't: [path] with its last segment
  /// and query left off, so a redirect on the same site stays on this
  /// read.
  PathPrefix? prefixMatching(WebPath path) {
    final queryAt = path.value.indexOf('?');
    final raw = queryAt < 0 ? path.value : path.value.substring(0, queryAt);
    if (!_allowsQuery(queryAt < 0 ? null : path.value.substring(queryAt + 1))) {
      return null;
    }
    final rawSegments = raw.substring(1).split('/');
    if (rawSegments.length != _segments.length) return null;
    for (var i = 0; i < _segments.length; i++) {
      final decoded = _decoded(rawSegments[i]);
      if (decoded == null || !_segments[i].matches(decoded)) return null;
    }
    return PathPrefix.parse(
      '/${rawSegments.take(rawSegments.length - 1).join('/')}/',
    );
  }

  /// Whether [query], or no query when it is null, carries each option at
  /// most once, only options [queryOptions] names, each with words its rule
  /// allows, and every option a rule says it must carry.
  bool _allowsQuery(String? query) {
    final seen = <QueryOptionName>{};
    for (final pair in query?.split('&') ?? const <String>[]) {
      final equalsAt = pair.indexOf('=');
      if (equalsAt < 0) return false;
      final name = _decodedQuery(pair.substring(0, equalsAt));
      final value = _decodedQuery(pair.substring(equalsAt + 1));
      final option = name == null ? null : QueryOptionName.parse(name);
      final rule = queryOptions[option];
      if (rule == null ||
          value == null ||
          !seen.add(option!) ||
          !rule._allowsValue(value)) {
        return false;
      }
    }
    return queryOptions.entries.every(
      (entry) =>
          entry.value.presence != QueryOptionPresence.mustCarry ||
          seen.contains(entry.key),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PathPattern &&
      _sameSegments(other._segments, _segments) &&
      other.queryOptions.length == queryOptions.length &&
      queryOptions.entries.every(
        (entry) => other.queryOptions[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_segments),
    Object.hashAllUnordered([
      for (final entry in queryOptions.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );

  @override
  String toString() => path;
}

bool _sameSegments(List<_Segment> a, List<_Segment> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A query option a [PathPattern] lets a read carry, such as `$select`.
final class QueryOptionName {
  const QueryOptionName._(this.value);

  /// [raw] as an option name, or null unless it is letters, optionally
  /// after one `$`.
  static QueryOptionName? parse(String raw) =>
      RegExp(r'^\$?[A-Za-z]+$').hasMatch(raw) ? QueryOptionName._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) =>
      other is QueryOptionName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Whether a read must carry a query option, or only may.
enum QueryOptionPresence { mayCarry, mustCarry }

/// What a [PathPattern] lets a read carry as one query option: a
/// comma-separated list of words, each one of [wordsFrom], so an option
/// can only narrow what a read returns to what the rules chose to show.
///
/// The words are an allow-list, never a pattern: a site can return what
/// a word names in a spelling nobody tried, such as Graph handing out a
/// signed-in-by-nobody `downloadUrl` for `$select=*` or
/// `$select=name,content.downloadUrl`.
final class QueryOptionRule {
  const QueryOptionRule._(this.presence, this.wordsFrom);

  /// The rule, or null when [wordsFrom] is empty or a word in it isn't
  /// letters only.
  static QueryOptionRule? of(
    QueryOptionPresence presence,
    Iterable<String> wordsFrom,
  ) {
    final words = Set<String>.unmodifiable(wordsFrom);
    return words.isEmpty || !words.every(_word.hasMatch)
        ? null
        : QueryOptionRule._(presence, words);
  }

  final QueryOptionPresence presence;
  final Set<String> wordsFrom;

  bool _allowsValue(String value) => value.split(',').every(wordsFrom.contains);

  @override
  bool operator ==(Object other) =>
      other is QueryOptionRule &&
      other.presence == presence &&
      other.wordsFrom.length == wordsFrom.length &&
      other.wordsFrom.containsAll(wordsFrom);

  @override
  int get hashCode => Object.hash(presence, Object.hashAllUnordered(wordsFrom));
}

/// One word an option's value may list, such as a field name.
final _word = RegExp(r'^[A-Za-z]+$');

/// One segment of a [PathPattern].
sealed class _Segment {
  const _Segment();

  static _Segment? parse(String raw) {
    if (raw.startsWith(_Name.placeholder)) {
      final suffix = raw.substring(_Name.placeholder.length);
      if (suffix.isEmpty) return const _Name('');
      final decoded = _literal(suffix);
      return decoded == null ? null : _Name(decoded);
    }
    final decoded = _literal(raw);
    return decoded == null ? null : _Literal(decoded);
  }

  bool matches(String decoded);
}

/// A segment spelled exactly, held decoded.
final class _Literal extends _Segment {
  const _Literal(this.decoded);

  final String decoded;

  @override
  bool matches(String decoded) => decoded == this.decoded;

  @override
  bool operator ==(Object other) =>
      other is _Literal && other.decoded == decoded;

  @override
  int get hashCode => decoded.hashCode;
}

/// A segment naming one thing, then [suffix], held decoded.
final class _Name extends _Segment {
  const _Name(this.suffix);

  static const placeholder = '{name}';

  final String suffix;

  @override
  bool matches(String decoded) {
    if (!decoded.endsWith(suffix)) return false;
    final name = decoded.substring(0, decoded.length - suffix.length);
    return name.isNotEmpty &&
        !name.contains(RegExp(r'[/\\:]')) &&
        !RegExp(r'^\.+$').hasMatch(name);
  }

  @override
  bool operator ==(Object other) => other is _Name && other.suffix == suffix;

  @override
  int get hashCode => Object.hash(_Name, suffix);
}

/// [raw], one literal segment of a pattern, decoded, or null unless a
/// path could carry it as one segment exactly: not empty, with no `{` or
/// `}`, and as [WebPath] would send it, which refuses `.` and `..`. No `*`
/// either, so no pattern reads as a wildcard it isn't.
String? _literal(String raw) {
  if (raw.isEmpty || raw.contains(RegExp(r'[{}?*]'))) return null;
  if (WebPath.parse('/$raw') == null) return null;
  final decoded = _decoded(raw);
  return decoded == null || decoded.contains('/') ? null : decoded;
}

/// [raw], one segment of a [WebPath], decoded, or null when it isn't
/// UTF-8. Every escape in a [WebPath] is well formed.
String? _decoded(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } on FormatException {
    return null;
  }
}

/// [raw], one name or value of a [WebPath]'s query, decoded, or null when
/// it isn't UTF-8.
String? _decodedQuery(String raw) {
  try {
    return Uri.decodeQueryComponent(raw);
  } on FormatException {
    return null;
  }
}
