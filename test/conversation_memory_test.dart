import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_ai_chatbot/models/chat_message.dart';
import 'package:my_ai_chatbot/services/gemini_service.dart';

void main() {
  String apiKey = '';

  setUpAll(() {
    final envFile = File('.env');
    if (envFile.existsSync()) {
      final lines = envFile.readAsLinesSync();
      for (final line in lines) {
        if (line.startsWith('GEMINI_API_KEY=')) {
          apiKey = line.substring('GEMINI_API_KEY='.length).trim();
          break;
        }
      }
    }
  });

  group('GeminiService Memory and Logic Tests', () {
    test('buildHistoryFromMessages creates valid alternating user/model turns', () {
      final messages = [
        ChatMessage(text: 'Hello', isUser: true),
        ChatMessage(text: 'Hi there!', isUser: false),
        ChatMessage(text: 'What is 2+2?', isUser: true),
        ChatMessage(text: '2+2 is 4.', isUser: false),
      ];

      final history = GeminiService.buildHistoryFromMessages(messages);
      expect(history.length, 4);
      expect(history[0].role, 'user');
      expect(history[1].role, 'model');
      expect(history[2].role, 'user');
      expect(history[3].role, 'model');
    });

    test('buildHistoryFromMessages merges consecutive user messages and drops trailing user', () {
      final messages = [
        ChatMessage(text: 'Question part 1', isUser: true),
        ChatMessage(text: 'Question part 2', isUser: true),
        ChatMessage(text: 'Answer', isUser: false),
        ChatMessage(text: 'Unanswered prompt', isUser: true),
      ];

      final history = GeminiService.buildHistoryFromMessages(messages);
      expect(history.length, 2);
      expect(history[0].role, 'user');
      expect(history[1].role, 'model');
    });

    test('Live multi-turn conversation retains context, supports new chat & session restore', () async {
      if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY_HERE') {
        return;
      }

      final service = GeminiService();
      service.initialize(apiKey);
      expect(service.isReady, isTrue);

      // Turn 1
      final reply1 = await service.sendMessage('What is the capital of Italy?');
      expect(reply1.toLowerCase(), contains('rome'));
      expect(reply1.toLowerCase().startsWith("hello, i'm myaichatbot"), isFalse);

      // Turn 2: Follow-up using pronoun "its"
      final reply2 = await service.sendMessage('What is its most famous ancient amphitheatre?');
      expect(reply2.toLowerCase(), contains('colosseum'));
      expect(reply2.toLowerCase().startsWith("hello, i'm myaichatbot"), isFalse);

      // Turn 3: Start New Chat resets memory
      service.startNewChat();
      final reply3 = await service.sendMessage('What city were we just talking about?');
      expect(reply3.toLowerCase().contains('rome'), isFalse);

      // Turn 4: Restore Session restores memory
      service.restoreSession([
        ChatMessage(text: 'What is the capital of Japan?', isUser: true),
        ChatMessage(text: 'The capital of Japan is Tokyo.', isUser: false),
      ]);
      final reply4 = await service.sendMessage('What is its approximate population?');
      expect(
        reply4.toLowerCase().contains('tokyo') || reply4.toLowerCase().contains('million'),
        isTrue,
      );
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
