/// Model for chat messages between dispatcher and citizen
class ChatMessage {
  final String id;
  final String senderId;
  final String senderEmail;
  final String senderRole; // 'citizen' or 'dispatcher'
  final String messageType; // 'text', 'image', 'voice'
  final String message; // For text messages or caption
  final String? mediaUrl; // URL for image or voice file
  final int? voiceDuration; // Duration in seconds for voice messages
  final DateTime timestamp;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderEmail,
    required this.senderRole,
    this.messageType = 'text',
    required this.message,
    this.mediaUrl,
    this.voiceDuration,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderEmail': senderEmail,
      'senderRole': senderRole,
      'messageType': messageType,
      'message': message,
      'mediaUrl': mediaUrl,
      'voiceDuration': voiceDuration,
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
      messageType: data['messageType'] ?? 'text',
      message: data['message'] ?? '',
      mediaUrl: data['mediaUrl'],
      voiceDuration: data['voiceDuration'],
      timestamp: (data['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }
}
