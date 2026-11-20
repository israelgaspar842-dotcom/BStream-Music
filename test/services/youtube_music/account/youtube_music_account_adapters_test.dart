import 'dart:io';

import 'package:bstream_music/services/youtube_music/account/youtube_music_account.dart';
import 'package:bstream_music/services/youtube_music/auth/youtube_music_auth_models.dart'
    as auth;
import 'package:bstream_music/services/youtube_music/auth/youtube_music_auth_coordinator.dart';
import 'package:bstream_music/services/youtube_music/auth/youtube_music_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viaCoordinator in [false, true]) {
    test(
      'profile refresh bypasses discovery cache${viaCoordinator ? ' through coordinator' : ''}',
      () async {
        final transport = _QueuedAccountTransport([
          _accountProfile('Old name', 'https://yt3.googleusercontent.com/old'),
          const <String, Object?>{},
          _accountProfile('New name', 'https://yt3.googleusercontent.com/new'),
        ]);
        final client = GatewayYouTubeMusicAccountClient(
          createGateway: (_) => YouTubeMusicAccountGateway(
            transport: transport,
            sessionHeaders: StaticYouTubeMusicSessionHeadersProvider(
              YouTubeMusicSessionHeaders(const {}),
            ),
            clientContext: const {
              'client': {'clientName': 'WEB_REMIX'},
            },
          ),
        );
        final authData = auth.YouTubeMusicWebAuthData(
          cookieHeader: _credential.cookieHeader,
          identity: _credential.identity,
          apiKey: _credential.apiKey,
          clientVersion: _credential.clientVersion,
          clientName: _credential.clientName,
        );
        // Channel discovery leaves its current profile ready for the login's
        // normal validation handoff. An independent refresh must bypass it.
        await client.listChannels(authData);
        expect(transport.requests, hasLength(2));

        final auth.YouTubeMusicAccountProfile fresh;
        if (viaCoordinator) {
          final coordinator = YouTubeMusicAuthCoordinator(
            sessionStore: _UnusedSessionStore(),
            accountClient: client,
          );
          fresh = (await coordinator.refreshProfile(_credential)).profile;
        } else {
          fresh = await client.refreshAccount(authData);
        }

        expect(fresh.displayName, 'New name');
        expect(
          fresh.avatarUrl,
          Uri.parse('https://yt3.googleusercontent.com/new'),
        );
        expect(transport.requests.map((request) => request.endpoint), [
          'account/account_menu',
          'account/accounts_list',
          'account/account_menu',
        ]);
      },
    );
  }

  group('production session header adapters', () {
    test('derives headers from a secure credential snapshot', () async {
      var reads = 0;
      final provider = CredentialYouTubeMusicSessionHeadersProvider(
        readCredential: () async {
          reads += 1;
          return _credential;
        },
        additionalHeaders: const <String, String>{
          'X-YouTube-Client-Name': '67',
        },
      );

      final headers = await provider.headersFor(
        const YouTubeMusicSessionHeaderRequest(
          endpoint: 'browse',
          kind: YouTubeMusicAccountRequestKind.read,
        ),
      );
      final values = headers.toTransportMap();

      expect(reads, 1);
      expect(values['Cookie'], 'SAPISID=test-session-value');
      expect(values['Authorization'], startsWith('SAPISIDHASH '));
      expect(values['X-Goog-AuthUser'], '0');
      expect(values['X-Goog-Visitor-Id'], 'visitor-data');
      expect(values['X-YouTube-Client-Name'], 'WEB_REMIX');
      expect(values['X-YouTube-Client-Version'], '1.test');
      expect(values['X-Goog-Api-Format-Version'], '1');
      expect(values['Referer'], 'https://music.youtube.com/');
      expect(values['User-Agent'], contains('Mozilla/5.0'));
      expect(
        values['Accept-Language'],
        matches(RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?,[a-z]{2,3};q=0\.9$')),
      );
      expect(headers.apiKey, 'test_api_key');
      expect(headers.toString(), isNot(contains('test-session-value')));
    });

    test(
      'supports a WebView candidate before credential persistence',
      () async {
        final provider = WebAuthDataYouTubeMusicSessionHeadersProvider(
          authData: auth.YouTubeMusicWebAuthData(
            cookieHeader: 'SAPISID=candidate-value',
            identity: const auth.YouTubeMusicAuthIdentity(
              visitorData: 'candidate-visitor',
              authUser: '1',
            ),
            apiKey: 'candidate_api_key',
            clientVersion: '1.candidate',
            clientName: 'WEB_REMIX',
          ),
        );

        final headers = await provider.headersFor(
          const YouTubeMusicSessionHeaderRequest(
            endpoint: 'account/account_menu',
            kind: YouTubeMusicAccountRequestKind.read,
          ),
        );

        expect(headers.toTransportMap()['Cookie'], 'SAPISID=candidate-value');
        expect(headers.toString(), isNot(contains('candidate-value')));
      },
    );

    test('fails closed when no persisted session exists', () async {
      final provider = CredentialYouTubeMusicSessionHeadersProvider(
        readCredential: () async => null,
      );

      await expectLater(
        provider.headersFor(
          const YouTubeMusicSessionHeaderRequest(
            endpoint: 'browse',
            kind: YouTubeMusicAccountRequestKind.read,
          ),
        ),
        throwsA(
          isA<YouTubeMusicAccountException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });

    test('builds WEB_REMIX context from an auth identity', () {
      final context = buildYouTubeMusicAccountClientContext(
        clientVersion: '1.test',
        clientName: 'WEB_REMIX',
        identity: const auth.YouTubeMusicAuthIdentity(
          visitorData: 'visitor-data',
          authUser: '0',
          dataSyncId: 'UC-main||sync',
        ),
        language: 'es-419',
        region: 'ni',
      );

      final client = context['client']! as Map<String, Object?>;
      final user = context['user']! as Map<String, Object?>;
      expect(client['clientName'], 'WEB_REMIX');
      expect(client['clientVersion'], '1.test');
      expect(client['visitorData'], 'visitor-data');
      expect(client['gl'], 'NI');
      expect(user['onBehalfOfUser'], 'UC-main||sync');
    });

    test(
      'does not force a Nicaragua region when the page did not provide one',
      () {
        final context = buildYouTubeMusicAccountClientContext(
          clientVersion: '1.test',
          clientName: 'WEB_REMIX',
          identity: const auth.YouTubeMusicAuthIdentity(
            visitorData: 'visitor-data',
            authUser: '0',
          ),
        );

        final client = context['client']! as Map<String, Object?>;
        expect(client['gl'], isNot('NI'));
        expect(client['gl'], matches(r'^[A-Z]{2}$'));
      },
    );
  });

  group('IO account transport safety', () {
    test(
      'targets only the exact HTTPS origin and adds continuation query',
      () async {
        final client = _RecordingHttpClient();
        final transport = IoYouTubeMusicAccountTransport(
          client: client,
          apiKey: 'fixture_key',
        );
        final request = _request(
          endpoint: 'browse',
          body: const <String, Object?>{'continuation': 'token-value'},
        );

        await expectLater(
          transport.send(request),
          throwsA(
            isA<YouTubeMusicAccountTransportException>().having(
              (error) => error.delivery,
              'delivery',
              YouTubeMusicRequestDelivery.notSent,
            ),
          ),
        );

        expect(client.openedUri?.scheme, 'https');
        expect(client.openedUri?.host, 'music.youtube.com');
        expect(client.openedUri?.path, '/youtubei/v1/browse');
        expect(client.openedUri?.queryParameters['key'], 'fixture_key');
        expect(client.openedUri?.queryParameters['prettyPrint'], 'false');
        expect(
          client.openedUri?.queryParameters['continuation'],
          'token-value',
        );
        expect(client.openedUri?.queryParameters['ctoken'], 'token-value');
        transport.close();
      },
    );

    test('rejects path traversal before opening a socket', () async {
      final client = _RecordingHttpClient();
      final transport = IoYouTubeMusicAccountTransport(client: client);

      await expectLater(
        transport.send(_request(endpoint: '../browse')),
        throwsA(isA<YouTubeMusicAccountTransportException>()),
      );

      expect(client.openedUri, isNull);
      transport.close();
    });

    test('rejects malformed API keys at construction', () {
      expect(
        () => IoYouTubeMusicAccountTransport(apiKey: 'bad key&redirect=1'),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> _accountProfile(String name, String avatarUrl) => {
  'activeAccountHeaderRenderer': {
    'accountName': {'simpleText': name},
    'accountPhoto': {
      'thumbnails': [
        {'url': avatarUrl, 'width': 128, 'height': 128},
      ],
    },
    'navigationEndpoint': {
      'browseEndpoint': {'browseId': 'UC-main'},
    },
  },
};

class _QueuedAccountTransport implements YouTubeMusicAccountTransport {
  _QueuedAccountTransport(this.responses);

  final List<Object?> responses;
  final requests = <YouTubeMusicAccountRequest>[];

  @override
  Future<YouTubeMusicAccountResponse> send(
    YouTubeMusicAccountRequest request,
  ) async {
    requests.add(request);
    return YouTubeMusicAccountResponse(
      statusCode: 200,
      body: responses.removeAt(0),
    );
  }
}

class _UnusedSessionStore implements YouTubeMusicSessionStore {
  @override
  Future<auth.YouTubeMusicSessionCredential?> read() =>
      throw UnimplementedError();

  @override
  Future<void> write(auth.YouTubeMusicSessionCredential credential) =>
      throw UnimplementedError();

  @override
  Future<void> delete() => throw UnimplementedError();
}

final auth.YouTubeMusicSessionCredential _credential =
    auth.YouTubeMusicSessionCredential(
      cookieHeader: 'SAPISID=test-session-value',
      identity: const auth.YouTubeMusicAuthIdentity(
        visitorData: 'visitor-data',
        authUser: '0',
        dataSyncId: 'UC-main||sync',
        delegatedPageId: 'UC-main',
      ),
      profile: const auth.YouTubeMusicAccountProfile(
        channelId: 'UC-main',
        displayName: 'Listener',
      ),
      validatedAt: DateTime.utc(2026, 8, 22),
      apiKey: 'test_api_key',
      clientVersion: '1.test',
      clientName: 'WEB_REMIX',
    );

YouTubeMusicAccountRequest _request({
  required String endpoint,
  Map<String, Object?> body = const <String, Object?>{},
}) {
  return YouTubeMusicAccountRequest(
    endpoint: endpoint,
    kind: YouTubeMusicAccountRequestKind.read,
    headers: const <String, String>{},
    body: body,
    timeout: const Duration(milliseconds: 100),
  );
}

class _RecordingHttpClient implements HttpClient {
  Uri? openedUri;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    openedUri = url;
    throw const SocketException('fixture stops before dispatch');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
