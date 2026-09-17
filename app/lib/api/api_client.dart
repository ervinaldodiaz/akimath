import 'dart:convert';
import 'dart:io';


import 'history.dart';
import 'me.dart';
import 'sync.dart';
import 'me_result.dart';

// Re-exported so a caller that fetches and a caller that only reads the result
// both need one import.
export 'history.dart';
export 'me_result.dart';
export 'sync.dart';

/// The one place in the app that opens a socket.
///
/// **A PURE-2 adapter, holding no decisions** (ADR 0001). No retry, no backoff,
/// no caching, no token storage: it is handed a token and a base URL, and it
/// turns one request into one typed result. Whether to retry is the caller's
/// question, and putting it here would answer it identically for every screen.
///
/// `dart:io`'s `HttpClient` rather than a package, because AkiMath is a mobile
/// app and that keeps the runtime dependency list where it is — `flutter`,
/// `cupertino_icons`, `meta`, `shared_preferences`. On the web this would not
/// compile; there is no web build.
///
/// **The base URL carries whatever prefix the deployment uses.** The contract
/// declares `servers: [{ url: "/v1" }]`, so a deployed server is reached at
/// `https://host/v1`; the server does not mount there yet, so against a local
/// one the base URL is just `http://localhost:PORT`. The client takes the whole
/// thing rather than assuming either.
///
/// **Every transport failure comes back as a value, on every operation here.**
/// `SocketException`, `TimeoutException`, a malformed URL: a screen cannot
/// `catch` what it never called, and letting these escape would make the caller
/// handle errors in two shapes. Each operation has its own `…Unreachable` arm
/// for exactly that.
///
/// **A 200 whose body is not what the contract promised is a `…Failed`**, on
/// every operation here. It is not the shape the caller asked for, so it cannot
/// be the found arm, and it is not the caller's fault, so it is not the
/// rejected one — and a `FormatException` out of a model constructor never
/// reaches a screen.
class ApiClient {
  ApiClient({
    required Uri baseUrl,
    HttpClient? transport,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _transport = transport ?? HttpClient();

  final Uri _baseUrl;
  final HttpClient _transport;

  /// How long one request may take, end to end.
  ///
  /// A timeout is not a retry policy — it is the difference between a screen
  /// that reports a failure and one that spins forever on a network that went
  /// away mid-answer. It is a constructor parameter so the default is visible,
  /// so a caller who knows better can say so, and so a test for a server that
  /// never answers need not wait ten seconds for one.
  final Duration timeout;

  /// The profile behind the token, or why there is not one.
  Future<MeResult> getMe(String accessToken) async {
    final Uri url = _baseUrl.resolve('me');
    try {
      final HttpClientRequest request = await _transport.getUrl(url);
      _authorize(request, accessToken);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readMe(response.statusCode, body);
    } on Exception catch (cause) {
      return MeUnreachable(cause.toString());
    }
  }

  /// Sends the bearer header, and sends none at all for a blank token.
  ///
  /// **`Bearer ` with nothing after it is a header the server can only refuse**,
  /// and it refuses it as `invalid_session` — "you sent something broken" — when
  /// the truth is `unauthenticated`, "you sent nothing". The server went to the
  /// trouble of separating those two, and a client that garbles the distinction
  /// wastes it. Found by running the real client against the real server, not by
  /// reading it.
  void _authorize(HttpClientRequest request, String accessToken) {
    if (accessToken.trim().isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    }
  }

  /// The whole response body, read to the end.
  ///
  /// **Drained even on a 204, where it is empty**: an unread response body holds
  /// the connection open until the client is closed.
  Future<String> _drain(HttpClientResponse response) =>
      response.transform(utf8.decoder).join();

  /// Attaches this device's player to the account the token names.
  ///
  /// **The band travels; the account does not.** The server takes the account
  /// from the verified token and refuses a body that so much as mentions it —
  /// so there is no parameter here for one, deliberately.
  ///
  /// `Idempotency-Key` is required by the contract. The caller supplies it, so
  /// a retry of *the same* attempt can carry the same key; generating one here
  /// would make every retry look like a new request.
  Future<LinkResult> linkPlayer({
    required String accessToken,
    required String playerId,
    required AgeBand ageBand,
    required String idempotencyKey,
  }) async {
    final Uri url = _baseUrl.resolve('players/link');
    try {
      final HttpClientRequest request = await _transport.postUrl(url);
      _authorize(request, accessToken);
      request.headers.set('Idempotency-Key', idempotencyKey);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(json.encode(<String, Object?>{
        'playerId': playerId,
        'ageBand': ageBand.wireName,
      }));
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readLink(response.statusCode, body);
    } on Exception catch (cause) {
      return LinkUnreachable(cause.toString());
    }
  }

  /// Asks for a pack to play offline.
  ///
  /// **No body and no `Idempotency-Key`.** The player comes from the session,
  /// and issuing is not idempotent by nature: a retried request leaves a second
  /// valid pack, which is harmless. The contract requires neither.
  Future<IssueResult> issuePack(String accessToken) async {
    final Uri url = _baseUrl.resolve('packs');
    try {
      final HttpClientRequest request = await _transport.postUrl(url);
      _authorize(request, accessToken);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readIssue(response.statusCode, body);
    } on Exception catch (cause) {
      return IssueUnreachable(cause.toString());
    }
  }

  IssueResult _readIssue(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 200:
        try {
          return IssueDone(IssuedPack.fromJson(_object(body)));
        } on FormatException catch (cause) {
          return IssueFailed(status: status, reason: cause.message);
        }
      case 404:
        return const IssueNoPlayer();
      case 401:
        return IssueRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      default:
        return IssueFailed(status: status, reason: message.isEmpty ? body : message);
    }
  }

  /// Fetches a pack the server issued earlier.
  ///
  /// **This is what makes a pack survive a relaunch.** The device stores the
  /// id and nothing else; the server rebuilds from the row it wrote plus the
  /// content that row names, byte for byte, so a re-fetch is the same pack and
  /// not a new one. Issuing again on every launch would work and would leave a
  /// row per launch behind it.
  ///
  /// **A 404 is the one answer that means issue a new one.** Gone, lapsed past
  /// its window, or somebody else's — the server cannot tell those apart on
  /// purpose, because distinguishing them confirms a stranger's pack exists.
  ///
  /// **[packId] is percent-encoded before it reaches the path.** It comes back
  /// out of storage, and a stored value is the one input nobody reviews.
  Future<FetchPackResult> fetchPack({
    required String accessToken,
    required String packId,
  }) async {
    final Uri url = _baseUrl.resolve('packs/${Uri.encodeComponent(packId)}');
    try {
      final HttpClientRequest request = await _transport.getUrl(url);
      _authorize(request, accessToken);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readFetchPack(response.statusCode, body);
    } on Exception catch (cause) {
      return FetchPackUnreachable(cause.toString());
    }
  }

  FetchPackResult _readFetchPack(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 200:
        try {
          return FetchPackDone(IssuedPack.fromJson(_object(body)));
        } on FormatException catch (cause) {
          return FetchPackFailed(status: status, reason: cause.message);
        }
      case 404:
        return const FetchPackGone();
      case 401:
        return FetchPackRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      default:
        return FetchPackFailed(
          status: status,
          reason: message.isEmpty ? body : message,
        );
    }
  }

