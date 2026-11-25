import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:is_tools_api/is_tools_api.dart'
    show Fetch, Input, OneActionTool, ToolName;
import 'package:test/test.dart';

void main() {
  final claudeTeam = ModelSignInName.parse('claude-team')!;
  final opus = ModelName.parse('claude-opus-5-5')!;
  final git = ProgramName.parse('git')!;
  final pandoc = ProgramName.parse('pandoc')!;
  final graph = Origin.parse('https://graph.microsoft.com')!;
  final bot = SignIn.parse('teams-bot')!;
  final whatMayLeave = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    fetchesMayReach: [
      GrantToFetch(
        FromAddressesUnder(
          AddressPrefix.of(graph, PathPrefix.parse('/v1.0/drives/d/items/F/')!),
        ),
        GoesAsSignIn(bot),
      ),
    ],
    webRequestsMayReach: const [],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );
  final starting = ModelAndSignIn(signIn: claudeTeam, model: opus);
  OneActionTool tool(
    String name, {
    String path = '/v1.0/drives/d/items/F/children',
    SignIn? signIn,
  }) => OneActionTool.of(
    name: ToolName.of(name),
    description: 'Lists the case folder.',
    input: Input.none,
    action: Fetch(graph, WebPath.parse(path)!, signIn ?? bot),
  );
  final readReport = tool('read_report', path: '/v1.0/drives/d/items/F/report');
  final listFolder = tool('list_folder');
  final rules = FlightRules.of(
    whatMayLeaveThisMachine: whatMayLeave,
    startingModel: starting,
    programsItMayRun: [git, pandoc],
    programsItNeeds: [git],
    givenTools: [readReport, listFolder],
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
    expect(back.givenTools.keys, [
      ToolName.of('read_report'),
      ToolName.of('list_folder'),
    ]);
    expect(
      jsonEncode(back.givenTools[ToolName.of('read_report')]!.toJson()),
      jsonEncode(readReport.toJson()),
    );
  });

  test('the given tools keep the order the rules list them in', () {
    final reversed = FlightRules.of(
      whatMayLeaveThisMachine: whatMayLeave,
      startingModel: starting,
      programsItMayRun: const [],
      programsItNeeds: const [],
      givenTools: [listFolder, readReport],
    )!;
    expect(reversed.givenTools.keys, [
      ToolName.of('list_folder'),
      ToolName.of('read_report'),
    ]);
    expect(
      FlightRules.fromJson(JsonObject.decode(jsonEncode(reversed.toJson())))
          .givenTools
          .keys,
      [ToolName.of('list_folder'), ToolName.of('read_report')],
    );
  });

  test('no two given tools share a name', () {
    expect(
      FlightRules.of(
        whatMayLeaveThisMachine: whatMayLeave,
        startingModel: starting,
        programsItMayRun: const [],
        programsItNeeds: const [],
        givenTools: [readReport, tool('read_report')],
      ),
      isNull,
    );
    expect(
      () => rules.givenTools[ToolName.of('other')] = readReport,
      throwsA(anything),
    );
  });

  test('rules naming a given tool outside a tool name are not read', () {
    final written = jsonEncode(rules.toJson());
    expect(written, contains('"read_report"'));
    expect(
      () => FlightRules.fromJson(
        JsonObject.decode(
          written.replaceFirst('"read_report"', '"read report"'),
        ),
      ),
      throwsFormatException,
    );
  });

  test('no given tool proposes what no grant could let out', () {
    FlightRules? given(OneActionTool tool) => FlightRules.of(
      whatMayLeaveThisMachine: whatMayLeave,
      startingModel: starting,
      programsItMayRun: const [],
      programsItNeeds: const [],
      givenTools: [listFolder, tool],
    );
    expect(given(readReport), isNotNull);
    expect(given(tool('outside', path: '/v1.0/drives/d/items/G')), isNull);
    expect(given(tool('as_other', signIn: SignIn.parse('other-bot')!)), isNull);
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
          {...readReport.toJson().asUncheckedMap(), 'steps': <Object?>[]},
        ],
      },
      {
        ...good,
        'givenTools': [
          {...readReport.toJson().asUncheckedMap(), 'level': 0},
        ],
      },
      {
        ...good,
        'givenTools': [readReport.toJson(), readReport.toJson()],
      },
      {
        ...good,
        'givenTools': [
          tool('outside', path: '/v1.0/drives/d/items/G').toJson(),
        ],
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
