import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:is_tools_api/is_tools_api.dart'
    show
        OneActionTool,
        Input,
        Field,
        ActionName,
        InputReference,
        BoundReference,
        Literal;
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
  OneActionTool tool(String name, String action) => OneActionTool.of(
    name: name,
    description: 'Reads from the case folder.',
    input: Input.field(Field('name', .string(minLength: 1))),
    bound: {'folder': Literal.text('01abc')},
    action: ActionName.of(action),
    arguments: const [BoundReference('folder'), InputReference('name')],
  );
  final readDocument = tool('read_document', 'readDocument');
  final listFolder = tool('list_folder', 'listFolder');
  final rules = FlightRules.of(
    whatMayLeaveThisMachine: whatMayLeave,
    startingModel: starting,
    programsItMayRun: [git, pandoc],
    programsItNeeds: [git],
    givenTools: [readDocument, listFolder],
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
    expect(back.givenTools.keys, ['read_document', 'list_folder']);
    expect(
      jsonEncode(back.givenTools['read_document']!.toJson()),
      jsonEncode(readDocument.toJson()),
    );
  });

  test('the given tools keep the order the rules list them in', () {
    final reversed = FlightRules.of(
      whatMayLeaveThisMachine: whatMayLeave,
      startingModel: starting,
      programsItMayRun: const [],
      programsItNeeds: const [],
      givenTools: [listFolder, readDocument],
    )!;
    expect(reversed.givenTools.keys, ['list_folder', 'read_document']);
    expect(
      FlightRules.fromJson(JsonObject.decode(jsonEncode(reversed.toJson())))
          .givenTools
          .keys,
      ['list_folder', 'read_document'],
    );
  });

  test('no two given tools share a name', () {
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: starting,
        programsItMayRun: const [],
        programsItNeeds: const [],
        givenTools: [readDocument, tool('read_document', 'listFolder')],
      ),
      isNull,
    );
    expect(() => rules.givenTools['other'] = readDocument, throwsA(anything));
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
        givenTools: const [],
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
        givenTools: const [],
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
        givenTools: const [],
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
      {...good}..remove('givenTools'),
      {...good, 'givenTools': null},
      {
        ...good,
        'givenTools': [null],
      },
      {
        ...good,
        'givenTools': [
          {...readDocument.toJson().asUncheckedMap(), 'steps': <Object?>[]},
        ],
      },
      {
        ...good,
        'givenTools': [
          {...readDocument.toJson().asUncheckedMap(), 'level': 0},
        ],
      },
      {
        ...good,
        'givenTools': [readDocument.toJson(), readDocument.toJson()],
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
