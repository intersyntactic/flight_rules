import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';

import 'read_strictly.dart';

/// A trajectory's rules: every way words can get off this machine, and what
/// each may carry where.
///
/// Files need no rule, and which programs may run is [FlightRules]'s:
/// reading, writing and running a program carry nothing off the machine by
/// themselves. A program can leave only through its own network, which
/// [programsNetwork] decides. A model
/// call, a fetch or a web request carries the case's words away, so each is
/// named here.
final class WhatMayLeaveThisMachine {
  WhatMayLeaveThisMachine({
    required Iterable<ModelSignInName> modelSignInsCallsMayGoOutAs,
    required Iterable<GrantToFetch> fetchesMayReach,
    required Iterable<GrantToMakeWebRequests> webRequestsMayReach,
    required this.programsNetwork,
  }) : modelSignInsCallsMayGoOutAs = Set.unmodifiable(
         modelSignInsCallsMayGoOutAs,
       ),
       fetchesMayReach = Set.unmodifiable(fetchesMayReach),
       webRequestsMayReach = Set.unmodifiable(webRequestsMayReach);

  /// [json] read back, strictly: a key it does not know, or a part that is
  /// not what it names, throws a [FormatException] naming the part. A key
  /// it does not know is never skipped, since a reader that skipped one
  /// would skip whatever it restricts.
  static WhatMayLeaveThisMachine fromJson(
    JsonObject json, [
    String field = 'whatMayLeaveThisMachine',
  ]) {
    exactly(field, json, const {
      'modelSignInsCallsMayGoOutAs',
      'fetchesMayReach',
      'webRequestsMayReach',
      'programsNetwork',
    });
    return WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [
        for (final (i, name)
            in json.list('modelSignInsCallsMayGoOutAs').indexed)
          decodeModelSignInName(name, '$field.modelSignInsCallsMayGoOutAs[$i]'),
      ],
      fetchesMayReach: [
        for (final (i, grant) in json.objects('fetchesMayReach').indexed)
          GrantToFetch.fromJson(grant, '$field.fetchesMayReach[$i]'),
      ],
      webRequestsMayReach: [
        for (final (i, grant) in json.objects('webRequestsMayReach').indexed)
          GrantToMakeWebRequests.fromJson(
            grant,
            '$field.webRequestsMayReach[$i]',
          ),
      ],
      programsNetwork: oneOf(
        ProgramsNetwork.values,
        json.string('programsNetwork'),
        '$field.programsNetwork',
      ),
    );
  }

  /// The model sign-ins a model call for this trajectory may go out as, by
  /// name. The airlock makes the call; the loop holds no credential.
  final Set<ModelSignInName> modelSignInsCallsMayGoOutAs;

  /// Where a fetch for this trajectory may read from, and who it goes as.
  final Set<GrantToFetch> fetchesMayReach;

  /// Where the web requests a tool builds for this trajectory may go, and
  /// who they go as.
  final Set<GrantToMakeWebRequests> webRequestsMayReach;

  final ProgramsNetwork programsNetwork;

  /// Whether a model call may go out as [signIn].
  bool allowsModelCall(ModelSignInName signIn) =>
      modelSignInsCallsMayGoOutAs.contains(signIn);

  /// The grant in [fetchesMayReach] that lets a fetch from [path] on [site]
  /// go as [signIn], or as nobody when it is null, with the prefix it was
  /// granted under, for the request's `grantedPathPrefix`; null when none
  /// does. [leasedNow] and [pooled] are as [webRequestsGrantFor] takes them.
  ({GrantToFetch grant, PathPrefix grantedPathPrefix})? fetchGrantFor(
    Origin site,
    WebPath path,
    SignIn? signIn, {
    required Map<BotPool, SignIn> leasedNow,
    required Set<SignIn> pooled,
  }) {
    for (final goesAs in _goesAsFor(signIn, leasedNow, pooled)) {
      for (final grant in fetchesMayReach) {
        if (grant.goesAs != goesAs) continue;
        final prefix = grant.from._prefixCovering(site, path);
        if (prefix != null) return (grant: grant, grantedPathPrefix: prefix);
      }
    }
    return null;
  }

  /// The grant in [webRequestsMayReach] that lets a web request to [path]
  /// on [site] go as [signIn], or as nobody when it is null, with the
  /// prefix it was granted under, for the request's `grantedPathPrefix`;
  /// null when none does. Every request a tool builds is decided on its
  /// own, and all of them must have a grant.
  ///
  /// [leasedNow] is each bot this trajectory holds a lease on right now, by
  /// the pool it came from; [pooled] is every sign-in ever added to any
  /// pool, whoever holds it, since a bot taken out of a pool must not
  /// become grantable by name while a lease on it may still run.
  /// [replyEndpoint] is where replies to the event that started this
  /// trajectory go, or null when no event did.
  ///
  /// A request under no sign-in matches only a [GoesAsNobody] grant, so a
  /// grant to reach a site anonymously never lets the trajectory make
  /// requests there as a bot. One under a sign-in matches a
  /// [GoesAsBotLeasedFrom] grant whose pool's lease is that sign-in, or,
  /// for a sign-in in no pool, a grant of that sign-in. A pooled bot's
  /// sign-in is never granted by name, so no rules can let a trajectory
  /// post as a bot leased to another. When both match, the grant of the
  /// sign-in is returned, since it relies on no lease.
  ({GrantToMakeWebRequests grant, PathPrefix grantedPathPrefix})?
  webRequestsGrantFor(
    Origin site,
    WebPath path,
    SignIn? signIn, {
    required Map<BotPool, SignIn> leasedNow,
    required Set<SignIn> pooled,
    required AddressPrefix? replyEndpoint,
  }) {
    for (final goesAs in _goesAsFor(signIn, leasedNow, pooled)) {
      for (final grant in webRequestsMayReach) {
        if (grant.goesAs != goesAs) continue;
        final prefix = grant.to._prefixCovering(site, path, replyEndpoint);
        if (prefix != null) return (grant: grant, grantedPathPrefix: prefix);
      }
    }
    return null;
  }

  /// The sign-in a reply to [replyEndpoint] can go as: one a
  /// [ToOwnReplyEndpoint] grant on [replyEndpoint]'s origin goes as, by
  /// name before by lease, as [webRequestsGrantFor] prefers, so every
  /// request the loop builds under the endpoint as it is granted. Null when
  /// none can. A reply grant under no sign-in is never chosen, since a
  /// reply is posted as someone. [leasedNow] and [pooled] are as
  /// [webRequestsGrantFor] takes them.
  SignIn? signInForReply({
    required AddressPrefix replyEndpoint,
    required Map<BotPool, SignIn> leasedNow,
    required Set<SignIn> pooled,
  }) {
    final replyGrantsGoAs = [
      for (final grant in webRequestsMayReach)
        if (grant.to case ToOwnReplyEndpoint(:final onOneOf)
            when onOneOf.contains(replyEndpoint.origin))
          grant.goesAs,
    ];
    for (final goesAs in replyGrantsGoAs) {
      if (goesAs case GoesAsSignIn(:final signIn)
          when !pooled.contains(signIn)) {
        return signIn;
      }
    }
    for (final goesAs in replyGrantsGoAs) {
      if (goesAs case GoesAsBotLeasedFrom(:final pool)) {
        if (leasedNow[pool] case final leased?) return leased;
      }
    }
    return null;
  }

  /// Each [GoesAs] a request under [signIn] may be granted by, the one
  /// relying on no lease first.
  static List<GoesAs> _goesAsFor(
    SignIn? signIn,
    Map<BotPool, SignIn> leasedNow,
    Set<SignIn> pooled,
  ) => switch (signIn) {
    null => const [GoesAsNobody()],
    final SignIn signIn => [
      if (!pooled.contains(signIn)) GoesAsSignIn(signIn),
      for (final MapEntry(key: pool, value: leased) in leasedNow.entries)
        if (leased == signIn) GoesAsBotLeasedFrom(pool),
    ],
  };

  JsonObject toJson() => JsonObject.of({
    'modelSignInsCallsMayGoOutAs': [
      for (final name in modelSignInsCallsMayGoOutAs)
        encodeModelSignInName(name),
    ],
    'fetchesMayReach': [for (final grant in fetchesMayReach) grant.toJson()],
    'webRequestsMayReach': [
      for (final grant in webRequestsMayReach) grant.toJson(),
    ],
    'programsNetwork': programsNetwork.name,
  });
}

