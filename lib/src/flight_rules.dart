import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';

import 'read_strictly.dart';
import 'what_may_leave_this_machine.dart';

/// A trajectory's flight rules: what may leave this machine, the model its
/// loop starts on, and the programs it may run and needs.
///
/// [startingModel]'s sign-in is always one [whatMayLeaveThisMachine] lets a
/// model call go out as, so a trajectory is never started on a model whose
/// first call would be refused; and every program in [programsItNeeds] is
/// one in [programsItMayRun], so a trajectory never needs a program it
/// could not run.
final class FlightRules {
  const FlightRules._(
    this.whatMayLeaveThisMachine,
    this.startingModel,
    this.programsItMayRun,
    this.programsItNeeds,
  );

  /// The rules, or null when [startingModel]'s sign-in is not one
  /// [whatMayLeaveThisMachine] lets a model call go out as, or when a
  /// program in [programsItNeeds] is not in [programsItMayRun].
  static FlightRules? of({
    required WhatMayLeaveThisMachine whatMayLeaveThisMachine,
    required ModelAndSignIn startingModel,
    required Iterable<ProgramName> programsItMayRun,
    required Iterable<ProgramName> programsItNeeds,
  }) {
    final mayRun = Set<ProgramName>.unmodifiable(programsItMayRun);
    final needs = Set<ProgramName>.unmodifiable(programsItNeeds);
    return _whyNot(whatMayLeaveThisMachine, startingModel, mayRun, needs) ==
            null
        ? FlightRules._(whatMayLeaveThisMachine, startingModel, mayRun, needs)
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

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts. Every key is required.
  static FlightRules fromJson(JsonObject json, [String field = 'flightRules']) {
    exactly(field, json, const {
      'whatMayLeaveThisMachine',
      'startingModel',
      'programsItMayRun',
      'programsItNeeds',
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
    return FlightRules._(whatMayLeaveThisMachine, startingModel, mayRun, needs);
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
  });
}
