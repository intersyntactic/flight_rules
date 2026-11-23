import 'package:is_effects/is_effects.dart';

/// The paths one kind of read may take on a site: a fixed number of
/// segments, each a literal or a `{name}`, and the query options it may
/// carry.
///
/// Written as a path, such as `/drives/b!D/items/01F:/{name}:/content`.
/// A literal segment is compared decoded, as [PathPrefix] compares them,
/// so `01F%3A` is `01F:`. `{name}` is one segment naming one thing in the
/// place the literals before it lead to, never a way past it: not empty,
/// no `/`, `\` or `:` once decoded, and not only dots. It may end in a
/// fixed literal suffix, as `{name}:` does. There is no wildcard and no
/// "any depth", so a pattern reaches exactly the paths it spells.
final class PathPattern {
  const PathPattern._(this.path, this._segments, this.optionsTakingWordLists);

  /// [path] as a pattern whose query may carry each of
  /// [optionsTakingWordLists] at most once, each with a comma-separated
  /// list of words; with none, it carries no query. Null when [path] isn't
  /// one: it must start with `/`, name at least two segments, so the
  /// prefix a read is granted under is never the whole site, and start
  /// with a literal.
  static PathPattern? parse(
    String path, {
    Iterable<QueryOptionName> optionsTakingWordLists = const [],
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
      Set.unmodifiable(optionsTakingWordLists),
    );
  }

  /// The pattern as it was written.
  final String path;
  final List<_Segment> _segments;
  final Set<QueryOptionName> optionsTakingWordLists;

  /// The prefix a read of [path] is granted under when this pattern
  /// matches it, or null when it doesn't: [path] with its last segment
  /// and query left off, so a redirect on the same site stays on this
  /// read.
  PathPrefix? prefixMatching(WebPath path) {
    final queryAt = path.value.indexOf('?');
    final raw = queryAt < 0 ? path.value : path.value.substring(0, queryAt);
    if (queryAt >= 0 && !_allowsQuery(path.value.substring(queryAt + 1))) {
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

  bool _allowsQuery(String query) {
    final seen = <QueryOptionName>{};
    for (final pair in query.split('&')) {
      final equalsAt = pair.indexOf('=');
      if (equalsAt < 0) return false;
      final name = _decodedQuery(pair.substring(0, equalsAt));
      final value = _decodedQuery(pair.substring(equalsAt + 1));
      final option = name == null ? null : QueryOptionName.parse(name);
      if (option == null ||
          value == null ||
          !optionsTakingWordLists.contains(option) ||
          !seen.add(option) ||
          !_wordList.hasMatch(value)) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is PathPattern &&
      _sameSegments(other._segments, _segments) &&
      other.optionsTakingWordLists.length == optionsTakingWordLists.length &&
      other.optionsTakingWordLists.containsAll(optionsTakingWordLists);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_segments),
    Object.hashAllUnordered(optionsTakingWordLists),
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

/// A comma-separated list of words, such as field names: no expression,
/// so an option can only narrow what a read returns.
final _wordList = RegExp(r'^[A-Za-z]+(,[A-Za-z]+)*$');

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