/// Whether a trajectory's programs can reach a network themselves.
enum ProgramsNetwork {
  /// The suit has no network of its own: a program reaches nothing off
  /// this machine, and only the web driver can.
  noNetworkOfTheirOwn,

  /// The suit shares this machine's network: a program can reach any site
  /// itself. The web grants then limit only the web driver, not the
  /// trajectory.
  sharesThisMachinesNetwork,
}

/// A grant to fetch [from] somewhere, going as [goesAs]: one grant, never
/// the addresses alone, since every bot of a kind reads from the same sites.
final class GrantToFetch {
  const GrantToFetch(this.from, this.goesAs);

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts.
  static GrantToFetch fromJson(JsonObject json, String field) {
    exactly(field, json, const {'from', 'goesAs'});
    return GrantToFetch(
      WhereFetchesReadFrom._fromJson(json.object('from'), '$field.from'),
      GoesAs._fromJson(json.object('goesAs'), '$field.goesAs'),
    );
  }

  final WhereFetchesReadFrom from;
  final GoesAs goesAs;

  @override
  bool operator ==(Object other) =>
      other is GrantToFetch && other.from == from && other.goesAs == goesAs;

  @override
  int get hashCode => Object.hash(from, goesAs);

  JsonObject toJson() =>
      JsonObject.of({'from': from._toJson(), 'goesAs': goesAs._toJson()});
}

