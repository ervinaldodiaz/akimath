/// What an auth call came back as — the shape of the answer, not the making of
/// it.
///
/// **Separate from `auth_client.dart` because this is data**, which is the
/// split `me_result.dart` already records and states the reason for: that file
/// imports `dart:io` and `dart:convert` to hold a socket, so a pure policy
/// switching on its results would reach a socket three hops away and
/// `pure_boundary_test.dart` would say so.
///
/// Two callers made the same split necessary here.
/// `features/account/policy/session.dart` carries an [AuthSession], and
/// `features/account/policy/session_restore.dart` switches on an [AuthResult];
/// both sit under a pure root.
///
/// `auth_client.dart` re-exports every name below, so an importer of the client
/// sees no difference.
library;

import 'package:meta/meta.dart';

/// A call that succeeded and returned nothing worth carrying.
@immutable
final class Accepted {
  const Accepted();
}

/// A Neon Auth session, as the thing needed to ask for a token.
///
/// **A cookie, because that is what the provider issues.** Better Auth's
/// `bearer` plugin would let the session travel in a header, and it is not in
/// `plugin_configs` — so the session is a `Set-Cookie` value that has to be
/// carried back. Held opaquely: nothing here parses it, and it is never logged.
///
/// **This is the durable half of being signed in**, and the access token is
/// not: `accessToken(session)` derives a short-lived JWT from this, which is
/// why a device that wants to survive a relaunch keeps the cookie and asks for
/// a token again on launch rather than storing one that has already expired.
@immutable
final class AuthSession {
  const AuthSession(this.cookie);

  /// The cookie header value to send back, verbatim.
  final String cookie;

  /// **A value, because `LinkedSession` compares by value.** Left to identity,
  /// two sessions holding the same cookie would be equal only when Dart
  /// canonicalised them — true for the `const` a test writes, false for the one
  /// a sign-in builds at runtime, which is the direction that makes a suite
  /// green and a device wrong.
  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.cookie == cookie;

  @override
  int get hashCode => cookie.hashCode;

  /// **Never the cookie.** `toString` reaches logs, crash reports and the
  /// debugger's watch pane, and a credential that appears in any of those has
  /// left the device.
  @override
  String toString() => 'AuthSession(<redacted>)';
}

/// What an auth call came back as.
@immutable
sealed class AuthResult<T> {
  const AuthResult();
}

/// The provider did what was asked.
@immutable
final class AuthOk<T> extends AuthResult<T> {
  const AuthOk(this.value);
  final T value;
}

/// The provider said no, for a reason a person can act on.
///
/// A wrong code, an address already taken, a password too short. `code` is the
/// provider's own machine-readable tag where it sent one.
@immutable
final class AuthRefused<T> extends AuthResult<T> {
  const AuthRefused({
    required this.status,
    required this.code,
    required this.message,
  });
  final int status;
  final String code;
  final String message;
}

/// An answer arrived and was not one this client can read.
@immutable
final class AuthFailed<T> extends AuthResult<T> {
  const AuthFailed({required this.status, required this.reason});
  final int status;
  final String reason;
}

/// No answer arrived at all.
@immutable
final class AuthUnreachable<T> extends AuthResult<T> {
  const AuthUnreachable(this.reason);
  final String reason;
}