  /// Sends a session's answers and reads back what they were worth.
  ///
  /// **The batch is one transaction on the far side.** Every source is resolved
  /// before anything is written, so a 404 means *nothing* was recorded — which
  /// is why that case is worth telling apart from a 400 here.
  ///
  /// **Unreachable is the one answer a retry is for.** The server drops a
  /// duplicate attempt by itself (migration 0004), so resending a batch that
  /// may or may not have landed is safe.
  Future<SyncResult> submitAttempts({
    required String accessToken,
    required List<AttemptSubmission> attempts,
  }) async {
    final Uri url = _baseUrl.resolve('attempts');
    try {
      final HttpClientRequest request = await _transport.postUrl(url);
      _authorize(request, accessToken);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(json.encode(<String, Object?>{
        'attempts': attempts.map((AttemptSubmission a) => a.toJson()).toList(),
      }));
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readSync(response.statusCode, body);
    } on Exception catch (cause) {
      return SyncUnreachable(cause.toString());
    }
  }

  SyncResult _readSync(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 200:
        try {
          final Object? verdicts = _object(body)['verdicts'];
          if (verdicts is! List<Object?>) {
            throw const FormatException('verdicts is not a list');
          }
          return SyncDone(verdicts
              .map((Object? v) => v is Map<String, Object?>
                  ? AttemptVerdict.fromJson(v)
                  : throw const FormatException('a verdict is not an object'))
              .toList());
        } on FormatException catch (cause) {
          return SyncFailed(status: status, reason: cause.message);
        }
      case 400:
        return SyncMalformed(message);
      case 404:
        return SyncNoSuchItem(
          tag: error['error'] as String? ?? 'no_such_item',
          message: message,
        );
      case 401:
        return SyncRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      default:
        return SyncFailed(status: status, reason: message.isEmpty ? body : message);
    }
  }

  /// The player's sessions, newest first.
  ///
  /// **An empty list is a success.** A player who has linked and not yet synced
  /// has no history, and a client that read that as a failure would apologise
  /// for the ordinary case.
  Future<HistoryResult> getHistory(String accessToken) async {
    final Uri url = _baseUrl.resolve('me/history');
    try {
      final HttpClientRequest request = await _transport.getUrl(url);
      _authorize(request, accessToken);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readHistory(response.statusCode, body);
    } on Exception catch (cause) {
      return HistoryUnreachable(cause.toString());
    }
  }

  HistoryResult _readHistory(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 200:
        try {
          return HistoryFound(History.fromJson(_object(body)));
        } on FormatException catch (cause) {
          return HistoryFailed(status: status, reason: cause.message);
        }
      case 404:
        return const HistoryNoPlayer();
      case 401:
        return HistoryRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      default:
        return HistoryFailed(status: status, reason: message.isEmpty ? body : message);
    }
  }

  /// Erases the player behind the token, and everything referencing them.
  ///
  /// **It does not delete the account.** Identity lives with Neon Auth; the
  /// server holds no credential that could remove it, and says so in the
  /// operation's description. The email and the sign-in survive this call.
  ///
  /// **A success is a 204 and therefore has no body to read** — see
  /// [EraseResult]. A client that parsed one anyway would turn a successful
  /// erasure into a `FormatException` a player reads as a failure, and then not
  /// retry, because the row really is gone.
  Future<EraseResult> eraseMe(String accessToken) async {
    final Uri url = _baseUrl.resolve('me');
    try {
      final HttpClientRequest request = await _transport.deleteUrl(url);
      _authorize(request, accessToken);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await _drain(response);
      return _readErase(response.statusCode, body);
    } on Exception catch (cause) {
      return EraseUnreachable(cause.toString());
    }
  }

  EraseResult _readErase(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 204:
        return const EraseDone();
      case 404:
        return const EraseNothingThere();
      case 401:
        return EraseRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      default:
        return EraseFailed(status: status, reason: message.isEmpty ? body : message);
    }
  }

  LinkResult _readLink(int status, String body) {
    final Map<String, Object?> error = _errorOr(body);
    final String message = error['message'] as String? ?? '';
    switch (status) {
      case 200:
        try {
          return LinkDone(Me.fromJson(_object(body)));
        } on FormatException catch (cause) {
          return LinkFailed(status: status, reason: cause.message);
        }
      case 400:
        return LinkMalformed(message);
      case 401:
        return LinkRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: message,
        );
      case 409:
        return LinkConflict(message);
      default:
        return LinkFailed(status: status, reason: message.isEmpty ? body : message);
    }
  }

  /// One `GET /me` status and body, as a [MeResult].
  MeResult _readMe(int status, String body) {
    switch (status) {
      case 200:
        try {
          return MeFound(Me.fromJson(_object(body)));
        } on FormatException catch (cause) {
          return MeFailed(status: status, reason: cause.message);
        }
      case 401:
        final Map<String, Object?> error = _errorOr(body);
        return MeRejected(
          tag: error['error'] as String? ?? 'unauthenticated',
          message: error['message'] as String? ?? '',
        );
      case 404:
        return const MeNoPlayer();
      default:
        return MeFailed(status: status, reason: _errorOr(body)['message'] as String? ?? body);
    }
  }

  Map<String, Object?> _object(String body) {
    final Object? decoded = json.decode(body);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('the body is not a JSON object', body);
    }
    return decoded;
  }

  /// The frozen `Error` shape if the body is one, and an empty map otherwise.
  ///
  /// A failing server is exactly the server most likely to answer with an HTML
  /// error page from something in front of it, so this never throws.
  Map<String, Object?> _errorOr(String body) {
    try {
      return _object(body);
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  /// Releases the underlying connections. Call it when the app is done.
  void close() => _transport.close();
}