/// Where fetches may read from: [FromAddressesUnder] a prefix the rules
/// name, or [FromGraphFolder], one folder of a Microsoft Graph drive.
sealed class WhereFetchesReadFrom {
  const WhereFetchesReadFrom();

  static WhereFetchesReadFrom _fromJson(JsonObject json, String field) {
    switch (oneOf(_FromKind.values, json.string('kind'), '$field.kind')) {
      case _FromKind.addressesUnder:
        exactly(field, json, const {'kind', 'prefix'});
        return FromAddressesUnder(
          _addressPrefixFromJson(json.object('prefix'), '$field.prefix'),
        );
      case _FromKind.graphFolder:
        exactly(field, json, const {'kind', 'drive', 'folder'});
        return FromGraphFolder(
          _graphIdFromJson(json.string('drive'), '$field.drive'),
          _graphIdFromJson(json.string('folder'), '$field.folder'),
        );
    }
  }

  /// The path prefix under which a fetch of [path] on [site] reads from
  /// here, or null when it doesn't.
  PathPrefix? _prefixCovering(Origin site, WebPath path);

  JsonObject _toJson();
}

/// Fetches read from the addresses under [prefix].
final class FromAddressesUnder extends WhereFetchesReadFrom {
  const FromAddressesUnder(this.prefix);

  final AddressPrefix prefix;

  @override
  PathPrefix? _prefixCovering(Origin site, WebPath path) =>
      prefix.covers(site, path) ? prefix.pathPrefix : null;

  @override
  bool operator ==(Object other) =>
      other is FromAddressesUnder && other.prefix == prefix;

  @override
  int get hashCode => prefix.hashCode;

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _FromKind.addressesUnder.name,
    'prefix': encodeAddressPrefix(prefix),
  });
}

