import 'package:checked_json/checked_json.dart';

/// The value of [values] named [name], or a [FormatException] naming
/// [field] and every name it could have been.
T oneOf<T extends Enum>(List<T> values, String name, String field) =>
    values.asNameMap()[name] ??
    (throw FormatException(
      '$field: not one of ${values.map((v) => v.name).join(', ')}: $name',
    ));

/// [json], refused with a [FormatException] naming [field] and each key it
/// does not know, unless every key is one of [keys]. For a reader whose
/// object must never be skimmed: a key it skipped could be one that
/// restricts.
JsonObject exactly(String field, JsonObject json, Set<String> keys) {
  final unknown = json.keys.where((key) => !keys.contains(key));
  if (unknown.isNotEmpty) {
    throw FormatException('$field: unexpected ${unknown.join(', ')}');
  }
  return json;
}
