import 'package:checked_json/checked_json.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart'
    show ModelSignInName;
import 'package:is_sign_in_vocabulary/bot_pool.dart';
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart'
    show ReplyEndpoint, RepliesUnderWebAddress, RepliesWithPinnedBodyFields;

import 'path_pattern.dart';
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
            in json.strings('modelSignInsCallsMayGoOutAs').indexed)
          ModelSignInName.parse(name) ??
              (throw FormatException(
                '$field.modelSignInsCallsMayGoOutAs[$i]: '
                'not a model sign-in name: $name',
              )),
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

  /// Whether some grant in [fetchesMayReach] reaches [path] on [site] and
  /// could let it go as [signIn], or as nobody when it is null. False means
  /// [fetchGrantFor] refuses that fetch whatever the leases and pools, so a
  /// fixed fetch can be judged when the rules are written. A grant to a
  /// pool's leased bot counts for any sign-in, since which bot is leased is
  /// known only when the fetch runs.
  bool couldEverFetch(Origin site, WebPath path, SignIn? signIn) =>
      fetchesMayReach.any(
        (grant) =>
            grant.from._prefixCovering(site, path) != null &&
            switch (grant.goesAs) {
              GoesAsNobody() => signIn == null,
              GoesAsSignIn(signIn: final named) => named == signIn,
              GoesAsBotLeasedFrom() => signIn != null,
            },
      );

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
  /// trajectory go, or null when no event did. A [ToOwnReplyEndpoint] grant
  /// lets a request through only under a [RepliesUnderWebAddress] prefix;
  /// for a [RepliesWithPinnedBodyFields] it lets none through, since the
  /// conversation is named in the body, which these rules never read, so
  /// such a reply leaves only as one the airlock builds from the endpoint.
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
    required ReplyEndpoint? replyEndpoint,
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
  /// request the loop builds under a [RepliesUnderWebAddress] goes as it is
  /// granted. For a [RepliesWithPinnedBodyFields], whether and as whom the
  /// trajectory may reply in its conversation at all. Null when
  /// none can. A reply grant under no sign-in is never chosen, since a
  /// reply is posted as someone. [leasedNow] and [pooled] are as
  /// [webRequestsGrantFor] takes them.
  SignIn? signInForReply({
    required ReplyEndpoint replyEndpoint,
    required Map<BotPool, SignIn> leasedNow,
    required Set<SignIn> pooled,
  }) {
    final origin = replyEndpoint.origin;
    final replyGrantsGoAs = [
      for (final grant in webRequestsMayReach)
        if (grant.to case ToOwnReplyEndpoint(:final onOneOf)
            when onOneOf.contains(origin))
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
      for (final name in modelSignInsCallsMayGoOutAs) name.name,
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
/// name, or [FromPathsMatching], only the paths the rules' patterns spell.
sealed class WhereFetchesReadFrom {
  const WhereFetchesReadFrom();

  static WhereFetchesReadFrom _fromJson(JsonObject json, String field) {
    switch (oneOf(_FromKind.values, json.string('kind'), '$field.kind')) {
      case _FromKind.addressesUnder:
        exactly(field, json, const {'kind', 'prefix'});
        return FromAddressesUnder(
          _addressPrefixFromJson(json.object('prefix'), '$field.prefix'),
        );
      case _FromKind.pathsMatching:
        exactly(field, json, const {'kind', 'origin', 'patterns'});
        return FromPathsMatching.of(
              decodeOrigin(json.raw('origin'), '$field.origin'),
              [
                for (final (i, pattern) in json.objects('patterns').indexed)
                  _pathPatternFromJson(pattern, '$field.patterns[$i]'),
              ],
            ) ??
            (throw FormatException('$field.patterns: names no pattern'));
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

/// Fetches read from [origin], only the paths one of [patterns] matches.
///
/// For a site where a prefix can't bound a read: one that names a thing in
/// a folder by a segment that isn't the folder's, or a thing by an id that
/// names no folder at all. The patterns spell the routes a read may take,
/// and every other route is refused rather than checked.
final class FromPathsMatching extends WhereFetchesReadFrom {
  const FromPathsMatching._(this.origin, this.patterns);

  /// The grant's source, or null when [patterns] names none.
  static FromPathsMatching? of(Origin origin, Iterable<PathPattern> patterns) {
    final all = Set<PathPattern>.unmodifiable(patterns);
    return all.isEmpty ? null : FromPathsMatching._(origin, all);
  }

  final Origin origin;
  final Set<PathPattern> patterns;

  @override
  PathPrefix? _prefixCovering(Origin site, WebPath path) {
    if (site != origin) return null;
    for (final pattern in patterns) {
      if (pattern.prefixMatching(path) case final prefix?) return prefix;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is FromPathsMatching &&
      other.origin == origin &&
      other.patterns.length == patterns.length &&
      other.patterns.containsAll(patterns);

  @override
  int get hashCode => Object.hash(origin, Object.hashAllUnordered(patterns));

  @override
  JsonObject _toJson() => JsonObject.of({
    'kind': _FromKind.pathsMatching.name,
    'origin': encodeOrigin(origin),
    'patterns': [
      for (final pattern in patterns)
        {
          'path': pattern.path,
          'queryOptions': [
            for (final MapEntry(key: name, value: rule)
                in pattern.queryOptions.entries)
              {
                'name': name.value,
                'presence': rule.presence.name,
                'wordsFrom': [...rule.wordsFrom],
              },
          ],
        },
    ],
  });
}

/// [json] as a [PathPattern], read strictly.
PathPattern _pathPatternFromJson(JsonObject json, String field) {
  exactly(field, json, const {'path', 'queryOptions'});
  final options = <QueryOptionName, QueryOptionRule>{};
  for (final (i, option) in json.objects('queryOptions').indexed) {
    final at = '$field.queryOptions[$i]';
    exactly(at, option, const {'name', 'presence', 'wordsFrom'});
    final name =
        QueryOptionName.parse(option.string('name')) ??
        (throw FormatException('$at.name: not a query option name'));
    final rule =
        QueryOptionRule.of(
          oneOf(
            QueryOptionPresence.values,
            option.string('presence'),
            '$at.presence',
          ),
          [
            for (final (j, word) in option.list('wordsFrom').indexed)
              word is String
                  ? word
                  : throw FormatException('$at.wordsFrom[$j]: not a word'),
          ],
        ) ??
        (throw FormatException('$at.wordsFrom: not a list of words'));
    if (options.containsKey(name)) {
      throw FormatException('$at.name: named twice: $name');
    }
    options[name] = rule;
  }
  return PathPattern.parse(json.string('path'), queryOptions: options) ??
      (throw FormatException('$field.path: not a path pattern'));
}

/// The tag a [WhereFetchesReadFrom] carries on the wire.
enum _FromKind { addressesUnder, pathsMatching }

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
    ReplyEndpoint? replyEndpoint,
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
    ReplyEndpoint? replyEndpoint,
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
    ReplyEndpoint? replyEndpoint,
  ) => switch (replyEndpoint) {
    RepliesUnderWebAddress()
        when onOneOf.contains(replyEndpoint.origin) &&
            replyEndpoint.admitsAddress(site, path) =>
      replyEndpoint.redirectsStayUnder,
    // These endpoints name the conversation in the request's body, which
    // these rules never read, so no raw request to one is confined to it.
    RepliesUnderWebAddress() || RepliesWithPinnedBodyFields() || null => null,
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