/// Fetches read the files in [folder] of [drive] on Microsoft Graph, and
/// nothing else: its listing, `/v1.0/drives/{drive}/items/{folder}/children`
/// with at most a `$select`, and a file in it by name,
/// `/v1.0/drives/{drive}/items/{folder}:/{name}:/content`.
///
/// A path prefix can't say this. Graph names a file in a folder as
/// `{folder}:`, a segment that isn't `{folder}`, and a file read by its own
/// id doesn't name its folder at all, so every other route Graph has to a
/// file is refused rather than checked. A name that could reach past the
/// folder (a `/`, `\` or `:` in it, or only dots) is refused too; no
/// OneDrive name has one.
final class FromGraphFolder extends WhereFetchesReadFrom {
  const FromGraphFolder(this.drive, this.folder);

  final GraphId drive;
  final GraphId folder;

  /// Each segment is compared decoded, as is_effects' [PathPrefix] compares
  /// them canonically, so `{folder}%3A` is `{folder}:`.
  @override
  PathPrefix? _prefixCovering(Origin site, WebPath path) {
    if (site != _graph) return null;
    final queryAt = path.value.indexOf('?');
    final raw = queryAt < 0 ? path.value : path.value.substring(0, queryAt);
    final query = queryAt < 0 ? null : path.value.substring(queryAt + 1);
    final segments = _decodedSegments(raw);
    final folderAt = '/v1.0/drives/${drive.value}/items/${folder.value}';
    switch (segments) {
      case ['v1.0', 'drives', final d, 'items', final f, 'children']
          when d == drive.value &&
              f == folder.value &&
              (query == null || _isSelectOnly(query)):
        return PathPrefix.parse('$folderAt/');
      case ['v1.0', 'drives', final d, 'items', final f, final name, 'content']
          when query == null &&
              d == drive.value &&
              f == '${folder.value}:' &&
              _isFileNameAndColon(name):
        return PathPrefix.parse('$folderAt:/${raw.split('/')[6]}/');
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FromGraphFolder &&
      other.drive == drive &&
      other.folder == folder;

  @override
  int get hashCode => Object.hash(drive, folder);

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _FromKind.graphFolder.name,
    'drive': drive.value,
    'folder': folder.value,
  });
}

final _graph = Origin.parse('https://graph.microsoft.com')!;

/// [raw]'s segments after its leading `/`, each decoded, or null when one
/// isn't UTF-8. [raw] is from a [WebPath], so every escape in it is well
/// formed.
List<String>? _decodedSegments(String raw) {
  if (!raw.startsWith('/')) return null;
  try {
    return [
      for (final s in raw.substring(1).split('/')) Uri.decodeComponent(s),
    ];
  } on FormatException {
    return null;
  }
}

/// Whether [query] asks only which fields to return: a `$select` listing
/// names. Another query option, such as `$expand=children`, could list
/// what lies below the folder.
bool _isSelectOnly(String query) {
  try {
    return RegExp(r'^\$select=[A-Za-z]+(,[A-Za-z]+)*$')
        .hasMatch(Uri.decodeQueryComponent(query));
  } on FormatException {
    return false;
  }
}

/// Whether [segment], decoded, is a file's name and the `:` that ends it.
bool _isFileNameAndColon(String segment) {
  if (!segment.endsWith(':')) return false;
  final name = segment.substring(0, segment.length - 1);
  return name.isNotEmpty &&
      !name.contains(RegExp(r'[/\\:]')) &&
      !RegExp(r'^\.+$').hasMatch(name);
}

/// The tag a [WhereFetchesReadFrom] carries on the wire.
enum _FromKind { addressesUnder, graphFolder }

/// A Microsoft Graph drive or item id, such as `b!3x9Q…` or
/// `01BYE5RZ6QN3…`: letters, digits, `!`, `-` and `_`, so it is always one
/// path segment, spelled one way.
final class GraphId {
  const GraphId._(this.value);

  /// [raw] as an id, or null when it has any other character or none.
  static GraphId? parse(String raw) =>
      RegExp(r'^[A-Za-z0-9!_-]+$').hasMatch(raw) ? GraphId._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) => other is GraphId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

