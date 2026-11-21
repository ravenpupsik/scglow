import 'models.dart';

sealed class ScException implements Exception {
  const ScException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScAuthExpired extends ScException {
  const ScAuthExpired() : super('Session expired');
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

class ScUnplayable extends ScException {
  const ScUnplayable(super.message, [this.reason = Unavailable.removed]);

  final Unavailable reason;
}

String friendlyError(Object error) => switch (error) {
      ScAuthExpired() => 'Session expired',
      ScNetworkError() => 'No connection',
      ScUnplayable() => 'Unavailable',
      ScChanged(status: final int s) => 'SoundCloud changed something · $s',
      ScChanged() => 'SoundCloud changed something',
      _ => 'Something went wrong',
    };
