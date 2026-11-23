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
  final fetchDrive = GrantToFetch(
    FromAddressesUnder(driveAbc),
    GoesAsSignIn(bot),
  );
  final fetchDocs = GrantToFetch(
    FromAddressesUnder(under(docs, '/')),
    const GoesAsNobody(),
  );
  final folderGrant = GrantToFetch(
    FromGraphFolder(GraphId.parse('b!d_1')!, GraphId.parse('01F')!),
    GoesAsSignIn(bot),
  );
  final toOwnReplies = GrantToMakeWebRequests(
    ToOwnReplyEndpoint.of([teams])!,
    GoesAsSignIn(bot),
  );
  final rules = WhatMayLeaveThisMachine(
    modelSignInsCallsMayGoOutAs: [claudeTeam],
    fetchesMayReach: [fetchDrive, fetchDocs, folderGrant],
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
      fetchesMayReach: [
        GrantToFetch(FromAddressesUnder(under(teams, '/')), GoesAsSignIn(bot)),
      ],
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

  group('the sign-in a reply goes as', () {
    final agents = BotPool.parse('teams-agents')!;
    final researcher1 = SignIn.parse('researcher1')!;
    final endpoint = under(teams, '/amer/v3/conversations/19%3Aabc/');
    WhatMayLeaveThisMachine replyingAs(List<GoesAs> goesAs) =>
        WhatMayLeaveThisMachine(
          modelSignInsCallsMayGoOutAs: [claudeTeam],
          fetchesMayReach: const [],
          webRequestsMayReach: [
            for (final as in goesAs)
              GrantToMakeWebRequests(ToOwnReplyEndpoint.of([teams])!, as),
          ],
          programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
        );

    /// The chosen sign-in, after checking the airlock grants a reply as it.
    SignIn? chosen(
      WhatMayLeaveThisMachine rules, {
      AddressPrefix? at,
      Map<BotPool, SignIn> leasedNow = const {},
      Set<SignIn> pooled = const {},
    }) {
      final replyEndpoint = at ?? endpoint;
      final signIn = rules.signInForReply(
        replyEndpoint: replyEndpoint,
        leasedNow: leasedNow,
        pooled: pooled,
      );
      if (signIn != null) {
        expect(
          rules.webRequestsGrantFor(
            replyEndpoint.origin,
            WebPath.parse('${replyEndpoint.pathPrefix}activities')!,
            signIn,
            leasedNow: leasedNow,
            pooled: pooled,
            replyEndpoint: replyEndpoint,
          ),
          isNotNull,
          reason: 'the airlock must grant a reply as the sign-in chosen',
        );
      }
      return signIn;
    }

    test('is the named sign-in of the reply grant', () {
      expect(chosen(replyingAs([GoesAsSignIn(bot)])), bot);
    });

    test('is the bot leased now, for a grant to the leased bot', () {
      final leased = replyingAs([GoesAsBotLeasedFrom(agents)]);
      expect(chosen(leased, leasedNow: {agents: researcher1}), researcher1);
      expect(chosen(leased), isNull);
    });

    test('prefers the named sign-in, as the airlock does', () {
      final both = replyingAs([GoesAsBotLeasedFrom(agents), GoesAsSignIn(bot)]);
      expect(chosen(both, leasedNow: {agents: researcher1}), bot);
    });

    test('never a pooled bot by name', () {
      final byName = replyingAs([GoesAsSignIn(researcher1)]);
      expect(chosen(byName, pooled: {researcher1}), isNull);
      final orLeased = replyingAs([
        GoesAsSignIn(researcher1),
        GoesAsBotLeasedFrom(agents),
      ]);
      expect(
        chosen(
          orLeased,
          leasedNow: {agents: researcher1},
          pooled: {researcher1},
        ),
        researcher1,
      );
    });

    test('is none for a grant under no sign-in', () {
      expect(chosen(replyingAs(const [GoesAsNobody()])), isNull);
    });

    test('is none for an endpoint on an origin no reply grant names', () {
      final elsewhere = Origin.parse('https://evil.example')!;
      expect(
        chosen(
          replyingAs([GoesAsSignIn(bot)]),
          at: under(elsewhere, '/amer/v3/conversations/19%3Aabc/'),
        ),
        isNull,
      );
    });

    test('is none without a reply grant', () {
      expect(chosen(replyingAs(const [])), isNull);
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

  group('a Graph folder grant', () {
    const folderAt = '/v1.0/drives/b!d_1/items/01F';
    String? prefix(Origin site, String raw, [SignIn? signIn]) {
      final granted = rules.fetchGrantFor(
        site,
        path(raw),
        signIn ?? bot,
        leasedNow: const {},
        pooled: const {},
      );
      if (granted == null) return null;
      expect(granted.grant, folderGrant);
      return granted.grantedPathPrefix.value;
    }

    test("reads the folder's listing, with at most a \$select", () {
      expect(prefix(graph, '$folderAt/children'), '$folderAt/');
      expect(
        prefix(
          graph,
          '$folderAt/children?\$select=name,size,lastModifiedDateTime,folder',
        ),
        '$folderAt/',
      );
      expect(prefix(graph, '$folderAt/children?%24select=name'), '$folderAt/');
    });

    test('reads a file in the folder by name, under its own prefix', () {
      const name = 'Incident%20report%20%232.docx';
      expect(prefix(graph, '$folderAt:/$name:/content'), '$folderAt:/$name:/');
      // `%3A` is `:`, as Graph and PathPrefix both read it.
      expect(
        prefix(graph, '/v1.0/drives/b!d_1/items/01F%3A/a.docx%3A/content'),
        isNotNull,
      );
    });

    test('refuses every other route to a file', () {
      for (final raw in [
        // A file by its own id, which names no folder.
        '/v1.0/drives/b!d_1/items/01FILE',
        '/v1.0/drives/b!d_1/items/01FILE/content',
        // By path from the root, or the same drive named another way.
        '/v1.0/drives/b!d_1/root:/a.docx:/content',
        '/v1.0/me/drive/items/01F/children',
        '/v1.0/sites/s1/drive/items/01F/children',
        '/beta/drives/b!d_1/items/01F/children',
        // Another folder, another drive.
        '/v1.0/drives/b!d_1/items/01G/children',
        '/v1.0/drives/b!d_2/items/01F/children',
        '/v1.0/drives/b!d_2/items/01F:/a.docx:/content',
        // The folder itself, or more than its listing.
        folderAt,
        '$folderAt/children/01X',
        '$folderAt/children?\$expand=children',
        '$folderAt/children?\$select=name&\$expand=children',
        '$folderAt/children?\$select=name,folder(\$expand)',
        '$folderAt/children?\$filter=size%20gt%200',
        // A file's metadata, or its content with a query.
        '$folderAt:/a.docx:',
        '$folderAt:/a.docx:/content?format=pdf',
        // Names that could reach past the folder, which no OneDrive name
        // has.
        '$folderAt:/a%2Fb.docx:/content',
        '$folderAt:/sub/a.docx:/content',
        '$folderAt:/a%5Cb.docx:/content',
        '$folderAt:/a%3Ab.docx:/content',
        '$folderAt:/.:/content',
        '$folderAt:/:/content',
        '$folderAt:/a.docx/content',
      ]) {
        expect(prefix(graph, raw), isNull, reason: raw);
      }
      // These never become a path for a grant to see.
      for (final raw in [
        '$folderAt:/..:/content',
        '$folderAt:/...:/content',
        '$folderAt:/a%2fb.docx:/content',
      ]) {
        expect(WebPath.parse(raw), isNull, reason: raw);
      }
    });

    test('reads only on Graph, and only as its sign-in', () {
      expect(prefix(docs, '$folderAt/children'), isNull);
      expect(
        rules.fetchGrantFor(
          graph,
          path('$folderAt/children'),
          null,
          leasedNow: const {},
          pooled: const {},
        ),
        isNull,
      );
      expect(
        prefix(graph, '$folderAt/children', SignIn.parse('other-bot')),
        isNull,
      );
    });

    test('ids are one segment, spelled one way', () {
      expect(GraphId.parse('b!3x9Q_-Z'), isNotNull);
      for (final raw in ['', '01F/x', '01F:', 'b%21d', '01 F', '..']) {
        expect(GraphId.parse(raw), isNull, reason: raw);
      }
    });
  });

  test('a grant under no sign-in is not a grant under a sign-in', () {
    // By ==, not only by hash, so a set that compared grants by address
    // alone would still be caught.
    expect(const GoesAsNobody() == GoesAsSignIn(bot), isFalse);
    expect(GoesAsSignIn(bot) == const GoesAsNobody(), isFalse);
    final docsRoot = FromAddressesUnder(under(docs, '/'));
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
    Map<String, Object?> fromUnder(Object? prefix) => {
      'kind': 'addressesUnder',
      'prefix': prefix,
    };
    final folder = {'kind': 'graphFolder', 'drive': 'b!d_1', 'folder': '01F'};
    final fetchGrant = {'from': fromUnder(from), 'goesAs': nobody};
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
        // 0.4.0's bare prefix, with no kind.
        {...fetchGrant, 'from': from},
        {
          ...fetchGrant,
          'from': {...fromUnder(from), 'kind': 'anywhere'},
        },
        {
          ...fetchGrant,
          'from': {...fromUnder(from), 'folder': '01F'},
        },
        {...fetchGrant, 'from': fromUnder('https://docs.example.com')},
        {
          ...fetchGrant,
          'from': fromUnder({...from, 'pathPrefix': '/guide'}),
        },
        {
          ...fetchGrant,
          'from': fromUnder({...from, 'pathPrefix': '/guide?x=1/'}),
        },
        {
          ...fetchGrant,
          'from': fromUnder({...from, 'pathPrefix': '/a/%2e%2e/'}),
        },
        {
          ...fetchGrant,
          'from': fromUnder({'origin': 'https://docs.example.com'}),
        },
        {
          ...fetchGrant,
          'from': fromUnder({...from, 'method': 'GET'}),
        },
        {
          ...fetchGrant,
          'from': fromUnder({
            ...from,
            'origin': 'https://docs.example.com/path',
          }),
        },
        {...fetchGrant, 'path': '/'},
        {
          ...fetchGrant,
          'from': {'kind': 'graphFolder', 'drive': 'b!d_1'},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'prefix': from},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'folder': ''},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'folder': '01F/children'},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'folder': '01F:'},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'drive': 'b%21d_1'},
        },
        {
          ...fetchGrant,
          'from': {...folder, 'drive': 1},
        },
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
