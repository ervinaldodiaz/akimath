import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'auth_result.dart';

export 'auth_result.dart';

/// The calls the account flow makes, as a seam.
///
/// **It exists so a widget test can stand in for the provider.** `testWidgets`
/// runs in a fake-async zone, so a real socket inside one completes on a clock
/// the test does not control — `auth_client_test.dart` exercises the real
/// implementation against a real `HttpServer` in a plain `test()`, which is
/// where that belongs, and the flow is driven against a double.
abstract interface class AuthApi {
  Future<AuthResult<Accepted>> signUp({
    required String email,
    required String password,
    required String callbackUrl,
  });

  Future<AuthResult<Accepted>> sendVerificationCode(String email);

  Future<AuthResult<AuthSession>> verifyEmail({
    required String email,
    required String code,
  });

  Future<AuthResult<AuthSession>> signIn({
    required String email,
    required String password,
  });

  Future<AuthResult<Accepted>> sendPasswordReset({
    required String email,
    required String redirectTo,
  });

  Future<AuthResult<Accepted>> resetPassword({
    required String token,
    required String newPassword,
  });

  Future<AuthResult<String>> accessToken(AuthSession session);
}

/// Neon Auth's REST API, as much of it as the account flow needs.
///
/// **A PURE-2 adapter.** It holds no cooldown, no retry and no storage: what a
/// screen may do next is `features/auth/policy/credential_rules.dart`, which is
/// pure. This turns one call into one typed result.
///
/// **The endpoint shapes were discovered against the running provider**, not
/// read from an SDK. `POST /email-otp/send-verification-otp` and
/// `POST /email-otp/verify-email` exist even though the `emailOTP` *plugin* is
/// disabled — they serve `emailVerificationMethod: "otp"`, which is a different
/// setting, and that distinction is what lets email sign-up be open while
/// GHSA-qq9h-g4jm-xgf3 stays shut (ADR 0002's amendment).
///
/// **`GET /token` answers 401, not 404**, which is how the JWT the AkiMath
/// server verifies is obtained: sign in or verify to get a session, then ask.
class AuthClient implements AuthApi {
  AuthClient({
    required Uri baseUrl,
    HttpClient? transport,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl,
       _transport = transport ?? HttpClient();

  final Uri _baseUrl;
  final HttpClient _transport;
  final Duration timeout;

  /// Creates an account. No session comes back while verification is required.
  ///
  /// **`callbackUrl` must be absolute.** The provider answers `MISSING_ORIGIN`
  /// otherwise — it wants either an `Origin` header or somewhere absolute to
  /// send a browser, and a mobile app has no origin to offer.
  ///
  /// **The address is sent as the name too.** The provider's schema wants one
  /// and a player has none — Q5, decided: a player has no name and `players`
  /// has no column for one, so the address is the only thing that identifies an
  /// account.
  @override
  Future<AuthResult<Accepted>> signUp({
    required String email,
    required String password,
    required String callbackUrl,
  }) async {
    final _Answer answer = await _post('sign-up/email', <String, Object?>{
      'email': email,
      'password': password,
      'name': email,
      'callbackURL': callbackUrl,
    });
    return answer.map((_) => const Accepted());
  }

  /// Asks for a verification code by email.
  ///
  /// Needed on its own because `sendVerificationEmailOnSignUp` is off: creating
  /// the account sends nothing, so the app asks when it is ready to show the
  /// code screen.
  ///
  /// The `type` sent is one of `email-verification`, `sign-in`,
  /// `forget-password` and `change-email` — the vocabulary read off the
  /// provider's own validation error, not out of an SDK.
  @override
  Future<AuthResult<Accepted>> sendVerificationCode(String email) async {
    final _Answer answer = await _post(
      'email-otp/send-verification-otp',
      <String, Object?>{
        'email': email,
        'type': 'email-verification',
      },
    );
    return answer.map((_) => const Accepted());
  }

  /// Verifies the address with the code, and signs in if the provider says so.
  @override
  Future<AuthResult<AuthSession>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final _Answer answer = await _post(
      'email-otp/verify-email',
      <String, Object?>{'email': email, 'otp': code},
    );
    return answer.mapSession();
  }

  /// Signs in an account that already exists — `1.1`.
  ///
  /// **The session is the whole answer.** A player who signs in has verified
  /// their address already, so there is no code to ask for; the only step left
  /// is [accessToken], exactly as after [verifyEmail].
  ///
  /// **Nothing is checked here about the password beyond its being sent.** The
  /// provider is the authority on whether a credential is right, and a client
  /// that applied `CredentialRules.longEnough` on the way in would refuse an
  /// account whose password predates that floor without ever asking.
  @override
  Future<AuthResult<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    final _Answer answer = await _post('sign-in/email', <String, Object?>{
      'email': email,
      'password': password,
    });
    return answer.mapSession();
  }

