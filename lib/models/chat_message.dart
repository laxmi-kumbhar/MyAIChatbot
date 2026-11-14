class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final bool isStreaming;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.isError = false,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isError,
    bool? isStreaming,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toMap() => {
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'isError': isError,
    'isStreaming': isStreaming,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    text: map['text'] as String? ?? '',
    isUser: map['isUser'] as bool? ?? false,
    timestamp: map['timestamp'] != null
        ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
        : DateTime.now(),
    isError: map['isError'] as bool? ?? false,
    isStreaming: map['isStreaming'] as bool? ?? false,
  );
}

class ChatHistorySession {
  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  ChatHistorySession({
    required this.id,
    required this.title,
    required this.messages,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toMap()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatHistorySession.fromMap(Map<String, dynamic> map) => ChatHistorySession(
    id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: map['title'] as String? ?? 'Conversation',
    messages: (map['messages'] as List<dynamic>?)
            ?.map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
            .toList() ??
        [],
    updatedAt: map['updatedAt'] != null
        ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
