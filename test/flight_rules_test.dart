import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:test/test.dart';

void main() {
  final claudeTeam = ModelSignInName.parse('claude-team')!;
  final opus = ModelName.parse('claude-opus-5-5')!;
  final whatMayLeave = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    sitesTheWebDriverMayReach: const [],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );
  final rules = FlightRules.of(
    whatMayLeaveThisMachine: whatMayLeave,
    startingModel: ModelAndSignIn(signIn: claudeTeam, model: opus),
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
  });

  test('the starting model goes out only as a sign-in the rules name', () {
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: ModelAndSignIn(
          signIn: ModelSignInName.parse('other')!,
          model: opus,
        ),
      ),
      isNull,
    );
  });

  test('flight rules are read strictly', () {
    final good = rules.toJson().asUncheckedMap();
    final starting = {'signIn': 'claude-team', 'model': 'claude-opus-5-5'};
    for (final json in [
      null,
      <String, Object?>{},
      {'whatMayLeaveThisMachine': good['whatMayLeaveThisMachine']},
      {'startingModel': starting},
      {...good, 'effort': 'high'},
      {...good, 'startingModel': null},
      {
        ...good,
        'startingModel': {...starting, 'effort': 'high'},
      },
      {
        ...good,
        'startingModel': {'signIn': 'claude-team'},
      },
      {
        ...good,
        'startingModel': {...starting, 'model': 'claude opus'},
      },
      {
        ...good,
        'startingModel': {...starting, 'signIn': 'other'},
      },
      {
        ...good,
        'whatMayLeaveThisMachine': {'programsNetwork': 'noNetworkOfTheirOwn'},
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
