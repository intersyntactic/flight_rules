import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';

import 'read_strictly.dart';

/// A trajectory's rules: every way words can get off this machine, and what
/// each may carry where.
///
/// Files and programs on the machine need no rule: reading, writing and
/// running a program carry nothing off it by themselves. A program can leave
/// only through its own network, which [programsNetwork] decides. A model
/// call or a web request only reads, yet carries the case's words away, so
/// each is named here.
final class WhatMayLeaveThisMachine {
  WhatMayLeaveThisMachine({
    required Iterable<ModelSignInName> modelSignInsCallsMayGoOutAs,
    required Iterable<SiteAndSignIn> sitesTheWebDriverMayReach,
    required this.programsNetwork,
  }) : modelSignInsCallsMayGoOutAs = Set.unmodifiable(
         modelSignInsCallsMayGoOutAs,
       ),
       sitesTheWebDriverMayReach = Set.unmodifiable(sitesTheWebDriverMayReach);

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
      'sitesTheWebDriverMayReach',
      'programsNetwork',
    });
    return WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [
        for (final (i, name)
            in json.list('modelSignInsCallsMayGoOutAs').indexed)
          decodeModelSignInName(name, '$field.modelSignInsCallsMayGoOutAs[$i]'),
      ],
      sitesTheWebDriverMayReach: [
        for (final (i, site)
            in json.objects('sitesTheWebDriverMayReach').indexed)
          SiteAndSignIn.fromJson(site, '$field.sitesTheWebDriverMayReach[$i]'),
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

  /// Each site the web driver may make a request to for this trajectory,
  /// with the sign-in it goes as.
  final Set<SiteAndSignIn> sitesTheWebDriverMayReach;

  final ProgramsNetwork programsNetwork;

  /// Whether a model call may go out as [signIn].
  bool allowsModelCall(ModelSignInName signIn) =>
      modelSignInsCallsMayGoOutAs.contains(signIn);

  /// Whether a web request to [site], as [signIn] or as nobody when it is
  /// null, is granted by [sitesTheWebDriverMayReach]. A request under no
  /// sign-in matches only a [GoesAsNobody] grant, and one under a sign-in
  /// only a grant of that sign-in, so a grant to fetch a page anonymously
  /// never lets the trajectory make requests there as a bot.
  bool allowsWebRequest(Origin site, SignIn? signIn) =>
      sitesTheWebDriverMayReach.contains(
        SiteAndSignIn(site, switch (signIn) {
          final signIn? => GoesAsSignIn(signIn),
          null => const GoesAsNobody(),
        }),
      );

  JsonObject toJson() => JsonObject.of({
    'modelSignInsCallsMayGoOutAs': [
      for (final name in modelSignInsCallsMayGoOutAs)
        encodeModelSignInName(name),
    ],
    'sitesTheWebDriverMayReach': [
      for (final site in sitesTheWebDriverMayReach) site.toJson(),
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
  /// itself. [WhatMayLeaveThisMachine.sitesTheWebDriverMayReach] then limits
  /// only the web driver, not the trajectory.
  sharesThisMachinesNetwork,
}

/// A site the web driver may reach, and the sign-in it goes as there: one
/// grant, never the site alone, since every bot of a kind makes requests to
/// the same sites.
final class SiteAndSignIn {
  const SiteAndSignIn(this.site, this.goesAs);

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts.
  static SiteAndSignIn fromJson(JsonObject json, String field) {
    exactly(field, json, const {'site', 'goesAs'});
    return SiteAndSignIn(
      decodeOrigin(json.raw('site'), '$field.site'),
      GoesAs._fromJson(json.object('goesAs'), '$field.goesAs'),
    );
  }

  final Origin site;
  final GoesAs goesAs;

  @override
  bool operator ==(Object other) =>
      other is SiteAndSignIn && other.site == site && other.goesAs == goesAs;

  @override
  int get hashCode => Object.hash(site, goesAs);

  JsonObject toJson() =>
      JsonObject.of({'site': encodeOrigin(site), 'goesAs': goesAs._toJson()});
}

/// Who a request to a granted site goes as: a [GoesAsSignIn], or
/// [GoesAsNobody]. Never null, so "no sign-in" cannot be read as "any
/// sign-in", here or on the wire.
sealed class GoesAs {
  const GoesAs();

  static GoesAs _fromJson(JsonObject json, String field) {
    switch (oneOf(_GoesAsKind.values, json.string('kind'), '$field.kind')) {
      case _GoesAsKind.signIn:
        exactly(field, json, const {'kind', 'signIn'});
        return GoesAsSignIn(decodeSignIn(json.raw('signIn'), '$field.signIn'));
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
enum _GoesAsKind { signIn, nobody }
