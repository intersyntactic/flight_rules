import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:test/test.dart';

void main() {
  final teams = Origin.parse('https://graph.microsoft.com')!;
  final docs = Origin.parse('https://docs.example.com')!;
  final bot = SignIn.parse('teams-bot')!;
  final claudeTeam = ModelSignInName.parse('claude-team')!;
  final rules = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    sitesTheWebDriverMayReach: [
      SiteAndSignIn(teams, GoesAsSignIn(bot)),
      SiteAndSignIn(docs, const GoesAsNobody()),
    ],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );

  test('what may leave this machine reads back as it was written', () {
    final back = WhatMayLeaveThisMachine.fromJson(
      JsonObject.decode(jsonEncode(rules.toJson())),
    );
    expect(back.modelSignInsCallsMayGoOutAs, rules.modelSignInsCallsMayGoOutAs);
    expect(back.sitesTheWebDriverMayReach, rules.sitesTheWebDriverMayReach);
    expect(back.programsNetwork, ProgramsNetwork.noNetworkOfTheirOwn);
  });

  test('a site is granted with its sign-in, never alone', () {
    SiteAndSignIn? grant(Origin site, SignIn? signIn) =>
        rules.grantFor(site, signIn, leasedNow: const {});
    expect(grant(teams, bot), SiteAndSignIn(teams, GoesAsSignIn(bot)));
    expect(grant(docs, null), SiteAndSignIn(docs, const GoesAsNobody()));
    // No sign-in is not any sign-in, and a sign-in is not no sign-in.
    expect(grant(docs, bot), isNull);
    expect(grant(teams, null), isNull);
    expect(grant(teams, SignIn.parse('other-bot')), isNull);
    expect(grant(Origin.parse('https://evil.example')!, null), isNull);
  });

  group('a grant to the bot leased from a pool', () {
    final agents = BotPool.parse('teams-agents')!;
    final github = BotPool.parse('github-agents')!;
    final researcher1 = SignIn.parse('researcher1')!;
    final reviewer2 = SignIn.parse('reviewer2')!;
    final leasedGrant = SiteAndSignIn(teams, GoesAsBotLeasedFrom(agents));
    final leasing = WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [claudeTeam],
      sitesTheWebDriverMayReach: [leasedGrant],
      programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
    );

    test('matches the bot leased from that pool, and only it', () {
      expect(
        leasing.grantFor(teams, researcher1, leasedNow: {agents: researcher1}),
        leasedGrant,
      );
      // Another bot of the same pool, leased to another trajectory.
      expect(
        leasing.grantFor(teams, reviewer2, leasedNow: {agents: researcher1}),
        isNull,
      );
      expect(
        leasing.grantFor(docs, researcher1, leasedNow: {agents: researcher1}),
        isNull,
      );
    });

    test('matches nothing once the lease ends', () {
      expect(leasing.grantFor(teams, researcher1, leasedNow: const {}), isNull);
    });

    test('matches nothing for a bot leased from another pool', () {
      expect(
        leasing.grantFor(teams, researcher1, leasedNow: {github: researcher1}),
        isNull,
      );
    });

    test('never matches a request under no sign-in', () {
      expect(
        leasing.grantFor(teams, null, leasedNow: {agents: researcher1}),
        isNull,
      );
    });

    test('gives way to a grant of the sign-in itself, which needs no '
        'lease', () {
      final both = WhatMayLeaveThisMachine(
        modelSignInsCallsMayGoOutAs: [claudeTeam],
        sitesTheWebDriverMayReach: [
          leasedGrant,
          SiteAndSignIn(teams, GoesAsSignIn(researcher1)),
        ],
        programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
      );
      expect(
        both.grantFor(teams, researcher1, leasedNow: {agents: researcher1}),
        SiteAndSignIn(teams, GoesAsSignIn(researcher1)),
      );
    });

    test('reads back as it was written', () {
      final back = WhatMayLeaveThisMachine.fromJson(
        JsonObject.decode(jsonEncode(leasing.toJson())),
      );
      expect(back.sitesTheWebDriverMayReach, {leasedGrant});
    });
  });

  test('a model call goes out only as a sign-in the rules name', () {
    expect(rules.allowsModelCall(claudeTeam), isTrue);
    expect(rules.allowsModelCall(ModelSignInName.parse('other')!), isFalse);
  });

  test('a grant under no sign-in is not a grant under a sign-in', () {
    // By ==, not only by hash, so a set that compared grants by site alone
    // would still be caught.
    expect(const GoesAsNobody() == GoesAsSignIn(bot), isFalse);
    expect(GoesAsSignIn(bot) == const GoesAsNobody(), isFalse);
    expect(
      SiteAndSignIn(docs, const GoesAsNobody()) ==
          SiteAndSignIn(docs, GoesAsSignIn(bot)),
      isFalse,
    );
    expect(
      SiteAndSignIn(docs, GoesAsSignIn(bot)) ==
          SiteAndSignIn(docs, GoesAsSignIn(SignIn.parse('other-bot')!)),
      isFalse,
    );
  });

  test('what may leave this machine is read strictly', () {
    final good = rules.toJson().asUncheckedMap();
    final site = {
      'site': 'https://docs.example.com',
      'goesAs': {'kind': 'nobody'},
    };
    for (final json in [
      null,
      <String, Object?>{},
      {...good, 'mayWrite': true},
      {...good, 'programsNetwork': 'visorUp'},
      {...good, 'modelSignInsCallsMayGoOutAs': 'claude-team'},
      {
        ...good,
        'modelSignInsCallsMayGoOutAs': ['Claude Team'],
      },
      {
        ...good,
        'modelSignInsCallsMayGoOutAs': [null],
      },
      for (final bad in <Object?>[
        {...site, 'goesAs': null},
        {...site, 'goesAs': 'nobody'},
        {
          ...site,
          'goesAs': {'kind': 'anyone'},
        },
        {
          ...site,
          'goesAs': {'kind': 'nobody', 'signIn': 'teams-bot'},
        },
        {
          ...site,
          'goesAs': {'kind': 'signIn'},
        },
        {
          ...site,
          'goesAs': {'kind': 'signIn', 'signIn': 'teams-bot', 'as': 'x'},
        },
        {
          ...site,
          'goesAs': {'kind': 'botLeasedFrom'},
        },
        {
          ...site,
          'goesAs': {'kind': 'botLeasedFrom', 'pool': 'Teams Agents'},
        },
        {
          ...site,
          'goesAs': {
            'kind': 'botLeasedFrom',
            'pool': 'teams-agents',
            'signIn': 'researcher1',
          },
        },
        {...site, 'site': 'https://docs.example.com/path'},
        {...site, 'path': '/'},
      ])
        {
          ...good,
          'sitesTheWebDriverMayReach': [bad],
        },
    ]) {
      expect(
        () => WhatMayLeaveThisMachine.fromJson(
          JsonObject.decode(jsonEncode(json)),
        ),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
