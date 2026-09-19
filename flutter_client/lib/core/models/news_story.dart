class NewsScope {
  final String type;
  final String? id;
  final String? name;

  const NewsScope({required this.type, this.id, this.name});

  factory NewsScope.fromJson(Map<String, dynamic> json) => NewsScope(
        type: json['type']?.toString() ?? 'EARTH',
        id: json['id']?.toString(),
        name: json['name']?.toString(),
      );
}

class NewsRelatedEntity {
  final String? type;
  final String? id;
  final String? name;

  const NewsRelatedEntity({this.type, this.id, this.name});

  factory NewsRelatedEntity.fromJson(Map<String, dynamic>? json) =>
      NewsRelatedEntity(
        type: json?['type']?.toString(),
        id: json?['id']?.toString(),
        name: json?['name']?.toString(),
      );
}

class NewsAction {
  final String? route;
  final String? entityId;
  final String? label;

  const NewsAction({this.route, this.entityId, this.label});

  factory NewsAction.fromJson(Map<String, dynamic>? json) => NewsAction(
        route: json?['route']?.toString(),
        entityId: json?['entityId']?.toString(),
        label: json?['label']?.toString(),
      );
}

class NewsViewer {
  final bool isNew;

  const NewsViewer({required this.isNew});

  factory NewsViewer.fromJson(Map<String, dynamic>? json) =>
      NewsViewer(isNew: json?['isNew'] == true);
}

class NewsStory {
  final String id;
  final NewsScope scope;
  final String topic;
  final String importance;
  final String headline;
  final String summary;
  final int gameDay;
  final int? gameMinute;
  final NewsRelatedEntity relatedEntity;
  final NewsAction action;
  final NewsViewer viewer;
  final String publicationKey;

  const NewsStory({
    required this.id,
    required this.scope,
    required this.topic,
    required this.importance,
    required this.headline,
    required this.summary,
    required this.gameDay,
    required this.gameMinute,
    required this.relatedEntity,
    required this.action,
    required this.viewer,
    required this.publicationKey,
  });

  factory NewsStory.fromJson(Map<String, dynamic> json) => NewsStory(
        id: json['id']?.toString() ?? '',
        scope: NewsScope.fromJson(
            Map<String, dynamic>.from(json['scope'] as Map? ?? const {})),
        topic: json['topic']?.toString() ?? 'SOCIETY',
        importance: json['importance']?.toString() ?? 'ROUTINE',
        headline: json['headline']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        gameDay: int.tryParse(json['gameDay']?.toString() ?? '') ?? 0,
        gameMinute: json['gameMinute'] == null
            ? null
            : int.tryParse(json['gameMinute'].toString()),
        relatedEntity: NewsRelatedEntity.fromJson(
            json['relatedEntity'] is Map
                ? Map<String, dynamic>.from(json['relatedEntity'] as Map)
                : null),
        action: NewsAction.fromJson(
            json['action'] is Map
                ? Map<String, dynamic>.from(json['action'] as Map)
                : null),
        viewer: NewsViewer.fromJson(
            json['viewer'] is Map
                ? Map<String, dynamic>.from(json['viewer'] as Map)
                : null),
        publicationKey: json['publicationKey']?.toString() ?? '',
      );
}
