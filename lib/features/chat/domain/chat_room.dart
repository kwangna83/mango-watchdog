class ChatRoom {
  const ChatRoom({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final String type;
}

class RoomMember {
  const RoomMember({
    required this.roomId,
    required this.userId,
    required this.role,
  });

  final String roomId;
  final String userId;
  final String role;
}
