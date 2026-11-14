import 'package:flutter_test/flutter_test.dart';
import 'package:my_ai_chatbot/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthService Strict Email & Account Validation Tests', () {
    test('isValidEmail accepts valid formats and rejects wrong formats', () {
      expect(AuthService.isValidEmail('user@gmail.com'), isTrue);
      expect(AuthService.isValidEmail('alex.smith@yahoo.co.uk'), isTrue);
      expect(AuthService.isValidEmail('john+tag@company.org'), isTrue);

      expect(AuthService.isValidEmail(''), isFalse);
      expect(AuthService.isValidEmail('abc'), isFalse);
      expect(AuthService.isValidEmail('abc@'), isFalse);
      expect(AuthService.isValidEmail('abc@com'), isFalse);
      expect(AuthService.isValidEmail('abc@.com'), isFalse);
      expect(AuthService.isValidEmail('user name@gmail.com'), isFalse);
      expect(AuthService.isValidEmail('user@wrong..com'), isFalse);
    });

    test('isValidGmail strictly requires @gmail.com domain', () {
      expect(AuthService.isValidGmail('myemail@gmail.com'), isTrue);
      expect(AuthService.isValidGmail('MYEMAIL@GMAIL.COM'), isTrue);

      expect(AuthService.isValidGmail('myemail@yahoo.com'), isFalse);
      expect(AuthService.isValidGmail('myemail@outlook.com'), isFalse);
      expect(AuthService.isValidGmail('myemail@gmail.co'), isFalse);
    });

    test('Sign In rejects non-existent / wrong emails with clear error message', () async {
      final auth = AuthService();

      expect(
        () => auth.signInWithEmailPassword(
          email: 'notregistered@gmail.com',
          password: 'password123',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('No account found with this email'))),
      );
    });

    test('Sign In rejects malformed email with invalid format error', () async {
      final auth = AuthService();

      expect(
        () => auth.signInWithEmailPassword(
          email: 'wrong-email-format',
          password: 'password123',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Invalid email format'))),
      );
    });

    test('Sign In rejects wrong password for an existing account', () async {
      final auth = AuthService();

      // Sign up first
      await auth.signUpWithEmailPassword(
        name: 'Sarah Connor',
        email: 'sarah@gmail.com',
        password: 'correctpassword',
      );

      // Attempt login with wrong password
      expect(
        () => auth.signInWithEmailPassword(
          email: 'sarah@gmail.com',
          password: 'wrongpassword',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Your password is wrong'))),
      );

      // Login with correct password succeeds
      final user = await auth.signInWithEmailPassword(
        email: 'sarah@gmail.com',
        password: 'correctpassword',
      );
      expect(user.name, 'Sarah Connor');
      expect(user.email, 'sarah@gmail.com');
    });

    test('Pre-seeded account laxmikumbhar589@gmail.com displays "Your password is wrong" when password mismatch', () async {
      final auth = AuthService();

      expect(
        () => auth.signInWithEmailPassword(
          email: 'laxmikumbhar589@gmail.com',
          password: 'third@9172',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Your password is wrong'))),
      );

      // Logging in with correct default password succeeds
      final user = await auth.signInWithEmailPassword(
        email: 'laxmikumbhar589@gmail.com',
        password: 'password123',
      );
      expect(user.name, 'Laxmi Kumbhar');
      expect(user.email, 'laxmikumbhar589@gmail.com');
    });

    test('Google Sign In rejects invalid Gmail address', () async {
      final auth = AuthService();

      expect(
        () => auth.signInWithGoogle(email: 'fake_email@yahoo.com'),
        throwsA(predicate((e) =>
            e.toString().contains('Must end with @gmail.com'))),
      );

      final user = await auth.signInWithGoogle(email: 'realuser@gmail.com');
      expect(user.email, 'realuser@gmail.com');
      expect(user.authProvider, 'google');
    });
  });
}

