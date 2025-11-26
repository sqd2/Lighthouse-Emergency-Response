import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

/// Chat screen for communication between dispatcher and citizen
class ChatScreen extends StatefulWidget {
  final String alertId;
  final String userRole; // 'citizen' or 'dispatcher'
  final String otherPartyEmail; // Email of the person you're chatting with

  const ChatScreen({
    super.key,
    required this.alertId,
    required this.userRole,
    required this.otherPartyEmail,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _imagePicker = ImagePicker();

  bool _isSending = false;
  bool _isRecording = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendTextMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderEmail': user.email ?? 'Unknown',
        'senderRole': widget.userRole,
        'messageType': 'text',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send message: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendImageMessage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isSending = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Upload image to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(widget.alertId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Use putData for all platforms (works on both web and mobile)
      final bytes = await image.readAsBytes();
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final imageUrl = await snapshot.ref.getDownloadURL();

      // Send message with image URL
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderEmail': user.email ?? 'Unknown',
        'senderRole': widget.userRole,
        'messageType': 'image',
        'message': '',
        'mediaUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send image: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        String path;

        if (kIsWeb) {
          // For web, record with path parameter
          path = 'web_recording_${DateTime.now().millisecondsSinceEpoch}';
          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.wav),
            path: path,
          );
        } else {
          // For mobile/desktop, use simple path
          path = 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc),
            path: path,
          );
        }

        setState(() {
          _isRecording = true;
          _recordingPath = path;
          _recordingDuration = 0;
        });

        // Start timer
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordingDuration++);
          }
        });
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      _recordingTimer?.cancel();

      final path = await _audioRecorder.stop();

      if (path == null) {
        setState(() => _isRecording = false);
        return;
      }

      setState(() {
        _isRecording = false;
        _isSending = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Upload voice message to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_voice')
          .child(widget.alertId)
          .child('${DateTime.now().millisecondsSinceEpoch}.${kIsWeb ? "wav" : "m4a"}');

      // Get audio bytes and upload (web only for now)
      if (!kIsWeb) {
        throw Exception('Voice recording is only supported on web platform');
      }

      // For web, the path is a blob URL - fetch it
      Uint8List bytes;
      if (path.startsWith('blob:')) {
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        throw Exception('Unexpected web recording path format: $path');
      }

      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'audio/wav'),
      );

      final snapshot = await uploadTask;
      final voiceUrl = await snapshot.ref.getDownloadURL();

      // Send voice message
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderEmail': user.email ?? 'Unknown',
        'senderRole': widget.userRole,
        'messageType': 'voice',
        'message': '',
        'mediaUrl': voiceUrl,
        'voiceDuration': _recordingDuration,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send voice message: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isRecording = false;
          _recordingDuration = 0;
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .collection('messages')
          .where('senderId', isNotEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Emergency Chat'),
            Text(
              widget.otherPartyEmail,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('emergency_alerts')
                  .doc(widget.alertId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading messages: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs
                    .map((doc) => ChatMessage.fromFirestore(
                          doc.id,
                          doc.data() as Map<String, dynamic>,
                        ))
                    .toList();

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == user?.uid;

                    return _MessageBubble(
                      message: message,
                      isMe: isMe,
                      timestamp: _formatTimestamp(message.timestamp),
                      formatDuration: _formatDuration,
                    );
                  },
                );
              },
            ),
          ),

          // Recording indicator
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border(
                  top: BorderSide(color: Colors.red.shade200),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.mic, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recording...',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatDuration(_recordingDuration),
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _cancelRecording,
                    tooltip: 'Cancel',
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green),
                    onPressed: _stopRecordingAndSend,
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Image button
                  IconButton(
                    icon: const Icon(Icons.image, color: Colors.blue),
                    onPressed: _isSending || _isRecording ? null : _sendImageMessage,
                    tooltip: 'Send image',
                  ),

                  // Voice button (web only)
                  if (kIsWeb)
                    IconButton(
                      icon: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.red : Colors.blue,
                      ),
                      onPressed: _isSending
                          ? null
                          : (_isRecording ? _stopRecordingAndSend : _startRecording),
                      tooltip: _isRecording ? 'Send voice' : 'Record voice',
                    ),

                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendTextMessage(),
                      enabled: !_isSending && !_isRecording,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send button
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: (_isSending || _isRecording) ? null : _sendTextMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isMe;
  final String timestamp;
  final String Function(int) formatDuration;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.timestamp,
    required this.formatDuration,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  double _playbackPosition = 0.0;

  @override
  void initState() {
    super.initState();

    if (widget.message.messageType == 'voice') {
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      _audioPlayer.onPositionChanged.listen((position) {
        if (mounted && widget.message.voiceDuration != null) {
          setState(() {
            _playbackPosition = position.inSeconds / widget.message.voiceDuration!;
          });
        }
      });

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _playbackPosition = 0.0;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (widget.message.mediaUrl != null) {
        await _audioPlayer.play(UrlSource(widget.message.mediaUrl!));
      }
    }
  }

  Widget _buildMessageContent() {
    switch (widget.message.messageType) {
      case 'image':
        return GestureDetector(
          onTap: () => _showEnlargedImage(context, widget.message.mediaUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.message.mediaUrl!,
              width: 200,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: 200,
                  height: 200,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.error, color: Colors.red),
                );
              },
            ),
          ),
        );

      case 'voice':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: widget.isMe ? Colors.white : Colors.blue,
                ),
                onPressed: _togglePlayback,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: _playbackPosition,
                      backgroundColor: widget.isMe
                          ? Colors.blue.shade300
                          : Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isMe ? Colors.white : Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.formatDuration(widget.message.voiceDuration ?? 0),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isMe ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'text':
      default:
        return Text(
          widget.message.message,
          style: TextStyle(
            color: widget.isMe ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        );
    }
  }

  void _showEnlargedImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Dismiss on background tap
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black.withOpacity(0.8),
              ),
            ),
            // Centered image
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.blue : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
                  bottomRight: Radius.circular(widget.isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.message.senderRole == 'dispatcher'
                            ? 'Dispatcher'
                            : 'Citizen',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  _buildMessageContent(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              child: Text(
                widget.timestamp,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
