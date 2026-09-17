import 'dart:convert';
import 'dart:io';

import 'package:akimath_app/api/auth_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for Neon Auth, answering the shapes the real one answers.
///
/// **The shapes are not invented.** Every status, body and validation message
/// below was read off the running provider by probing it — including the two
/// that decided the design: `MISSING_ORIGIN` on `sign-up/email` without an
/// absolute `callbackURL`, and `GET /token` answering **401 rather than 404**,
/// which is what showed the endpoint exists and wants a session.
class _Provider {
  _Provider(this._socket, this.calls);

  static Future<_Provider> answering(
    Future<void> Function(HttpRequest request, String body) respond,
  ) async {
    final HttpServer socket = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final List<_Call> calls = <_Call>[];
    socket.listen((HttpRequest request) async {
      final String body = await utf8.decodeStream(request);
      calls.add(_Call(request.method, request.uri.path, body,
          request.headers.value(HttpHeaders.cookieHeader)));
      await respond(request, body);
      await request.response.close();
    });
    return _Provider(socket, calls);
  }

  final HttpServer _socket;
  final List<_Call> calls;

  /// A base URL with a path segment, the way the real one has `/neondb/auth`.
  Uri get baseUrl =>
      Uri.parse('http://${_socket.address.host}:${_socket.port}/neondb/auth');

  Future<void> close() => _socket.close(force: true);
}

class _Call {
  _Call(this.method, this.path, this.body, this.cookie);
  final String method;
  final String path;
  final String body;
  final String? cookie;
  Map<String, Object?> get json =>
      body.isEmpty ? const <String, Object?>{} : jsonDecode(body) as Map<String, Object?>;
}

Future<void> _reply(HttpRequest request, int status, Object? body,
    {List<String> cookies = const <String>[]}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  for (final String cookie in cookies) {
    request.response.headers.add(HttpHeaders.setCookieHeader, cookie);
  }
  request.response.write(json.encode(body));
}