  /// Asks the provider to email a password-reset link — `1.4`.
  ///
  /// **This is Better Auth's core `forget-password`, not an email-OTP call.**
  /// The OTP plugin is what ADR 0002's amendment keeps switched off to hold
  /// GHSA-qq9h-g4jm-xgf3 shut, so recovery goes down the path that needs no
  /// plugin at all. Nothing here constructs, signs or verifies a token: the
  /// provider mints it and mails it, which is the only arrangement CLAUDE.md's
  /// *"never hand-write authentication crypto"* permits.
  ///
  /// **A success is not proof an email was sent.** The provider answers the
  /// same for an address that has no account — deliberate, so a caller cannot
  /// enumerate who is registered — so the screen above this says *"si esa
  /// cuenta existe"* and never *"te lo mandamos"*.
  ///
  /// [redirectTo] carries the same trusted-origin rule as `callbackURL` on
  /// sign-up: absolute, and inside a trusted origin, or the provider answers
  /// **403 `INVALID_CALLBACK_URL`**. See `Endpoints.callbackUrl`.
  @override
  Future<AuthResult<Accepted>> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) async {
    final _Answer answer = await _post('forget-password', <String, Object?>{
      'email': email,
      'redirectTo': redirectTo,
    });
    return answer.map((_) => const Accepted());
  }

  /// Sets a new password from the token in that email — `1.5`.
  ///
  /// **Nothing in the app can reach this yet, and that is a fact about the
  /// device rather than about the provider.** The token arrives only inside the
  /// emailed link, so receiving it needs a URL scheme registered in
  /// `AndroidManifest.xml` and `Info.plist` plus that scheme added to the
  /// provider's `trusted_origins` — none of which exists. The operation is
  /// written so the screen above it is driving something real the day it does.
  @override
  Future<AuthResult<Accepted>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final _Answer answer = await _post('reset-password', <String, Object?>{
      'token': token,
      'newPassword': newPassword,
    });
    return answer.map((_) => const Accepted());
  }

  /// The JWT the AkiMath server verifies, for a session that has one.
  @override
  Future<AuthResult<String>> accessToken(AuthSession session) async {
    final _Answer answer = await _get('token', session);
    return answer.map((Map<String, Object?> body) {
      final Object? token = body['token'];
      if (token is! String || token.isEmpty) {
        throw const FormatException('the token response carried no token');
      }
      return token;
    });
  }

  void close() => _transport.close();

  Future<_Answer> _post(String path, Map<String, Object?> body) =>
      _send(path, body: body, session: null);

  Future<_Answer> _get(String path, AuthSession session) =>
      _send(path, body: null, session: session);

  Future<_Answer> _send(
    String path, {
    required Map<String, Object?>? body,
    required AuthSession? session,
  }) async {
    final Uri url = _slashed(_baseUrl).resolve(path);
    try {
      final HttpClientRequest request = body == null
          ? await _transport.getUrl(url)
          : await _transport.postUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (session != null) {
        request.headers.set(HttpHeaders.cookieHeader, session.cookie);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(json.encode(body));
      }
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String text = await response.transform(utf8.decoder).join();
      return _Answer(
        status: response.statusCode,
        text: text,
        setCookie:
            response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
      );
    } on Exception catch (cause) {
      return _Answer.unreachable(cause.toString());
    }
  }

  /// The base URL with a trailing slash, which [Uri.resolve] requires.
  ///
  /// **Without one, `resolve` replaces the last segment instead of appending**,
  /// so `.../neondb/auth` plus `token` would ask for `.../neondb/token`.
  static Uri _slashed(Uri base) =>
      base.path.endsWith('/') ? base : base.replace(path: '${base.path}/');
}

/// One HTTP answer, before it is given a meaning.
@immutable
class _Answer {
  const _Answer({
    required this.status,
    required this.text,
    required this.setCookie,
  }) : unreachableReason = null;

  const _Answer.unreachable(String reason)
    : status = 0,
      text = '',
      setCookie = const <String>[],
      unreachableReason = reason;

  final int status;
  final String text;
  final List<String> setCookie;
  final String? unreachableReason;

  Map<String, Object?> get _body {
    try {
      final Object? decoded = json.decode(text);
      return decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  AuthResult<T> map<T>(T Function(Map<String, Object?> body) onOk) {
    final AuthResult<T>? early = _early<T>();
    if (early != null) {
      return early;
    }
    try {
      return AuthOk<T>(onOk(_body));
    } on FormatException catch (cause) {
      return AuthFailed<T>(status: status, reason: cause.message);
    }
  }

  /// The answer as a session, or a failure if it set no cookie.
  ///
  /// **A 2xx that carries no cookie is a failure, not an empty session.**
  /// Handing one back would authenticate nothing and fail at the next call with
  /// an unrelated message, which is harder to act on than saying so here.
  AuthResult<AuthSession> mapSession() {
    final AuthResult<AuthSession>? early = _early<AuthSession>();
    if (early != null) {
      return early;
    }
    final String cookie = _everySetCookieJoined;
    if (cookie.isEmpty) {
      return AuthFailed<AuthSession>(
        status: status,
        reason: 'the provider accepted the call and set no session cookie',
      );
    }
    return AuthOk<AuthSession>(AuthSession(cookie));
  }

  /// Every `Set-Cookie` the answer carried, as one `Cookie` header value.
  ///
  /// **All of them, because the provider sends more than one** and dropping the
  /// wrong one is a session that works until it does not.
  String get _everySetCookieJoined => setCookie
      .map((String header) => header.split(';').first.trim())
      .where((String pair) => pair.isNotEmpty)
      .join('; ');

  AuthResult<T>? _early<T>() {
    if (unreachableReason != null) {
      return AuthUnreachable<T>(unreachableReason!);
    }
    if (status >= 200 && status < 300) {
      return null;
    }
    if (status >= 400 && status < 500) {
      final Map<String, Object?> body = _body;
      return AuthRefused<T>(
        status: status,
        code: body['code'] as String? ?? '',
        message: body['message'] as String? ?? '',
      );
    }
    return AuthFailed<T>(
      status: status,
      reason: _body['message'] as String? ?? text,
    );
  }
}
