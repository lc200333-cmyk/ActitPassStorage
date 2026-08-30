class FieldDefinition {
  const FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.secret = false,
  });

  final String id;
  final String label;
  final String type;
  final bool required;
  final bool secret;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        'required': required,
        'secret': secret,
      };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) =>
      FieldDefinition(
        id: json['id'] as String,
        label: json['label'] as String,
        type: json['type'] as String,
        required: json['required'] == true,
        secret: json['secret'] == true,
      );
}

class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.name,
    required this.iconId,
    required this.colorId,
    required this.fields,
    this.builtIn = false,
    this.embeddedIconBase64,
    this.iconFileName,
    this.spbColor,
    this.categoryPath = '',
  });

  final String id;
  final String name;
  final String iconId;
  final String colorId;
  final List<FieldDefinition> fields;
  final bool builtIn;
  final String? embeddedIconBase64;
  final String? iconFileName;
  final int? spbColor;
  final String categoryPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconId': iconId,
        'colorId': colorId,
        'builtIn': builtIn,
        'embeddedIconBase64': embeddedIconBase64,
        'iconFileName': iconFileName,
        'spbColor': spbColor,
        'categoryPath': categoryPath,
        'fields': fields.map((field) => field.toJson()).toList(),
      };

  factory CardTemplate.fromJson(Map<String, dynamic> json) => CardTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        iconId: json['iconId'] as String,
        colorId: json['colorId'] as String,
        builtIn: json['builtIn'] == true,
        embeddedIconBase64: json['embeddedIconBase64'] as String?,
        iconFileName: json['iconFileName'] as String?,
        spbColor: json['spbColor'] as int?,
        categoryPath: json['categoryPath'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>)
            .map(
              (field) =>
                  FieldDefinition.fromJson(field as Map<String, dynamic>),
            )
            .toList(),
      );
}

class SecretItem {
  const SecretItem({
    required this.id,
    required this.templateId,
    required this.title,
    required this.category,
    required this.colorId,
    required this.values,
    required this.modifiedAt,
    this.attachments = const [],
    this.hitCount = 0,
    this.iconId,
    this.backgroundImageBase64,
    this.spbColor,
    this.fieldOrder = const [],
    this.hiddenFieldIds = const {},
  });

  final String id;
  final String templateId;
  final String title;
  final String category;
  final String colorId;
  final Map<String, String> values;
  final DateTime modifiedAt;
  final List<SecretAttachment> attachments;
  final int hitCount;
  final String? iconId;
  final String? backgroundImageBase64;
  final int? spbColor;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'category': category,
        'colorId': colorId,
        'values': values,
        'modifiedAt': modifiedAt.toIso8601String(),
        'attachments':
            attachments.map((attachment) => attachment.toJson()).toList(),
        'hitCount': hitCount,
        'iconId': iconId,
        'backgroundImageBase64': backgroundImageBase64,
        'spbColor': spbColor,
        'fieldOrder': fieldOrder,
        'hiddenFieldIds': hiddenFieldIds.toList(),
      };

  factory SecretItem.fromJson(Map<String, dynamic> json) => SecretItem(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        colorId: json['colorId'] as String? ?? 'neutral',
        values:
            Map<String, String>.from(json['values'] as Map<dynamic, dynamic>),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .map(
              (attachment) => SecretAttachment.fromJson(
                attachment as Map<String, dynamic>,
              ),
            )
            .toList(),
        hitCount: json['hitCount'] as int? ?? 0,
        iconId: json['iconId'] as String?,
        backgroundImageBase64: json['backgroundImageBase64'] as String?,
        spbColor: json['spbColor'] as int?,
        fieldOrder: List<String>.from(json['fieldOrder'] as List? ?? const []),
        hiddenFieldIds: Set<String>.from(
          json['hiddenFieldIds'] as List? ?? const [],
        ),
      );
}

class SecretAttachment {
  const SecretAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.decodeError,
    this.pendingBytes,
    this.deleted = false,
  });

  final String id;
  final String fileName;
  final int size;
  final String? decodeError;
  final List<int>? pendingBytes;
  final bool deleted;

  SecretAttachment copyWith({
    String? id,
    String? fileName,
    int? size,
    String? decodeError,
    List<int>? pendingBytes,
    bool? deleted,
  }) =>
      SecretAttachment(
        id: id ?? this.id,
        fileName: fileName ?? this.fileName,
        size: size ?? this.size,
        decodeError: decodeError,
        pendingBytes: pendingBytes ?? this.pendingBytes,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'size': size,
        'decodeError': decodeError,
      };

  factory SecretAttachment.fromJson(Map<String, dynamic> json) =>
      SecretAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        size: json['size'] as int? ?? -1,
        decodeError: json['decodeError'] as String?,
      );
}