GraphId _graphIdFromJson(String raw, String field) =>
    GraphId.parse(raw) ??
    (throw FormatException('$field: not a Graph id: $raw'));

/// A grant to make web requests [to] somewhere, going as [goesAs].
final class GrantToMakeWebRequests {
  const GrantToMakeWebRequests(this.to, this.goesAs);

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts.
  static GrantToMakeWebRequests fromJson(JsonObject json, String field) {
    exactly(field, json, const {'to', 'goesAs'});
    return GrantToMakeWebRequests(
      WhereWebRequestsGo._fromJson(json.object('to'), '$field.to'),
      GoesAs._fromJson(json.object('goesAs'), '$field.goesAs'),
    );
  }

  final WhereWebRequestsGo to;
  final GoesAs goesAs;

  @override
  bool operator ==(Object other) =>
      other is GrantToMakeWebRequests &&
      other.to == to &&
      other.goesAs == goesAs;

  @override
  int get hashCode => Object.hash(to, goesAs);

  JsonObject toJson() =>
      JsonObject.of({'to': to._toJson(), 'goesAs': goesAs._toJson()});
}

/// Where web requests may go: [ToAddressesUnder] a prefix the rules name,
/// or [ToOwnReplyEndpoint], wherever replies to the event that started the
/// trajectory go.
sealed class WhereWebRequestsGo {
  const WhereWebRequestsGo();

  static WhereWebRequestsGo _fromJson(JsonObject json, String field) {
    switch (oneOf(_WhereKind.values, json.string('kind'), '$field.kind')) {
      case _WhereKind.addressesUnder:
        exactly(field, json, const {'kind', 'prefix'});
        return ToAddressesUnder(
          _addressPrefixFromJson(json.object('prefix'), '$field.prefix'),
        );
      case _WhereKind.ownReplyEndpoint:
        exactly(field, json, const {'kind', 'onOneOf'});
        return ToOwnReplyEndpoint.of([
              for (final (i, origin) in json.list('onOneOf').indexed)
                decodeOrigin(origin, '$field.onOneOf[$i]'),
            ]) ??
            (throw FormatException('$field.onOneOf: names no origin'));
    }
  }

  /// The path prefix under which a request to [path] on [site] goes here,
  /// or null when it doesn't.
  PathPrefix? _prefixCovering(
    Origin site,
    WebPath path,
    AddressPrefix? replyEndpoint,
  );

  JsonObject _toJson();
}

/// Requests go to the addresses under [prefix].
final class ToAddressesUnder extends WhereWebRequestsGo {
  const ToAddressesUnder(this.prefix);

  final AddressPrefix prefix;

  @override
  PathPrefix? _prefixCovering(
    Origin site,
    WebPath path,
    AddressPrefix? replyEndpoint,
  ) => prefix.covers(site, path) ? prefix.pathPrefix : null;

  @override
  bool operator ==(Object other) =>
      other is ToAddressesUnder && other.prefix == prefix;

  @override
  int get hashCode => prefix.hashCode;

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _WhereKind.addressesUnder.name,
    'prefix': encodeAddressPrefix(prefix),
  });
}

/// Requests go under the reply endpoint of the event that started the
/// trajectory, when that endpoint is on one of [onOneOf]. Rules are copied
/// into every trajectory a mission starts, while each trajectory's
/// conversation is its own, so a grant can't name the conversation. The
/// endpoint comes from the inbound event, so the rules name the origins it
/// may be on, never leaving them open.
final class ToOwnReplyEndpoint extends WhereWebRequestsGo {
  const ToOwnReplyEndpoint._(this.onOneOf);

  /// The grant's destination, or null when [onOneOf] names no origin.
  static ToOwnReplyEndpoint? of(Iterable<Origin> onOneOf) {
    final origins = Set<Origin>.unmodifiable(onOneOf);
    return origins.isEmpty ? null : ToOwnReplyEndpoint._(origins);
  }

  final Set<Origin> onOneOf;