void main() {
  late _Provider provider;
  late AuthClient client;

  Future<void> serving(Future<void> Function(HttpRequest, String) respond) async {
    provider = await _Provider.answering(respond);
    client = AuthClient(baseUrl: provider.baseUrl);
  }

  tearDown(() async {
    client.close();
    await provider.close();
  });

  group('the paths are the provider\'s own', () {
    test('every call lands under the base path, not beside it', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 200, <String, Object?>{'token': 'a.b.c'},
              cookies: <String>['session=abc; Path=/']));

      await client.signUp(email: 'a@b.co', password: 'password1', callbackUrl: 'akimath://done');
      await client.sendVerificationCode('a@b.co');
      await client.verifyEmail(email: 'a@b.co', code: '123456');
      await client.signIn(email: 'a@b.co', password: 'password1');
      await client.accessToken(const AuthSession('session=abc'));

      expect(provider.calls.map((_Call c) => '${c.method} ${c.path}').toList(), <String>[
        'POST /neondb/auth/sign-up/email',
        'POST /neondb/auth/email-otp/send-verification-otp',
        'POST /neondb/auth/email-otp/verify-email',
        'POST /neondb/auth/sign-in/email',
        'GET /neondb/auth/token',
      ]);
    });

    test('sign-up sends an absolute callbackURL, or the provider refuses it', () async {
      await serving((HttpRequest request, String body) => _reply(request, 200, <String, Object?>{}));

      await client.signUp(
        email: 'a@b.co',
        password: 'password1',
        callbackUrl: 'akimath://verified',
      );

      final Map<String, Object?> sent = provider.calls.single.json;
      expect(sent['email'], 'a@b.co');
      expect(sent['password'], 'password1');
      expect(sent['callbackURL'], 'akimath://verified');
      expect(Uri.parse(sent['callbackURL']! as String).isAbsolute, isTrue);
    });

    test('the code request names the type the provider validates against', () async {
      await serving((HttpRequest request, String body) => _reply(request, 200, <String, Object?>{}));

      await client.sendVerificationCode('a@b.co');

      expect(provider.calls.single.json['type'], 'email-verification');
    });

    test('the code is sent as `otp`, which is what the body is validated as', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 200, <String, Object?>{}, cookies: <String>['session=abc']));

      await client.verifyEmail(email: 'a@b.co', code: '123456');

      expect(provider.calls.single.json, <String, Object?>{'email': 'a@b.co', 'otp': '123456'});
    });
  });

  group('a session is a cookie, because the bearer plugin is off', () {
    test('verifying returns one, carrying every cookie the provider set', () async {
      await serving((HttpRequest request, String body) => _reply(
        request,
        200,
        <String, Object?>{'status': true},
        cookies: <String>[
          'better-auth.session_token=abc123; Path=/; HttpOnly',
          'better-auth.csrf=xyz; Path=/',
        ],
      ));

      final AuthResult<AuthSession> result =
          await client.verifyEmail(email: 'a@b.co', code: '123456');

      expect(result, isA<AuthOk<AuthSession>>());
      final String cookie = (result as AuthOk<AuthSession>).value.cookie;
      expect(cookie, contains('better-auth.session_token=abc123'));
      expect(cookie, contains('better-auth.csrf=xyz'));
      expect(cookie, isNot(contains('HttpOnly')));
    });

    test('and it is sent back when the token is asked for', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 200, <String, Object?>{'token': 'header.payload.signature'}));

      final AuthResult<String> result =
          await client.accessToken(const AuthSession('better-auth.session_token=abc123'));

      expect(result, isA<AuthOk<String>>());
      expect((result as AuthOk<String>).value, 'header.payload.signature');
      expect(provider.calls.single.cookie, 'better-auth.session_token=abc123');
    });

    test('a success with no cookie is a failure, not an empty session', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 200, <String, Object?>{'status': true}));

      expect(await client.signIn(email: 'a@b.co', password: 'password1'),
          isA<AuthFailed<AuthSession>>());
    });

    test('a session never prints itself', () async {
      expect(const AuthSession('better-auth.session_token=abc123').toString(),
          isNot(contains('abc123')));
    });
  });

  group('what the provider says no with', () {
    test('a 4xx carries the code and the message a person can act on', () async {
      await serving((HttpRequest request, String body) => _reply(request, 400, <String, Object?>{
        'code': 'INVALID_OTP',
        'message': 'The code is wrong or has expired.',
      }));

      final AuthResult<AuthSession> result =
          await client.verifyEmail(email: 'a@b.co', code: '000000');

      expect(result, isA<AuthRefused<AuthSession>>());
      final AuthRefused<AuthSession> refused = result as AuthRefused<AuthSession>;
      expect(refused.code, 'INVALID_OTP');
      expect(refused.message, contains('wrong'));
      expect(refused.status, 400);
    });

    test('MISSING_ORIGIN arrives as a refusal, since it is our request that is wrong', () async {
      await serving((HttpRequest request, String body) => _reply(request, 400, <String, Object?>{
        'code': 'MISSING_ORIGIN',
        'message': 'Origin header is required when callbackURL is not an absolute URL',
      }));

      final AuthResult<Accepted> result =
          await client.signUp(email: 'a@b.co', password: 'password1', callbackUrl: '/done');

      expect((result as AuthRefused<Accepted>).code, 'MISSING_ORIGIN');
    });

    test('an unauthenticated token request is a refusal, not a crash', () async {
      await serving((HttpRequest request, String body) => _reply(
          request, 401, <String, Object?>{'message': 'Unauthorized', 'code': 'UNAUTHORIZED'}));

      final AuthResult<String> result = await client.accessToken(const AuthSession('nope=1'));
      expect((result as AuthRefused<String>).code, 'UNAUTHORIZED');
    });

    test('a 5xx is a failure rather than something to show a person', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 503, <String, Object?>{'message': 'upstream is down'}));

      expect(await client.sendVerificationCode('a@b.co'), isA<AuthFailed<Accepted>>());
    });

    test('an HTML error page does not throw on the way to a result', () async {
      await serving((HttpRequest request, String body) async {
        request.response.statusCode = 502;
        request.response.write('<html>bad gateway</html>');
      });

      expect(await client.sendVerificationCode('a@b.co'), isA<AuthFailed<Accepted>>());
    });

    test('a 200 token response with no token is a failure', () async {
      await serving((HttpRequest request, String body) =>
          _reply(request, 200, <String, Object?>{'unexpected': true}));

      expect(await client.accessToken(const AuthSession('s=1')), isA<AuthFailed<String>>());
    });
  });

  group('when the provider is not there', () {
    test('a refused socket is unreachable, not an exception', () async {
      final HttpServer dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final Uri gone = Uri.parse('http://${dead.address.host}:${dead.port}/neondb/auth');
      await dead.close(force: true);

      final AuthClient orphan = AuthClient(baseUrl: gone);
      addTearDown(orphan.close);

      expect(await orphan.sendVerificationCode('a@b.co'), isA<AuthUnreachable<Accepted>>());
    });

    test('a provider that never answers times out', () async {
      provider = await _Provider.answering((HttpRequest request, String body) =>
          Future<void>.delayed(const Duration(seconds: 30)));
      client = AuthClient(
        baseUrl: provider.baseUrl,
        timeout: const Duration(milliseconds: 150),
      );

      expect(await client.sendVerificationCode('a@b.co'), isA<AuthUnreachable<Accepted>>());
    });
  });
}
