import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/chat_message.dart';

class GeminiService {
  GenerativeModel? _model;
  ChatSession? _chatSession;
  String _currentApiKey = '';
  int _currentModelIndex = 0;

  // High-availability fast models prioritized by free tier quota & low latency
  static const List<String> _candidateModels = [
    'gemini-3.5-flash-lite',
    'gemini-flash-lite-latest',
    'gemini-3.1-flash-lite',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
  ];

  // High-intelligence system instruction for world-class, engaging, and accurate responses
  static final Content _systemInstruction = Content.system(
    'You are MyAIChatbot, an intelligent, insightful, and versatile AI assistant powered by Gemini.\n\n'
    'CORE OBJECTIVES:\n'
    '1. Provide high-quality, comprehensive, and accurate answers to any inquiry.\n'
    '2. When explaining concepts, provide intuitive breakdowns, clear structure, and real-world examples.\n'
    '3. When providing code or technical solutions, write clean, production-ready, well-commented code with concise explanations.\n'
    '4. Format responses beautifully using Markdown: use bold highlights, headings (##, ###), bullet lists, tables, and syntax-highlighted code blocks where appropriate.\n'
    '5. Adapt depth dynamically: give direct answers for simple questions, and rich, well-organized answers for complex or open-ended topics.\n'
    '6. DO NOT introduce yourself ("Hello, I\'m MyAIChatbot") unless explicitly asked ("Who are you?", "What is your name?").\n'
    '7. DO NOT repeat greetings on follow-up questions in an ongoing conversation.\n'
    '8. Maintain full conversational context, smoothly handling pronouns, references, and follow-ups.',
  );

  String get activeModelName => _candidateModels[_currentModelIndex];
  String get currentApiKey => _currentApiKey;
  bool get isReady => _model != null && _chatSession != null;
  Iterable<Content>? get currentHistory => _chatSession?.history;

  /// Initialize or update the Gemini client with an API key
  void initialize(String apiKey) {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty || trimmedKey == 'YOUR_GEMINI_API_KEY_HERE') {
      _model = null;
      _chatSession = null;
      _currentApiKey = '';
      return;
    }

    _currentApiKey = trimmedKey;
    _currentModelIndex = 0;
    _initModel();
  }

  void _initModel({String? modelName, List<Content>? history}) {
    final chosenModel = modelName ?? _candidateModels[_currentModelIndex];
    _model = GenerativeModel(
      model: chosenModel,
      apiKey: _currentApiKey,
      systemInstruction: _systemInstruction,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 2048,
      ),
    );
    _chatSession = _model!.startChat(history: history);
  }

  /// Start a fresh conversation context (resets conversation memory)
  void startNewChat() {
    if (_model != null) {
      _chatSession = _model!.startChat();
    }
  }

  /// Restore an existing conversation into Gemini memory so follow-up questions work
  void restoreSession(List<ChatMessage> messages) {
    final history = buildHistoryFromMessages(messages);
    if (_model == null && _currentApiKey.isNotEmpty) {
      _initModel(history: history);
    } else if (_model != null) {
      _chatSession = _model!.startChat(history: history);
    }
  }

  /// Converts ChatMessage list into valid alternating user/model Content turns for Gemini
  static List<Content> buildHistoryFromMessages(List<ChatMessage> messages) {
    final history = <Content>[];
    final valid = messages.where((m) => !m.isError && m.text.trim().isNotEmpty).toList();

    for (final msg in valid) {
      if (msg.isUser) {
        // If two user messages in a row, merge text
        if (history.isNotEmpty && history.last.role == 'user') {
          final existing = history.last.parts.whereType<TextPart>().map((p) => p.text).join('\n');
          history[history.length - 1] = Content.text('$existing\n${msg.text.trim()}');
        } else {
          history.add(Content.text(msg.text.trim()));
        }
      } else {
        // Model message only allowed if preceded by a user message
        if (history.isNotEmpty && history.last.role == 'user') {
          history.add(Content.model([TextPart(msg.text.trim())]));
        }
      }
    }

    // History for startChat must end with a model response so next message is user
    while (history.isNotEmpty && history.last.role == 'user') {
      history.removeLast();
    }

    return history;
  }

  /// Send user message to Gemini using real-time streaming with multi-turn memory preserved.
  Stream<String> sendMessageStream(String prompt) async* {
    if (!isReady) {
      throw Exception(
        'Gemini API key is missing. Please set your API key in the .env file or via the top-right Settings icon.',
      );
    }

    for (int i = _currentModelIndex; i < _candidateModels.length; i++) {
      if (i != _currentModelIndex) {
        // Fallback: switch model while preserving existing conversation history
        final existingHistory = _chatSession?.history.toList() ?? [];
        _currentModelIndex = i;
        _initModel(modelName: _candidateModels[i], history: existingHistory);
      }

      try {
        final stream = _chatSession!.sendMessageStream(
          Content.text(prompt.trim()),
        );

        bool hasYielded = false;
        await for (final response in stream) {
          final text = response.text;
          if (text != null && text.isNotEmpty) {
            hasYielded = true;
            yield text;
          }
        }

        if (hasYielded) {
          _currentModelIndex = i; // Retain active fast model for subsequent queries
          return; // Success
        }
      } catch (e) {
        final err = e.toString();

        final isRecoverable = err.contains('503') ||
            err.contains('high demand') ||
            err.contains('UNAVAILABLE') ||
            err.contains('404') ||
            err.contains('not found') ||
            err.contains('no longer available') ||
            err.contains('Internal error') ||
            err.contains('RESOURCE_EXHAUSTED') ||
            err.contains('Quota exceeded') ||
            err.contains('429');

        if (isRecoverable && i < _candidateModels.length - 1) {
          // Immediately try next fast model candidate with history preserved
          continue;
        }

        if (err.contains('API_KEY_INVALID') || err.contains('403')) {
          throw Exception(
            'Invalid Gemini API Key. Please verify your key at https://aistudio.google.com/',
          );
        } else if (err.contains('RESOURCE_EXHAUSTED') || err.contains('Quota exceeded') || err.contains('429')) {
          throw Exception(
            'High traffic limit reached for this free model. Please wait a few moments and try again, or add a personal key in Settings.',
          );
        } else {
          throw Exception(
            err.replaceFirst('GenerativeAIServer Error: ', '')
               .replaceFirst('Exception: ', ''),
          );
        }
      }
    }

    throw Exception(
      'Could not get a response. Please try asking again in a moment.',
    );
  }

  /// Convenience non-streaming method (used for tests and full-block requests)
  Future<String> sendMessage(String prompt) async {
    final buffer = StringBuffer();
    await for (final chunk in sendMessageStream(prompt)) {
      buffer.write(chunk);
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw Exception('Received an empty response. Please try again.');
    }
    return result;
  }
}
