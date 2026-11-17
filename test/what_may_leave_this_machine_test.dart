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
    modelSignInsTheLoopIsGiven: [claudeTeam],
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
    expect(back.modelSignInsTheLoopIsGiven, rules.modelSignInsTheLoopIsGiven);
    expect(back.sitesTheWebDriverMayReach, rules.sitesTheWebDriverMayReach);
    expect(back.programsNetwork, ProgramsNetwork.noNetworkOfTheirOwn);
  });

  test('a site is granted with its sign-in, never alone', () {
    expect(rules.allowsWebRequest(teams, bot), isTrue);
    expect(rules.allowsWebRequest(docs, null), isTrue);
    // No sign-in is not any sign-in, and a sign-in is not no sign-in.
    expect(rules.allowsWebRequest(docs, bot), isFalse);
    expect(rules.allowsWebRequest(teams, null), isFalse);
    expect(rules.allowsWebRequest(teams, SignIn.parse('other-bot')), isFalse);
    expect(
      rules.allowsWebRequest(Origin.parse('https://evil.example')!, null),
      isFalse,
    );
  });

  test('a model call goes out only as a sign-in the loop is given', () {
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
      {...good, 'modelSignInsTheLoopIsGiven': 'claude-team'},
      {
        ...good,
        'modelSignInsTheLoopIsGiven': ['Claude Team'],
      },
      {
        ...good,
        'modelSignInsTheLoopIsGiven': [null],
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
