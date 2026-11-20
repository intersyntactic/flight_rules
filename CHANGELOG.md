## 0.3.0

- `GoesAsBotLeasedFrom(BotPool)`: a grant to the sign-in of whichever bot the trajectory leases from that pool, matching nothing without a lease. On the wire, `{"kind": "botLeasedFrom", "pool": …}`.
- `WhatMayLeaveThisMachine.grantFor(site, signIn, leasedNow:, pooled:)` returns the grant that allows a web request, or null, and replaces `allowsWebRequest`, which could not say which lease a decision relied on. A sign-in in `pooled` is never granted by name: only a current lease lets a trajectory go as a pooled bot.
- Depends on is_effects ^0.12.0.

## 0.2.0

- `FlightRules`: `whatMayLeaveThisMachine` and a required `startingModel` (an is_effects `ModelAndSignIn`) whose sign-in must be one model calls may go out as. A trajectory's rules copy is now a `FlightRules`.
- Depends on is_effects ^0.11.0.

## 0.1.2

- Depends on is_effects ^0.9.0.

## 0.1.1

- Depends on is_effects ^0.8.0.

## 0.1.0

- `WhatMayLeaveThisMachine`, `SiteAndSignIn`, `GoesAs`, `ProgramsNetwork`, read and written with checked_json.
