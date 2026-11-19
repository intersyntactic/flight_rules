import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';

import 'read_strictly.dart';
import 'what_may_leave_this_machine.dart';

/// A trajectory's flight rules: what may leave this machine, and the model
/// its loop starts on.
///
/// [startingModel]'s sign-in is always one [whatMayLeaveThisMachine] lets a
/// model call go out as, so a trajectory is never started on a model whose
/// first call would be refused.
final class FlightRules {
  const FlightRules._(this.whatMayLeaveThisMachine, this.startingModel);

  /// The rules, or null when [startingModel]'s sign-in is not one
  /// [whatMayLeaveThisMachine] lets a model call go out as.
  static FlightRules? of({
    required WhatMayLeaveThisMachine whatMayLeaveThisMachine,
    required ModelAndSignIn startingModel,
  }) => whatMayLeaveThisMachine.allowsModelCall(startingModel.signIn)
      ? FlightRules._(whatMayLeaveThisMachine, startingModel)
      : null;

  /// [json] read back, strictly, as [WhatMayLeaveThisMachine.fromJson]
  /// reads its parts. Both keys are required.
  static FlightRules fromJson(JsonObject json, [String field = 'flightRules']) {
    exactly(field, json, const {'whatMayLeaveThisMachine', 'startingModel'});
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
    return of(
          whatMayLeaveThisMachine: whatMayLeaveThisMachine,
          startingModel: startingModel,
        ) ??
        (throw FormatException(
          '$field.startingModel.signIn: not one model calls may go out as: '
          '${startingModel.signIn}',
        ));
  }

  final WhatMayLeaveThisMachine whatMayLeaveThisMachine;

  /// The model the trajectory's loop starts on, and the sign-in its calls
  /// go out as.
  final ModelAndSignIn startingModel;

  JsonObject toJson() => JsonObject.of({
    'whatMayLeaveThisMachine': whatMayLeaveThisMachine.toJson(),
    'startingModel': encodeModelAndSignIn(startingModel),
  });
}
