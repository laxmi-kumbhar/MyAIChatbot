import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    if (message.isUser) {
      // User message (Right-aligned, mobile-optimized bubble)
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: screenWidth > 600 ? 560 : screenWidth * 0.82,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E3A8A), const Color(0xFF2563EB)]
                        : [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SelectableText(
                  message.text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // AI message (Left-aligned, ChatGPT & Gemini modern style)
    final isStreamingWithoutText = message.isStreaming && message.text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4285F4), Color(0xFF9B51E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          // AI Content & Copy button
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: message.isError
                        ? (isDark
                            ? const Color(0xFF3E1C1C)
                            : const Color(0xFFFFEBEE))
                        : (isDark
                            ? const Color(0xFF212121)
                            : const Color(0xFFF7F7F8)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: message.isError
                          ? Colors.red.withValues(alpha: 0.4)
                          : (isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFE5E5E5)),
                      width: 1,
                    ),
                  ),
                  child: isStreamingWithoutText
                      ? const TypingDotsIndicator()
                      : MarkdownBody(
                          data: message.isStreaming
                              ? '${message.text} ▌'
                              : message.text,
                          selectable: !message.isStreaming,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: TextStyle(
                              fontSize: 14.5,
                              height: 1.55,
                              color: message.isError
                                  ? Colors.redAccent
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.92)
                                      : Colors.black87),
                            ),
                            h1: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            h2: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            h3: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            listBullet: TextStyle(
                              fontSize: 14.5,
                              height: 1.55,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            code: TextStyle(
                              backgroundColor: isDark
                                  ? const Color(0xFF191919)
                                  : const Color(0xFFEAEAEA),
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: isDark ? const Color(0xFF9CDCFE) : const Color(0xFFC7254E),
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                            codeblockDecoration: BoxDecoration(
                              color: isDark ? const Color(0xFF141414) : const Color(0xFFF6F8FA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFD0D7DE),
                              ),
                            ),
                            tableBorder: TableBorder.all(
                              color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                              width: 1,
                            ),
                            tableHead: const TextStyle(fontWeight: FontWeight.bold),
                            tableCellsPadding: const EdgeInsets.all(8),
                          ),
                        ),
                ),
                if (!message.isStreaming && !isStreamingWithoutText) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        tooltip: 'Copy response',
                        color: isDark ? Colors.white54 : Colors.black45,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        onPressed: () => _copyToClipboard(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'MyAIChatbot',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TypingDotsIndicator extends StatefulWidget {
  const TypingDotsIndicator({super.key});

  @override
  State<TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final delay = index * 0.2;
              final raw = (_controller.value - delay);
              final progress = (raw < 0 ? raw + 1.0 : raw) % 1.0;
              final wave = (progress < 0.5 ? progress * 2 : (1.0 - progress) * 2);
              final opacity = 0.35 + (0.65 * wave);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blueAccent.withValues(alpha: opacity),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withValues(alpha: 0.3 * wave),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                transform: Matrix4.translationValues(0, -3.5 * wave, 0),
              );
            },
          );
        }),
      ),
    );
  }
}
