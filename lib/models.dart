/// Datos que entrega la API móvil.
library;

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

double _toDouble(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

List<String> _stringList(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

class AppUser {
  const AppUser({required this.id, required this.name, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'].toString(),
    name: json['name'] as String,
    email: json['email'] as String,
  );

  final String id;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class DiagramSummary {
  const DiagramSummary({
    required this.id,
    required this.title,
    required this.isOwner,
    required this.classesCount,
    required this.relationshipsCount,
    required this.isLive,
    this.lastSavedAt,
  });

  factory DiagramSummary.fromJson(Map<String, dynamic> json) => DiagramSummary(
    id: json['id'].toString(),
    title: json['title'] as String? ?? 'Sin título',
    isOwner: json['isOwner'] == true,
    classesCount: json['classesCount'] as int? ?? 0,
    relationshipsCount: json['relationshipsCount'] as int? ?? 0,
    isLive: json['isLive'] == true,
    lastSavedAt: _parseDate(json['lastSavedAt']),
  );

  final String id;
  final String title;
  final bool isOwner;
  final int classesCount;
  final int relationshipsCount;
  final bool isLive;
  final DateTime? lastSavedAt;
}

class UmlClass {
  const UmlClass({
    required this.id,
    required this.name,
    required this.kind,
    required this.attributes,
    required this.methods,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory UmlClass.fromJson(Map<String, dynamic> json) => UmlClass(
    id: json['id'].toString(),
    name: json['name'] as String? ?? 'SinNombre',
    kind: json['kind'] as String? ?? 'class',
    attributes: _stringList(json['attributes']),
    methods: _stringList(json['methods']),
    x: _toDouble(json['x'], 0),
    y: _toDouble(json['y'], 0),
    width: _toDouble(json['width'], 180),
    height: _toDouble(json['height'], 120),
  );

  final String id;
  final String name;
  final String kind;
  final List<String> attributes;
  final List<String> methods;
  final double x;
  final double y;
  final double width;
  final double height;
}

class UmlRelation {
  const UmlRelation({
    required this.id,
    required this.source,
    required this.target,
    required this.type,
    required this.name,
    required this.sourceMultiplicity,
    required this.targetMultiplicity,
  });

  factory UmlRelation.fromJson(Map<String, dynamic> json) => UmlRelation(
    id: json['id'].toString(),
    source: json['source'].toString(),
    target: json['target'].toString(),
    type: json['type'] as String? ?? 'association',
    name: json['name'] as String? ?? '',
    sourceMultiplicity: json['sourceMultiplicity'] as String? ?? '',
    targetMultiplicity: json['targetMultiplicity'] as String? ?? '',
  );

  final String id;
  final String source;
  final String target;
  final String type;
  final String name;
  final String sourceMultiplicity;
  final String targetMultiplicity;
}

class DiagramDetail {
  const DiagramDetail({
    required this.id,
    required this.title,
    required this.version,
    required this.classes,
    required this.relations,
    required this.present,
    required this.agentName,
    this.lastSavedAt,
  });

  factory DiagramDetail.fromJson(Map<String, dynamic> json) => DiagramDetail(
    id: json['id'].toString(),
    title: json['title'] as String? ?? 'Sin título',
    version: json['version'] as int? ?? 1,
    classes: (json['classes'] as List? ?? const [])
        .map((e) => UmlClass.fromJson(e as Map<String, dynamic>))
        .toList(),
    relations: (json['relations'] as List? ?? const [])
        .map((e) => UmlRelation.fromJson(e as Map<String, dynamic>))
        .toList(),
    present: _stringList(json['present']),
    agentName: json['agentName'] as String? ?? 'Asistente',
    lastSavedAt: _parseDate(json['lastSavedAt']),
  );

  final String id;
  final String title;
  final int version;
  final List<UmlClass> classes;
  final List<UmlRelation> relations;
  final List<String> present;
  final String agentName;
  final DateTime? lastSavedAt;
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.actorName,
    required this.summary,
    required this.origin,
    required this.action,
    this.requestedByName,
    this.actorId,
    this.createdAt,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    id: json['id'].toString(),
    actorId: json['actorId']?.toString(),
    actorName: json['actorName'] as String? ?? 'Alguien',
    summary: json['summary'] as String? ?? '',
    origin: json['origin'] as String? ?? 'manual',
    action: json['action'] as String? ?? '',
    requestedByName: json['requestedByName'] as String?,
    createdAt: _parseDate(json['createdAt']),
  );

  final String id;
  final String? actorId;
  final String actorName;
  final String summary;
  final String origin;
  final String action;
  final String? requestedByName;
  final DateTime? createdAt;

  /// Cómo se hizo el cambio, en palabras.
  String? get originLabel => switch (origin) {
    'manual' => 'a mano',
    'agent' => 'a pedido de ${requestedByName ?? 'alguien'}',
    'import' => 'por importación',
    _ => null,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.authorName,
    required this.text,
    this.authorId,
    this.opsSummary,
    this.replyTo,
    this.toAgent = false,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'].toString(),
    role: json['role'] as String? ?? 'user',
    authorId: json['authorId']?.toString(),
    authorName: json['authorName'] as String? ?? '',
    text: json['text'] as String? ?? '',
    opsSummary: json['opsSummary'] as String?,
    replyTo: json['replyTo']?.toString(),
    toAgent: json['toAgent'] == true,
    createdAt: _parseDate(json['createdAt']),
  );

  final String id;
  final String role;
  final String? authorId;
  final String authorName;
  final String text;
  final String? opsSummary;
  final String? replyTo;
  final bool toAgent;
  final DateTime? createdAt;

  /// Lo que se muestra: el texto y, si la IA dibujó, el resultado.
  String get displayText =>
      [text, opsSummary].whereType<String>().where((t) => t.isNotEmpty).join('\n');
}

/// Aviso de la bandeja (`/notifications`).
class AppNotice {
  const AppNotice({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    this.diagramId,
    this.diagramTitle,
    this.createdAt,
  });

  factory AppNotice.fromJson(Map<String, dynamic> json) => AppNotice(
    id: json['id'].toString(),
    type: json['type'] as String? ?? 'activity',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    read: json['read'] == true,
    diagramId: json['diagramId']?.toString(),
    diagramTitle: json['diagramTitle'] as String?,
    createdAt: _parseDate(json['createdAt']),
  );

  final String id;

  /// `activity`, `agent` o `invitation`.
  final String type;
  final String title;
  final String body;
  final bool read;
  final String? diagramId;
  final String? diagramTitle;
  final DateTime? createdAt;

  AppNotice markedRead() => AppNotice(
    id: id,
    type: type,
    title: title,
    body: body,
    read: true,
    diagramId: diagramId,
    diagramTitle: diagramTitle,
    createdAt: createdAt,
  );
}

class NoticeInbox {
  const NoticeInbox({required this.notices, required this.unread});

  final List<AppNotice> notices;
  final int unread;
}
