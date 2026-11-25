import 'models.dart';

sealed class ScException implements Exception {
  const ScException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScAuthExpired extends ScException {
  const ScAuthExpired([this.failure]) : super('Session expired');

  final AuthFailure? failure;
}

class AuthFailure {
  const AuthFailure({
    required this.method,
    required this.path,
    required this.status,
    this.botCheck = false,
    this.excerpt = '',
    this.clientIdRefreshed = false,
    this.via = 'direct',
  });

  final String method;
  final String path;
  final int status;
  final bool botCheck;

  final String excerpt;
  final bool clientIdRefreshed;
  final String via;

  String describe() => '$method $path -> $status [$via] botCheck=$botCheck '
      'clientIdRefreshed=$clientIdRefreshed body="$excerpt"';
}

class ScChanged extends ScException {
  const ScChanged([this.details, this.status])
      : super('SoundCloud changed something');

  final String? details;

  final int? status;

  @override
  String toString() =>
      details == null ? message : '$message ($details)';
}

class ScNetworkError extends ScException {
  const ScNetworkError() : super('No connection');
}

class ScStreamFailed extends ScException {
  const ScStreamFailed() : super("Couldn't load this track");
}

class ScUnplayable extends ScException {
  const ScUnplayable(super.message, [this.reason = Unavailable.removed]);

  final Unavailable reason;
}

String friendlyError(Object error) => switch (error) {
      ScAuthExpired() => "Couldn't confirm sign-in",
      ScNetworkError() => 'No connection',
      ScStreamFailed() => "Couldn't load this track",
      ScUnplayable() => 'Unavailable',
      ScChanged(status: final int s) => 'SoundCloud changed something · $s',
      ScChanged() => 'SoundCloud changed something',
      _ => 'Something went wrong',
    };
