/// Model for chat messages between dispatcher and citizen
class ChatMessage {
  final String id;
  final String senderId;
  final String senderEmail;
  final String senderRole; // 'citizen' or 'dispatcher'
  final String message;
  final DateTime timestamp;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderEmail,
    required this.senderRole,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderEmail': senderEmail,
      'senderRole': senderRole,
      'message': message,
      'timestamp': timestamp,
      'isRead': isRead,
    };
  }

  factory ChatMessage.fromFirestore(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      senderEmail: data['senderEmail'] ?? '',
      senderRole: data['senderRole'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }
}
