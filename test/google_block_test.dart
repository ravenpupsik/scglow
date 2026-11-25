import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/core/web_session.dart';

void main() {
  test('Google embedded-browser block is recognised by URL or page text', () {
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://accounts.google.com/signin/oauth/error?authError=Error+403:+disallowed_useragent',
      ),
      isTrue,
    );
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://accounts.google.com/v3/signin/rejected?continue=x',
      ),
      isTrue,
    );
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://accounts.google.com/v3/signin/identifier',
        "Couldn't sign you in\nThis browser or app may not be secure. Learn more",
      ),
      isTrue,
    );
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://accounts.google.com/v3/signin/identifier',
        'Не удалось войти в аккаунт. Этот браузер или приложение могут быть небезопасными.',
      ),
      isTrue,
    );
  });

  test('normal Google and SoundCloud pages are not treated as blocked', () {
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://accounts.google.com/v3/signin/identifier',
        'Sign in with Google',
      ),
      isFalse,
    );
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://soundcloud.com/signin',
        'This browser or app may not be secure',
      ),
      isFalse,
    );
    expect(
      WebSession.isGoogleEmbedBlock(
        'https://evil.example/?next=accounts.google.com&disallowed_useragent',
      ),
      isFalse,
    );
    expect(WebSession.isGoogleEmbedBlock(null), isFalse);
  });
}
