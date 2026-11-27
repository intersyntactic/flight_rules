# The rules table: per-person, per-conversation permissions

Status: draft for review by Nick and airlock-api-b2. Nothing is built yet.

## What Nick asked for (27 Nov 2026)

- Call settings **bind**. The model, sign-in and effort a person chooses are
  what the airlock sends every call with. The loop can only ask for a change.
- Rules for messages between missions **differ per mission**.
- The most general shape. A simple default, with permissions that can be
  decided down to a fine grain: different people can have different settings
  in different situations.
- A "situation" is **a conversation or channel**.
- One human on Slack and on Teams is **one person**.
- Custom rules are **rows in a table**.

## The idea in one paragraph

The rules become a table. Each row grants one thing, to someone, somewhere,
perhaps after something else has happened first. Rows only ever add: no row
takes away what another gave. So an action is allowed exactly when some row
covers it, and nothing has to decide which row wins. When the airlock allows
something, it records the row that allowed it, so the logbook can always
answer "why was this allowed, and for whom?". This is how web requests already
work: `webRequestsGrantFor` returns the grant, not a yes.

## The columns

| Column | Holds | Cases |
|---|---|---|
| who | whose action the row covers | `anyone` (any named person in the conversation), or a person from the people list |
| where | which conversation | `anywhere`, a mission (a channel), or one thread in it |
| allows | what the row lets them do | choose call settings, or send to another mission |
| needs first | what must happen first | nothing, an okay from someone, or a Projection |

Each column is a closed set of cases (a sealed class), so a row the code
can't enforce can't be written. A new kind of permission is a code change,
because the airlock can only enforce what it has code to check.

### who

- `Anyone`: any **named** person in the conversation. An event that names no
  person (`TranslatedEvent.from` is null) is covered by no row at all, not
  even `Anyone`. It gets the trajectory's `startingModel` and can't choose
  anything else.
- `Person(name)`: a person from the people list, under any of their accounts.

There is no row keyed by a bare `ActorId`: Nick wants one person, not one per
account. Roles (such as a mission commander) wait for Nick's ruling on loop-launcher's
task 57: whether the commander is a fixed role per mission, and who
appoints it.

### where

A mission is a channel (or a chat with no threads), and each thread in it is
one trajectory, as the docking station's README puts it.

- `Anywhere`
- `InMission(AddressInExternalSystem)`: any thread of that channel.
- `InThread(AddressInExternalSystem)`: one thread.

The docking station's rules file is already a table with only this column:
`default` is an `Anywhere` row, and `byMissionAddress` holds `InMission`
rows. This design adds the other three columns. The docking station
resolves `where` when it admits a trajectory: it copies the rows whose
`where` covers that thread into the trajectory's `FlightRules`. So the
airlock still sees only its own trajectory's rules, and the admission
records exactly those rows, as it records the rest of the rules today.

### allows

- `ChooseCallSettings(signIn, models, effortUpTo)`: the person may choose
  that sign-in, with any of `models` (or any model), at an effort up to
  `effortUpTo` (or any). Effort compares by `Effort.rank`, so a level this
  code doesn't know ranks above every limit and is refused. These rows
  replace `modelSignInsCallsMayGoOutAs`: the sign-ins calls may go out as
  are the ones the rows name.
- `SendToMission(to)`: a message may cross to the mission `to`, or to any
  mission. Who sends it is the open commander question.

### needs first

- `Nothing`
- `OkayFrom(who)`: someone `who` covers, in the sending conversation, okays
  that exact text going out. This is loop-launcher's "decided like a
  declassification".
- `Projection`: the text is drawn up by a Projection, not relayed.

Call-settings rows take only `Nothing`: the person choosing is the one
acting.

## The people list

```
people:
  hart: [slack:T01/U9, teams:acme/4f2…]
```

A person's name, with every account that is theirs. The list lives in the
rules file. Only whoever edits that file can link two accounts, because
linking an account to `hart` hands it Hart's permissions. An account may
appear under at most one person. A row naming a person not on the list
makes the file unreadable, as an unknown program does today.

The types, a `PersonName` and the list, belong beside `ActorId` in is_shapes,
whose doc already plans "a table beside them" for joining accounts. That
is a change in the shapes repo, so it's a brief to that repo's session, not
work done from here.

## Binding call settings

1. A person chooses settings in the conversation (the More options dialog,
   or the agent proposing "switch to Opus" and the person accepting). The
   docking station turns that into an event whose `from` is the person's
   `ActorId`, read from what they wrote, never from the loop.
2. The airlock decides it against the trajectory's rows. It finds the person
   for that account, then a `ChooseCallSettings` row that covers them.
   Allowed, it writes a settings entry: the settings, who chose them, and the
   row that allowed it. Refused, nothing changes.
3. Every model call takes its sign-in, model and effort from the newest
   settings entry, or from `startingModel` when there is none. The loop no
   longer sends them (airlock-api's breaking `ModelCall` change).
4. At each call, `WhatMayLeaveThisMachine.allowsModelCall(signIn) → bool`
   becomes `callSettingsGrantFor(newestSettings, chooser) → row?`. It
   returns the row that still allows those settings for that person, or
   null. So a call can never go out on settings that no row allows, and the
   record of each call names its row.

## Examples

```
rules:
  - who: anyone   where: anywhere
    allows: choose claude-team, models: [claude-sonnet-5-5], effort up to high
  - who: hart     where: anywhere
    allows: choose claude-team, any model, any effort
  - who: hart     where: in mission teams:19:finance@thread.v2
    allows: choose openai-team, models: [gpt-5]
  - who: anyone   where: in mission teams:19:legal@thread.v2
    allows: send to mission teams:19:finance@thread.v2
    needs first: okay from hart
```

## What changes, and who does it

| Where | Change | Session |
|---|---|---|
| shapes | `PersonName`, the people list | the shapes session (none listed as running on 27 Nov) |
| flight_rules | the row types, `callSettingsGrantFor`; rows replace `modelSignInsCallsMayGoOutAs` | flight-rules-55 |
| airlock_api, airlock | the settings entry, binding, `ModelCall` without model and sign-in | airlock-api-b2, airlock-d5 |
| docking_station | the rules file's people list and rows; resolving `where` at admission | docking-station-97 |
| infra | a new rules-file format, so an infra window and a fresh logbook (the one-shape rule) | infra-95 |

All of these are breaking, so they should ship as one batch, in one window.

## Open

1. Roles: is the commander a fixed role per mission, and who appoints it?
   (Nick, via loop-launcher's task 57.) Until then, crossing rows can name
   only `anyone` or a person.
2. Is `where` needed in `FlightRules` at all, once the docking station
   resolves it? This draft says no: rows reach the airlock with `where`
   already applied.
3. Do fetch and web-request grants move into the table too? They have no
   `who`, because a tool's fetch is the agent's, not a person's. This draft
   leaves them where they are.
