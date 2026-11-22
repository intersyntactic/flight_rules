import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:test/test.dart';

void main() {
  final claudeTeam = ModelSignInName.parse('claude-team')!;
  final opus = ModelName.parse('claude-opus-5-5')!;
  final git = ProgramName.parse('git')!;
  final pandoc = ProgramName.parse('pandoc')!;
  final whatMayLeave = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    fetchesMayReach: const [],
    webRequestsMayReach: const [],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );
  final starting = ModelAndSignIn(signIn: claudeTeam, model: opus);
  final rules = FlightRules.of(
    whatMayLeaveThisMachine: whatMayLeave,
    startingModel: starting,
    programsItMayRun: [git, pandoc],
    programsItNeeds: [git],
  )!;

  test('flight rules read back as they were written', () {
    final back = FlightRules.fromJson(
      JsonObject.decode(jsonEncode(rules.toJson())),
    );
    expect(back.startingModel, rules.startingModel);
    expect(
      back.whatMayLeaveThisMachine.modelSignInsCallsMayGoOutAs,
      whatMayLeave.modelSignInsCallsMayGoOutAs,
    );
    expect(back.programsItMayRun, {git, pandoc});
    expect(back.programsItNeeds, {git});
  });

  test('the starting model goes out only as a sign-in the rules name', () {
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: ModelAndSignIn(
          signIn: ModelSignInName.parse('other')!,
          model: opus,
        ),
        programsItMayRun: const [],
        programsItNeeds: const [],
      ),
      isNull,
    );
  });

  test('a trajectory runs only the programs the rules name', () {
    expect(rules.allowsProgram(git), isTrue);
    expect(rules.allowsProgram(pandoc), isTrue);
    expect(rules.allowsProgram(ProgramName.parse('curl')!), isFalse);
  });

  test('a trajectory never needs a program it may not run', () {
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: starting,
        programsItMayRun: [git],
        programsItNeeds: [git, pandoc],
      ),
      isNull,
    );
    // Allowing a program it doesn't need is fine.
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: starting,
        programsItMayRun: [git, pandoc],
        programsItNeeds: const [],
      ),
      isNotNull,
    );
  });

  test('flight rules are read strictly', () {
    final good = rules.toJson().asUncheckedMap();
    final startingJson = {'signIn': 'claude-team', 'model': 'claude-opus-5-5'};
    for (final json in [
      null,
      <String, Object?>{},
      {'whatMayLeaveThisMachine': good['whatMayLeaveThisMachine']},
      {'startingModel': startingJson},
      {...good, 'effort': 'high'},
      {...good, 'startingModel': null},
      {
        ...good,
        'startingModel': {...startingJson, 'effort': 'high'},
      },
      {
        ...good,
        'startingModel': {'signIn': 'claude-team'},
      },
      {
        ...good,
        'startingModel': {...startingJson, 'model': 'claude opus'},
      },
      {
        ...good,
        'startingModel': {...startingJson, 'signIn': 'other'},
      },
      {
        ...good,
        'whatMayLeaveThisMachine': {'programsNetwork': 'noNetworkOfTheirOwn'},
      },
      {...good}..remove('programsItMayRun'),
      {...good}..remove('programsItNeeds'),
      {...good, 'programsItMayRun': 'git'},
      {
        ...good,
        'programsItMayRun': ['git', 'not a program'],
      },
      {
        ...good,
        'programsItNeeds': [null],
      },
      {
        ...good,
        'programsItNeeds': ['git', 'curl'],
      },
    ]) {
      expect(
        () => FlightRules.fromJson(JsonObject.decode(jsonEncode(json))),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
