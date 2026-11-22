## 0.4.0

- **Breaking:** `sitesTheWebDriverMayReach` is split in two, so a grant to make web requests never lets a fetch through, and the reverse. `fetchesMayReach` holds `GrantToFetch(from, goesAs)`, decided by `fetchGrantFor(site, path, signIn, leasedNow:, pooled:)`. `webRequestsMayReach` holds `GrantToMakeWebRequests(to, goesAs)`, decided by `webRequestsGrantFor(site, path, signIn, leasedNow:, pooled:, replyEndpoint:)`, once for each request a tool builds. `SiteAndSignIn` and `grantFor` are removed, and 0.3.0's rules are not read.
- Every grant reaches only under an is_effects `AddressPrefix`: an origin and a `PathPrefix`, compared by canonical segments, so a path reaches under a prefix only when it goes deeper than it. `/` is the whole site, written on purpose.
- `ToOwnReplyEndpoint.of(onOneOf)`: a web-request grant to wherever replies to the event that started the trajectory go, on one of the origins named. It matches nothing for a trajectory no event started, and `of` returns null for an empty list. A fixed prefix goes in `ToAddressesUnder(prefix)`.
- **Breaking:** `FlightRules` gains two required keys: `programsItMayRun`, the programs a trajectory may run (`allowsProgram`), and `programsItNeeds`, the ones a machine must have for it to start. `FlightRules.of` returns null, and `fromJson` throws, when a needed program isn't one it may run.
- Depends on is_effects ^0.13.0.

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
