import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:test/test.dart';

void main() {
  final graph = Origin.parse('https://graph.microsoft.com')!;
  final docs = Origin.parse('https://docs.example.com')!;
  final teams = Origin.parse('https://smba.trafficmanager.net')!;
  final bot = SignIn.parse('teams-bot')!;
  final claudeTeam = ModelSignInName.parse('claude-team')!;
  WebPath path(String raw) => WebPath.parse(raw)!;
  AddressPrefix under(Origin origin, String prefix) =>
      AddressPrefix.of(origin, PathPrefix.parse(prefix)!);

  final driveAbc = under(graph, '/v1.0/drives/abc/');
  final fetchDrive = GrantToFetch(driveAbc, GoesAsSignIn(bot));
  final fetchDocs = GrantToFetch(under(docs, '/'), const GoesAsNobody());
  final toOwnReplies = GrantToMakeWebRequests(
    ToOwnReplyEndpoint.of([teams])!,
    GoesAsSignIn(bot),
  );
  final rules = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    fetchesMayReach: [fetchDrive, fetchDocs],
    webRequestsMayReach: [toOwnReplies],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );

  GrantToFetch? fetch(Origin site, String raw, SignIn? signIn) => rules
      .fetchGrantFor(
        site,
        path(raw),
        signIn,
        leasedNow: const {},
        pooled: const {},
      )
      ?.grant;

  test('what may leave this machine reads back as it was written', () {
    final back = WhatMayLeaveThisMachine.fromJson(
      JsonObject.decode(jsonEncode(rules.toJson())),
    );
    expect(back.modelSignInsCallsMayGoOutAs, rules.modelSignInsCallsMayGoOutAs);
    expect(back.fetchesMayReach, rules.fetchesMayReach);
    expect(back.webRequestsMayReach, rules.webRequestsMayReach);
    expect(back.programsNetwork, ProgramsNetwork.noNetworkOfTheirOwn);
  });

  test('an address is granted with its sign-in, never alone', () {
    expect(fetch(graph, '/v1.0/drives/abc/items', bot), fetchDrive);
    expect(fetch(docs, '/guide', null), fetchDocs);
    // No sign-in is not any sign-in, and a sign-in is not no sign-in.
    expect(fetch(docs, '/guide', bot), isNull);
    expect(fetch(graph, '/v1.0/drives/abc/items', null), isNull);
    expect(
      fetch(graph, '/v1.0/drives/abc/items', SignIn.parse('other-bot')),
      isNull,
    );
    expect(fetch(Origin.parse('https://evil.example')!, '/', null), isNull);
  });

  group('a fetch grant reaches only under its path prefix', () {
    test('everything below the prefix', () {
      expect(fetch(graph, '/v1.0/drives/abc/', bot), fetchDrive);
      expect(
        fetch(graph, '/v1.0/drives/abc/root:/plan.docx:/content', bot),
        fetchDrive,
      );
      expect(
        fetch(graph, r'/v1.0/drives/abc/children?$select=name', bot),
        fetchDrive,
      );
    });

    test('never the node itself, a sibling, or another drive', () {
      expect(fetch(graph, '/v1.0/drives/abc', bot), isNull);
      expect(fetch(graph, '/v1.0/drives/abcdef/items', bot), isNull);
      expect(fetch(graph, '/v1.0/drives/xyz/items', bot), isNull);
      expect(fetch(graph, '/v1.0/me/drive/items', bot), isNull);
    });

    test('a / prefix reaches the whole site', () {
      expect(fetch(docs, '/', null), fetchDocs);
      expect(fetch(docs, '/a/b/c', null), fetchDocs);
    });
  });

  test('a fetch grant never lets a web request through, nor the reverse', () {
    final fetchOnly = WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [claudeTeam],
      fetchesMayReach: [GrantToFetch(under(teams, '/'), GoesAsSignIn(bot))],
      webRequestsMayReach: const [],
      programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
    );
    expect(
      fetchOnly.webRequestsGrantFor(
        teams,
        path('/v3/conversations/x/activities'),
        bot,
        leasedNow: const {},
        pooled: const {},
        replyEndpoint: null,
      ),
      isNull,
    );
    final requestsOnly = WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [claudeTeam],
      fetchesMayReach: const [],
      webRequestsMayReach: [
        GrantToMakeWebRequests(
          ToAddressesUnder(under(teams, '/')),
          GoesAsSignIn(bot),
        ),
      ],
      programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
    );
    expect(
      requestsOnly.fetchGrantFor(
        teams,
        path('/v3/conversations/x/activities'),
        bot,
        leasedNow: const {},
        pooled: const {},
      ),
      isNull,
    );
  });

  group("a grant to the trajectory's own reply endpoint", () {
    final endpoint = under(
      teams,
      '/amer/v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D123/',
    );
    GrantToMakeWebRequests? reply(
      Origin site,
      String raw, {
      required AddressPrefix? replyEndpoint,
      SignIn? signIn,
    }) => rules
        .webRequestsGrantFor(
          site,
          path(raw),
          signIn ?? bot,
          leasedNow: const {},
          pooled: const {},
          replyEndpoint: replyEndpoint,
        )
        ?.grant;

    test('reaches under that endpoint, in either spelling', () {
      expect(
        reply(
          teams,
          '/amer/v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D123/activities',
          replyEndpoint: endpoint,
        ),
        toOwnReplies,
      );
      expect(
        reply(
          teams,
          '/amer/v3/conversations/19:abc%40thread.tacv2;messageid=123/activities',
          replyEndpoint: endpoint,
        ),
        toOwnReplies,
      );
    });

    test('never another conversation', () {
      expect(
        reply(
          teams,
          '/amer/v3/conversations/19%3Aother%40thread.tacv2/activities',
          replyEndpoint: endpoint,
        ),
        isNull,
      );
    });

    test('matches nothing for a trajectory no event started', () {
      expect(
        reply(
          teams,
          '/amer/v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D123/activities',
          replyEndpoint: null,
        ),
        isNull,
      );
    });

    test('matches nothing when the endpoint is on an origin the rules '
        'do not name', () {
      final elsewhere = Origin.parse('https://evil.example')!;
      expect(
        reply(
          elsewhere,
          '/amer/v3/conversations/x/activities',
          replyEndpoint: under(elsewhere, '/amer/v3/conversations/x/'),
        ),
        isNull,
      );
    });

    test('needs at least one origin', () {
      expect(ToOwnReplyEndpoint.of(const []), isNull);
    });
  });

  test('each grant says the prefix it was granted under', () {
    expect(
      rules
          .fetchGrantFor(
            graph,
            path('/v1.0/drives/abc/items'),
            bot,
            leasedNow: const {},
            pooled: const {},
          )
          ?.grantedPathPrefix,
      driveAbc.pathPrefix,
    );
    final fixed = under(teams, '/v3/conversations/x/');
    final toFixed = WhatMayLeaveThisMachine(
      modelSignInsCallsMayGoOutAs: [claudeTeam],
      fetchesMayReach: const [],
      webRequestsMayReach: [
        GrantToMakeWebRequests(ToAddressesUnder(fixed), GoesAsSignIn(bot)),
      ],
      programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
    );
    expect(
      toFixed
          .webRequestsGrantFor(
            teams,
            path('/v3/conversations/x/activities'),
            bot,
            leasedNow: const {},
            pooled: const {},
            replyEndpoint: null,
          )
          ?.grantedPathPrefix,
      fixed.pathPrefix,
    );
    // A reply grant names no prefix of its own: it is the endpoint's.
    final endpoint = under(teams, '/amer/v3/conversations/19%3Aabc/');
    expect(
      rules
          .webRequestsGrantFor(
            teams,
            path('/amer/v3/conversations/19:abc/activities'),
            bot,
            leasedNow: const {},
            pooled: const {},
            replyEndpoint: endpoint,
          )
          ?.grantedPathPrefix,
      endpoint.pathPrefix,
    );
  });

  group('a grant to the bot leased from a pool', () {
    final agents = BotPool.parse('teams-agents')!;
    final github = BotPool.parse('github-agents')!;
    final researcher1 = SignIn.parse('researcher1')!;
    final reviewer2 = SignIn.parse('reviewer2')!;
    final pool = {researcher1, reviewer2};
    final everywhere = under(teams, '/');
    final leasedGrant = GrantToMakeWebRequests(
      ToAddressesUnder(everywhere),
      GoesAsBotLeasedFrom(agents),
    );
    WhatMayLeaveThisMachine allowing(List<GrantToMakeWebRequests> grants) =>
        WhatMayLeaveThisMachine(
          modelSignInsCallsMayGoOutAs: [claudeTeam],
          fetchesMayReach: const [],
          webRequestsMayReach: grants,
          programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
        );
    final leasing = allowing([leasedGrant]);
    GrantToMakeWebRequests? post(
      WhatMayLeaveThisMachine rules,
      Origin site,
      SignIn? signIn, {
      required Map<BotPool, SignIn> leasedNow,
      required Set<SignIn> pooled,
    }) => rules
        .webRequestsGrantFor(
          site,
          path('/v3/conversations/x/activities'),
          signIn,
          leasedNow: leasedNow,
          pooled: pooled,
          replyEndpoint: null,
        )
        ?.grant;

    test('matches the bot leased from that pool, and only it', () {
      expect(
        post(
          leasing,
          teams,
          researcher1,
          leasedNow: {agents: researcher1},
          pooled: pool,
        ),
        leasedGrant,
      );
      // Another bot of the same pool, leased to another trajectory.
      expect(
        post(
          leasing,
          teams,
          reviewer2,
          leasedNow: {agents: researcher1},
          pooled: pool,
        ),
        isNull,
      );
      expect(
        post(
          leasing,
          docs,
          researcher1,
          leasedNow: {agents: researcher1},
          pooled: pool,
        ),
        isNull,
      );
    });

    test('matches nothing once the lease ends', () {
      expect(
        post(leasing, teams, researcher1, leasedNow: const {}, pooled: pool),
        isNull,
      );
    });

    test('matches nothing for a bot leased from another pool', () {
      expect(
        post(
          leasing,
          teams,
          researcher1,
          leasedNow: {github: researcher1},
          pooled: pool,
        ),
        isNull,
      );
    });

    test('never matches a request under no sign-in', () {
      expect(
        post(
          leasing,
          teams,
          null,
          leasedNow: {agents: researcher1},
          pooled: pool,
        ),
        isNull,
      );
    });

    test('a pooled bot is never granted by name', () {
      final byNameGrant = GrantToMakeWebRequests(
        ToAddressesUnder(everywhere),
        GoesAsSignIn(researcher1),
      );
      final byName = allowing([byNameGrant]);
      // researcher1 is leased to another trajectory: the grant by name
      // must not let this one post as it.
      expect(
        post(byName, teams, researcher1, leasedNow: const {}, pooled: pool),
        isNull,
      );
      // Out of every pool, the same grant holds.
      expect(
        post(byName, teams, researcher1, leasedNow: const {}, pooled: const {}),
        byNameGrant,
      );
    });

    test('a pooled bot this trajectory leases goes by the leased grant, '
        'even beside a grant by name', () {
      final both = allowing([
        leasedGrant,
        GrantToMakeWebRequests(
          ToAddressesUnder(everywhere),
          GoesAsSignIn(researcher1),
        ),
      ]);
      expect(
        post(
          both,
          teams,
          researcher1,
          leasedNow: {agents: researcher1},
          pooled: pool,
        ),
        leasedGrant,
      );
    });

    test('reads back as it was written', () {
      final back = WhatMayLeaveThisMachine.fromJson(
        JsonObject.decode(jsonEncode(leasing.toJson())),
      );
      expect(back.webRequestsMayReach, {leasedGrant});
    });
  });

  test('a model call goes out only as a sign-in the rules name', () {
    expect(rules.allowsModelCall(claudeTeam), isTrue);
    expect(rules.allowsModelCall(ModelSignInName.parse('other')!), isFalse);
  });

  test('a grant under no sign-in is not a grant under a sign-in', () {
    // By ==, not only by hash, so a set that compared grants by address
    // alone would still be caught.
    expect(const GoesAsNobody() == GoesAsSignIn(bot), isFalse);
    expect(GoesAsSignIn(bot) == const GoesAsNobody(), isFalse);
    final docsRoot = under(docs, '/');
    expect(
      GrantToFetch(docsRoot, const GoesAsNobody()) ==
          GrantToFetch(docsRoot, GoesAsSignIn(bot)),
      isFalse,
    );
    expect(
      GrantToFetch(docsRoot, GoesAsSignIn(bot)) ==
          GrantToFetch(docsRoot, GoesAsSignIn(SignIn.parse('other-bot')!)),
      isFalse,
    );
  });

  test('what may leave this machine is read strictly', () {
    final good = rules.toJson().asUncheckedMap();
    final from = {'origin': 'https://docs.example.com', 'pathPrefix': '/'};
    final nobody = {'kind': 'nobody'};
    final fetchGrant = {'from': from, 'goesAs': nobody};
    final requestGrant = {
      'to': {'kind': 'addressesUnder', 'prefix': from},
      'goesAs': nobody,
    };
    for (final json in [
      null,
      <String, Object?>{},
      {...good, 'mayWrite': true},
      {...good, 'programsNetwork': 'visorUp'},
      {...good, 'modelSignInsCallsMayGoOutAs': 'claude-team'},
      {
        ...good,
        'modelSignInsCallsMayGoOutAs': ['Claude Team'],
      },
      {
        ...good,
        'modelSignInsCallsMayGoOutAs': [null],
      },
      // 0.3.0's single list: a fresh logbook, never read as either.
      {...good, 'sitesTheWebDriverMayReach': const <Object?>[]},
      for (final bad in <Object?>[
        {...fetchGrant, 'goesAs': null},
        {...fetchGrant, 'goesAs': 'nobody'},
        {
          ...fetchGrant,
          'goesAs': {'kind': 'anyone'},
        },
        {
          ...fetchGrant,
          'goesAs': {'kind': 'nobody', 'signIn': 'teams-bot'},
        },
        {
          ...fetchGrant,
          'goesAs': {'kind': 'signIn'},
        },
        {
          ...fetchGrant,
          'goesAs': {'kind': 'signIn', 'signIn': 'teams-bot', 'as': 'x'},
        },
        {
          ...fetchGrant,
          'goesAs': {'kind': 'botLeasedFrom'},
        },
        {
          ...fetchGrant,
          'goesAs': {'kind': 'botLeasedFrom', 'pool': 'Teams Agents'},
        },
        {
          ...fetchGrant,
          'goesAs': {
            'kind': 'botLeasedFrom',
            'pool': 'teams-agents',
            'signIn': 'researcher1',
          },
        },
        {...fetchGrant, 'from': 'https://docs.example.com'},
        {...fetchGrant, 'from': null},
        {
          ...fetchGrant,
          'from': {...from, 'pathPrefix': '/guide'},
        },
        {
          ...fetchGrant,
          'from': {...from, 'pathPrefix': '/guide?x=1/'},
        },
        {
          ...fetchGrant,
          'from': {...from, 'pathPrefix': '/a/%2e%2e/'},
        },
        {
          ...fetchGrant,
          'from': {'origin': 'https://docs.example.com'},
        },
        {
          ...fetchGrant,
          'from': {...from, 'method': 'GET'},
        },
        {
          ...fetchGrant,
          'from': {...from, 'origin': 'https://docs.example.com/path'},
        },
        {...fetchGrant, 'path': '/'},
      ])
        {
          ...good,
          'fetchesMayReach': [bad],
        },
      for (final bad in <Object?>[
        {...requestGrant, 'to': null},
        {
          ...requestGrant,
          'to': {'kind': 'anywhere'},
        },
        {
          ...requestGrant,
          'to': {'kind': 'addressesUnder'},
        },
        {
          ...requestGrant,
          'to': {
            'kind': 'addressesUnder',
            'prefix': from,
            'onOneOf': const <Object?>[],
          },
        },
        {
          ...requestGrant,
          'to': {'kind': 'ownReplyEndpoint'},
        },
        {
          ...requestGrant,
          'to': {'kind': 'ownReplyEndpoint', 'onOneOf': const <Object?>[]},
        },
        {
          ...requestGrant,
          'to': {
            'kind': 'ownReplyEndpoint',
            'onOneOf': ['not an origin'],
          },
        },
        {
          ...requestGrant,
          'to': {
            'kind': 'ownReplyEndpoint',
            'onOneOf': ['https://smba.trafficmanager.net'],
            'prefix': from,
          },
        },
        // A fetch grant's shape is not a web-request grant.
        fetchGrant,
      ])
        {
          ...good,
          'webRequestsMayReach': [bad],
        },
    ]) {
      expect(
        () => WhatMayLeaveThisMachine.fromJson(
          JsonObject.decode(jsonEncode(json)),
        ),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
