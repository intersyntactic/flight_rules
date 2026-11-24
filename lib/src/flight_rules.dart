import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_tools_api/is_tools_api.dart' show OneActionTool;

import 'read_strictly.dart';
import 'what_may_leave_this_machine.dart';

/// A trajectory's flight rules: what may leave this machine, the model its
/// loop starts on, the programs it may run and needs, and the tools it is
/// given.
///
/// [startingModel]'s sign-in is always one [whatMayLeaveThisMachine] lets a
/// model call go out as, so a trajectory is never started on a model whose
/// first call would be refused; every program in [programsItNeeds] is one
/// in [programsItMayRun], so a trajectory never needs a program it could
/// not run; and no two of [givenTools] share a name, so a model's call by
/// name reaches exactly one.
final class FlightRules {
  const FlightRules._(
    this.whatMayLeaveThisMachine,
    this.startingModel,
    this.programsItMayRun,
    this.programsItNeeds,
    this.givenTools,
  );

  /// The rules, or null when [startingModel]'s sign-in is not one
  /// [whatMayLeaveThisMachine] lets a model call go out as, when a program
  /// in [programsItNeeds] is not in [programsItMayRun], or when two of
  /// [givenTools] share a name.
  static FlightRules? of({
    required WhatMayLeaveThisMachine whatMayLeaveThisMachine,
    required ModelAndSignIn startingModel,
    required Iterable<ProgramName> programsItMayRun,
    required Iterable<ProgramName> programsItNeeds,
    required Iterable<OneActionTool> givenTools,
  }) {
    final mayRun = Set<ProgramName>.unmodifiable(programsItMayRun);
    final needs = Set<ProgramName>.unmodifiable(programsItNeeds);
    final (tools, sharedName) = _byName(givenTools);
    return sharedName == null &&
            _whyNot(whatMayLeaveThisMachine, startingModel, mayRun, needs) ==
                null
        ? FlightRules._(
            whatMayLeaveThisMachine,
            startingModel,
            mayRun,
            needs,
            tools,
          )
        : null;
  }

  /// Which part breaks the rules [of] holds them to, and how, with the
  /// part's name relative to the rules; null when none does.
  static String? _whyNot(
    WhatMayLeaveThisMachine whatMayLeaveThisMachine,
    ModelAndSignIn startingModel,
    Set<ProgramName> mayRun,
    Set<ProgramName> needs,
  ) {
    if (!whatMayLeaveThisMachine.allowsModelCall(startingModel.signIn)) {
      return 'startingModel.signIn: not one model calls may go out as: '
          '${startingModel.signIn}';
    }
    final notAllowed = needs.difference(mayRun);
    if (notAllowed.isNotEmpty) {
      return 'programsItNeeds: not in programsItMayRun: '
          '${notAllowed.join(', ')}';
    }
    return null;
  }

  /// [tools] by name, in the order given, and the first name two of them
  /// share, or null when none do.
  static (Map<String, OneActionTool>, String?) _byName(
    Iterable<OneActionTool> tools,
  ) {
    final byName = <String, OneActionTool>{};
    for (final tool in tools) {
      if (byName.containsKey(tool.name)) return (const {}, tool.name);
      byName[tool.name] = tool;
    }
    return (Map.unmodifiable(byName), null);
  }

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts. Every key is required.
  static FlightRules fromJson(JsonObject json, [String field = 'flightRules']) {
    exactly(field, json, const {
      'whatMayLeaveThisMachine',
      'startingModel',
      'programsItMayRun',
      'programsItNeeds',
      'givenTools',
    });
    final whatMayLeaveThisMachine = WhatMayLeaveThisMachine.fromJson(
      json.object('whatMayLeaveThisMachine'),
      '$field.whatMayLeaveThisMachine',
    );
    exactly('$field.startingModel', json.object('startingModel'), const {
      'signIn',
      'model',
    });
    final startingModel = decodeModelAndSignIn(
      json.raw('startingModel'),
      '$field.startingModel',
    );
    List<ProgramName> programs(String key) => [
      for (final (i, name) in json.list(key).indexed)
        decodeProgramName(name, '$field.$key[$i]'),
    ];
    final mayRun = Set<ProgramName>.unmodifiable(programs('programsItMayRun'));
    final needs = Set<ProgramName>.unmodifiable(programs('programsItNeeds'));
    final why = _whyNot(whatMayLeaveThisMachine, startingModel, mayRun, needs);
    if (why != null) throw FormatException('$field.$why');
    final (tools, sharedName) = _byName([
      for (final (i, tool) in json.list('givenTools').indexed)
        switch (JsonObject.parse(tool)) {
              final object? => OneActionTool.parse(object),
              null => null,
            } ??
            (throw FormatException(
              '$field.givenTools[$i]: not a one-action tool',
            )),
    ]);
    if (sharedName != null) {
      throw FormatException(
        '$field.givenTools: two tools are named $sharedName',
      );
    }
    return FlightRules._(
      whatMayLeaveThisMachine,
      startingModel,
      mayRun,
      needs,
      tools,
    );
  }

  final WhatMayLeaveThisMachine whatMayLeaveThisMachine;

  /// The model the trajectory's loop starts on, and the sign-in its calls
  /// go out as.
  final ModelAndSignIn startingModel;

  /// The programs the trajectory may run, by name. A program the machine
  /// lacks may still be here.
  final Set<ProgramName> programsItMayRun;

  /// The programs the trajectory needs: a machine lacking one of them can't
  /// start it.
  final Set<ProgramName> programsItNeeds;

  /// The tools the trajectory is given, by name, in the order the rules
  /// list them. A tool adds no reach: the airlock decides each action it
  /// proposes against the rest of these rules. A tool's bound values, such
  /// as a folder's id, fill in its arguments and limit nothing; only
  /// [whatMayLeaveThisMachine] limits where its actions reach.
  final Map<String, OneActionTool> givenTools;

  /// Whether the trajectory may run [program].
  bool allowsProgram(ProgramName program) => programsItMayRun.contains(program);

  JsonObject toJson() => JsonObject.of({
    'whatMayLeaveThisMachine': whatMayLeaveThisMachine.toJson(),
    'startingModel': encodeModelAndSignIn(startingModel),
    'programsItMayRun': [
      for (final program in programsItMayRun) encodeProgramName(program),
    ],
    'programsItNeeds': [
      for (final program in programsItNeeds) encodeProgramName(program),
    ],
    'givenTools': [for (final tool in givenTools.values) tool.toJson()],
  });
}