  @override
  PathPrefix? _prefixCovering(
    Origin site,
    WebPath path,
    AddressPrefix? replyEndpoint,
  ) => switch (replyEndpoint) {
    final endpoint?
        when onOneOf.contains(endpoint.origin) && endpoint.covers(site, path) =>
      endpoint.pathPrefix,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ToOwnReplyEndpoint &&
      other.onOneOf.length == onOneOf.length &&
      other.onOneOf.containsAll(onOneOf);

  @override
  int get hashCode => Object.hashAllUnordered(onOneOf);

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _WhereKind.ownReplyEndpoint.name,
    'onOneOf': [for (final origin in onOneOf) encodeOrigin(origin)],
  });
}

/// The tag a [WhereWebRequestsGo] carries on the wire.
enum _WhereKind { addressesUnder, ownReplyEndpoint }

/// [json] as an [AddressPrefix], read strictly: is_effects' reader skips a
/// key it does not know.
AddressPrefix _addressPrefixFromJson(JsonObject json, String field) {
  exactly(field, json, const {'origin', 'pathPrefix'});
  return AddressPrefix.of(
    decodeOrigin(json.raw('origin'), '$field.origin'),
    decodePathPrefix(json.raw('pathPrefix'), '$field.pathPrefix'),
  );
}

/// Who a request to a granted address goes as: a [GoesAsSignIn], a
/// [GoesAsBotLeasedFrom], or [GoesAsNobody]. Never null, so "no sign-in" cannot be read as "any
/// sign-in", here or on the wire.
sealed class GoesAs {
  const GoesAs();

  static GoesAs _fromJson(JsonObject json, String field) {
    switch (oneOf(_GoesAsKind.values, json.string('kind'), '$field.kind')) {
      case _GoesAsKind.signIn:
        exactly(field, json, const {'kind', 'signIn'});
        return GoesAsSignIn(decodeSignIn(json.raw('signIn'), '$field.signIn'));
      case _GoesAsKind.botLeasedFrom:
        exactly(field, json, const {'kind', 'pool'});
        return GoesAsBotLeasedFrom(
          decodeBotPool(json.raw('pool'), '$field.pool'),
        );
      case _GoesAsKind.nobody:
        exactly(field, json, const {'kind'});
        return const GoesAsNobody();
    }
  }

  JsonObject _toJson();
}

/// Requests go as [signIn].
final class GoesAsSignIn extends GoesAs {
  const GoesAsSignIn(this.signIn);

  final SignIn signIn;

  @override
  bool operator ==(Object other) =>
      other is GoesAsSignIn && other.signIn == signIn;

  @override
  int get hashCode => signIn.hashCode;

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _GoesAsKind.signIn.name,
    'signIn': encodeSignIn(signIn),
  });
}

/// Requests go as the sign-in of the bot this trajectory leases from [pool],
/// whichever bot that is when the request is decided. Rules are copied
/// when a mission is admitted, before any bot is leased, so a grant can't
/// name the bot; granting every bot in the pool would let one trajectory
/// post as another's. With no lease from [pool], the grant matches nothing.
final class GoesAsBotLeasedFrom extends GoesAs {
  const GoesAsBotLeasedFrom(this.pool);

  final BotPool pool;

  @override
  bool operator ==(Object other) =>
      other is GoesAsBotLeasedFrom && other.pool == pool;

  @override
  int get hashCode => pool.hashCode;

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _GoesAsKind.botLeasedFrom.name,
    'pool': encodeBotPool(pool),
  });
}

/// Requests go under no sign-in.
final class GoesAsNobody extends GoesAs {
  const GoesAsNobody();

  @override
  bool operator ==(Object other) => other is GoesAsNobody;

  @override
  int get hashCode => (GoesAsNobody).hashCode;

  @override
  JsonObject _toJson() => JsonObject.of({'kind': _GoesAsKind.nobody.name});
}

/// The tag a [GoesAs] carries on the wire.
enum _GoesAsKind { signIn, botLeasedFrom, nobody }
