import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/gemini_service.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _currentMessagesKey = 'my_ai_chatbot_active_messages_v1';
  static const String _savedSessionsKey = 'my_ai_chatbot_saved_sessions_v1';

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GeminiService _geminiService = GeminiService();

  final List<ChatMessage> _messages = [];
  final List<List<ChatMessage>> _savedSessions = [];
  bool _isLoading = false;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _loadSavedChatHistory();
  }

  /// Loads both the active conversation and past chat sessions from local persistent storage
  Future<void> _loadSavedChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load saved past sessions in sidebar history
      final savedSessionsJson = prefs.getStringList(_savedSessionsKey);
      if (savedSessionsJson != null && savedSessionsJson.isNotEmpty) {
        final List<List<ChatMessage>> loaded = [];
        for (final sessionStr in savedSessionsJson) {
          try {
            final List<dynamic> list = jsonDecode(sessionStr) as List<dynamic>;
            final session = list
                .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
                .toList();
            if (session.isNotEmpty) {
              loaded.add(session);
            }
          } catch (_) {}
        }
        if (mounted && loaded.isNotEmpty) {
          setState(() {
            _savedSessions.clear();
            _savedSessions.addAll(loaded);
          });
        }
      }

      // 2. Load the active chat conversation
      final activeMessagesJson = prefs.getString(_currentMessagesKey);
      if (activeMessagesJson != null && activeMessagesJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(activeMessagesJson) as List<dynamic>;
        final current = list
            .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
            .toList();
        if (mounted && current.isNotEmpty) {
          setState(() {
            _messages.clear();
            _messages.addAll(current);
          });
          // Restore conversation context to Gemini service
          _geminiService.restoreSession(current);
          _scrollToBottom(smooth: false);
        }
      }
    } catch (e) {
      debugPrint('Error loading saved chat history: $e');
    }
  }

  /// Automatically persists active conversation and history to browser/device storage
  Future<void> _persistHistoryToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Persist active conversation
      if (_messages.isNotEmpty) {
        final activeList = _messages.map((m) => m.toMap()).toList();
        await prefs.setString(_currentMessagesKey, jsonEncode(activeList));
      } else {
        await prefs.remove(_currentMessagesKey);
      }

      // 2. Persist saved past sessions
      final savedList = _savedSessions.map((session) {
        return jsonEncode(session.map((m) => m.toMap()).toList());
      }).toList();
      await prefs.setStringList(_savedSessionsKey, savedList);
    } catch (e) {
      debugPrint('Error persisting chat history: $e');
    }
  }

  Future<void> _loadApiKey() async {
    // 1. Check compile-time environment variable (injected securely from GitHub Secrets for deployed web)
    const defineKey = String.fromEnvironment('GEMINI_API_KEY');

    // 2. Check local user-entered preference (so user can override if they wish)
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKey = prefs.getString('gemini_api_key');
      if (storedKey != null && storedKey.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _geminiService.initialize(storedKey.trim());
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Error loading key from SharedPreferences: $e');
    }

    // 3. Check .env if available
    if (dotenv.isInitialized) {
      final envKey = dotenv.env['GEMINI_API_KEY'];
      if (envKey != null && envKey.isNotEmpty && envKey != 'YOUR_GEMINI_API_KEY_HERE') {
        if (mounted) {
          setState(() {
            _geminiService.initialize(envKey);
          });
        }
        return;
      }
    }

    // 4. Fallback to default active key
    if (defineKey.isNotEmpty && defineKey != 'YOUR_GEMINI_API_KEY_HERE') {
      if (mounted) {
        setState(() {
          _geminiService.initialize(defineKey);
        });
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (smooth) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _stopGenerating() {
    if (_isLoading) {
      setState(() {
        _isCancelled = true;
        _isLoading = false;
        if (_messages.isNotEmpty && _messages.last.isStreaming) {
          _messages[_messages.length - 1] = _messages.last.copyWith(isStreaming: false);
        }
      });
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!_geminiService.isReady) {
      _showApiKeyDialog(
        notice: 'Please enter your Gemini API key to start chatting.',
      );
      return;
    }

    _textController.clear();
    _isCancelled = false;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      // Immediately display AI bubble with typing dots (ChatGPT & Gemini style)
      _messages.add(ChatMessage(text: '', isUser: false, isStreaming: true));
      _isLoading = true;
    });
    _scrollToBottom();

    String accumulated = '';

    try {
      final stream = _geminiService.sendMessageStream(text);
      await for (final chunk in stream) {
        if (!mounted || _isCancelled) return;
        accumulated += chunk;
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: accumulated,
            isUser: false,
            isStreaming: true,
          );
        });
        _scrollToBottom(smooth: false);
      }

      if (mounted && !_isCancelled) {
        setState(() {
          if (accumulated.trim().isEmpty) {
            _messages[_messages.length - 1] = ChatMessage(
              text: 'I received an empty response. Please try asking again.',
              isUser: false,
              isStreaming: false,
            );
          } else {
            _messages[_messages.length - 1] = ChatMessage(
              text: accumulated,
              isUser: false,
              isStreaming: false,
            );
          }
          _isLoading = false;
        });
        _scrollToBottom();
        _persistHistoryToStorage();
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        final errorText = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: accumulated.isNotEmpty
                ? '$accumulated\n\n*[Error: $errorText]*'
                : errorText,
            isUser: false,
            isError: true,
            isStreaming: false,
          );
          _isLoading = false;
        });
        _scrollToBottom();
        _persistHistoryToStorage();
      }
    }
  }

  void _startNewChat() {
    if (_messages.isNotEmpty) {
      setState(() {
        _savedSessions.insert(0, List<ChatMessage>.from(_messages));
        _messages.clear();
      });
      _persistHistoryToStorage();
      _geminiService.startNewChat();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Started a new conversation'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _restoreSession(List<ChatMessage> session) {
    setState(() {
      if (_messages.isNotEmpty) {
        _savedSessions.insert(0, List<ChatMessage>.from(_messages));
      }
      _savedSessions.removeWhere((s) =>
          identical(s, session) ||
          (s.length == session.length &&
              s.isNotEmpty &&
              session.isNotEmpty &&
              s.first.text == session.first.text));
      _messages.clear();
      _messages.addAll(session);
      _geminiService.restoreSession(session);
    });
    _persistHistoryToStorage();
    Navigator.of(context).pop(); // Close drawer
    _scrollToBottom();
  }

  void _clearAllHistory() {
    setState(() {
      _savedSessions.clear();
    });
    _persistHistoryToStorage();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cleared all chat history'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showApiKeyDialog({String? notice}) {
    final controller = TextEditingController(text: _geminiService.currentApiKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Gemini API Key'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notice != null) ...[
              Text(
                notice,
                style: const TextStyle(color: Colors.amber, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Get a free Gemini API key at:\nhttps://aistudio.google.com/',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Paste AIzaSy... key here',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newKey = controller.text.trim();
              if (newKey.isNotEmpty) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('gemini_api_key', newKey);
                } catch (e) {
                  debugPrint('Could not save to SharedPreferences: $e');
                }

                if (!mounted) return;
                setState(() {
                  _geminiService.initialize(newKey);
                });
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('API key permanently saved on this device!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9B51E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text(
              'MyAIChatbot',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: const Text(
                'Flash',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 21),
            tooltip: 'New Chat',
            onPressed: _startNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.key_outlined, size: 21),
            tooltip: 'API Key',
            onPressed: () => _showApiKeyDialog(),
          ),
        ],
      ),
      drawer: _buildDrawer(isDark),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                if (!_geminiService.isReady) _buildApiKeyWarningBanner(),
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return ChatBubble(message: _messages[index]);
                          },
                        ),
                ),
                _buildInputBar(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiKeyWarningBanner() {
    return Container(
      color: Colors.amber.shade900.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Gemini API key is needed to start chatting.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => _showApiKeyDialog(),
            child: const Text('Add Key', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactMobile = screenWidth < 500;

    final suggestions = [
      (
        icon: Icons.lightbulb_outline_rounded,
        color: const Color(0xFFF59E0B),
        title: 'Creative Ideas',
        prompt: 'Give me 5 creative ideas for a weekend project',
      ),
      (
        icon: Icons.code_rounded,
        color: const Color(0xFF10B981),
        title: 'Code & Debug',
        prompt: 'Write a Python function to reverse a string',
      ),
      (
        icon: Icons.flight_takeoff_rounded,
        color: const Color(0xFF3B82F6),
        title: 'Travel Guide',
        prompt: 'Plan a 3-day travel itinerary for Tokyo',
      ),
      (
        icon: Icons.psychology_outlined,
        color: const Color(0xFF8B5CF6),
        title: 'Explain Simply',
        prompt: 'Explain quantum computing in simple terms',
      ),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isCompactMobile ? 16.0 : 24.0,
          vertical: 20.0,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9B51E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(29),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'MyAIChatbot',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask anything or tap a prompt to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            // Responsive cards layout for mobile & tablet
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 450;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isNarrow ? 1 : 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: isNarrow ? 68 : 88,
                  ),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final item = suggestions[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _sendMessage(item.prompt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF212121) : const Color(0xFFF7F7F8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(item.icon, color: item.color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    item.title,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.prompt,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171717) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242424) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 5,
                    style: TextStyle(
                      fontSize: 16, // Critical: 16px prevents iOS Safari from auto-zooming
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Ask anything...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 12.0,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isLoading
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: _isLoading ? Colors.redAccent : null,
                ),
                child: IconButton(
                  onPressed: _isLoading ? _stopGenerating : () => _sendMessage(),
                  icon: Icon(
                    _isLoading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  tooltip: _isLoading ? 'Stop generating' : 'Send message',
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MyAIChatbot may display inaccurate info, so verify important facts.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(bool isDark) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App Branding Header in Drawer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F4F6),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF9B51E0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MyAIChatbot',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'AI Assistant • Fast & Free',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _startNewChat();
                },
                icon: const Icon(Icons.add),
                label: const Text('Start New Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Conversation History',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.grey,
                    ),
                  ),
                  if (_savedSessions.isNotEmpty)
                    InkWell(
                      onTap: _clearAllHistory,
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _savedSessions.isEmpty
                  ? Center(
                      child: Text(
                        'No previous chats yet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _savedSessions.length,
                      itemBuilder: (context, index) {
                        final session = _savedSessions[index];
                        final previewText = session.firstWhere(
                          (m) => m.isUser,
                          orElse: () => session.first,
                        ).text;

                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline, size: 18),
                          title: Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            tooltip: 'Delete chat',
                            onPressed: () {
                              setState(() {
                                _savedSessions.removeAt(index);
                              });
                              _persistHistoryToStorage();
                            },
                          ),
                          onTap: () => _restoreSession(session),
                        );
                      },
                    ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('API Key Settings'),
              onTap: () {
                Navigator.of(context).pop();
                _showApiKeyDialog();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Model: ${_geminiService.activeModelName}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
