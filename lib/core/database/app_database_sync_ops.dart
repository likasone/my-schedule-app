part of 'app_database.dart';

/// 局域网同步的数据库读写（规格见 docs/lan_sync.md §1、§6）。
///
/// - 读：[readSyncRows] 在一个事务里读出规范化所需的全部原始行（一致的快照），
///   结果是纯 Dart 的 [SyncRawSnapshot]，可以整批送进 `Isolate.run`；
/// - 写：`app_database_sync_writes.dart`（按原值写入与关联清理）与
///   `app_database_sync_order.dart`（顺序列表重排），由 `SyncApplier` 放进
///   同一个事务。
///
/// 读取一律用原始 SQL 而不是 Drift 的 `select`：要的是库里实际存的值（时间是
/// Unix 秒、布尔是 0/1），原始列指纹按它计算；也省掉一万篇日记逐行构造
/// [DateTime] 与数据类的开销。日记不读 `content_text`（由正文推出，不参与哈希）。
mixin _AppDatabaseSyncOps on _$AppDatabase {
  /// 在一个事务里读出日记、标签、标签关联、日记本、成员关系、留言、模板、
  /// 纪念日与这天的心情的原始行。草稿不同步，不读。
  Future<SyncRawSnapshot> readSyncRows() {
    return transaction(() => _readSyncRowsImpl());
  }

  Future<SyncRawSnapshot> _readSyncRowsImpl() async {
    final diaryRows = await customSelect(
      'SELECT id, diary_id, title, content, cover, metadata, created_at, '
      'updated_at, is_archived, archived_at, is_pinned, capsule_unlock_at, '
      'capsule_locked_at, is_deleted, deleted_at FROM diaries',
    ).get();
    final tagRows = await customSelect(
      'SELECT id, name, color FROM tags',
    ).get();
    final diaryTagRows = await customSelect(
      'SELECT diary_id, tag_id FROM diary_tags',
    ).get();
    final notebookRows = await customSelect(
      'SELECT id, notebook_id, name, kind, visibility, payload, sort_order, '
      'is_pinned, is_closed, created_at, updated_at, parent_id FROM notebooks',
    ).get();
    final membershipRows = await customSelect(
      'SELECT diary_id, notebook_id, chapter_id, position, added_at '
      'FROM diary_notebooks',
    ).get();
    final commentRows = await customSelect(
      'SELECT id, comment_id, diary_id, content, mood, created_at, edited_at '
      'FROM diary_comments',
    ).get();
    final templateRows = await customSelect(
      'SELECT id, template_id, name, payload, sort_order, created_at, '
      'updated_at FROM diary_templates',
    ).get();
    final anniversaryRows = await customSelect(
      'SELECT id, anniversary_id, title, base_date, recurrence, lunar_year, '
      'lunar_month, lunar_day, linked_diary_id, note, is_pinned, metadata, '
      'created_at, updated_at FROM anniversaries',
    ).get();
    final dayMoodRows = await customSelect(
      'SELECT day, mood, updated_at FROM day_moods',
    ).get();

    return SyncRawSnapshot(
      diaries: <SyncRawDiary>[
        for (final row in diaryRows)
          SyncRawDiary(
            localId: _syncInt(row.data['id']),
            diaryId: _syncStr(row.data['diary_id']),
            title: _syncStr(row.data['title']),
            content: _syncStr(row.data['content']),
            cover: _syncStrOrNull(row.data['cover']),
            metadata: _syncStr(row.data['metadata']),
            createdAt: _syncInt(row.data['created_at']),
            updatedAt: _syncInt(row.data['updated_at']),
            isArchived: _syncBool(row.data['is_archived']),
            archivedAt: _syncIntOrNull(row.data['archived_at']),
            isPinned: _syncBool(row.data['is_pinned']),
            capsuleUnlockAt: _syncIntOrNull(row.data['capsule_unlock_at']),
            capsuleLockedAt: _syncIntOrNull(row.data['capsule_locked_at']),
            isDeleted: _syncBool(row.data['is_deleted']),
            deletedAt: _syncIntOrNull(row.data['deleted_at']),
          ),
      ],
      tags: <SyncRawTag>[
        for (final row in tagRows)
          SyncRawTag(
            localId: _syncInt(row.data['id']),
            name: _syncStr(row.data['name']),
            color: _syncInt(row.data['color']),
          ),
      ],
      diaryTags: <SyncRawDiaryTag>[
        for (final row in diaryTagRows)
          SyncRawDiaryTag(
            diaryLocalId: _syncInt(row.data['diary_id']),
            tagLocalId: _syncInt(row.data['tag_id']),
          ),
      ],
      notebooks: <SyncRawNotebook>[
        for (final row in notebookRows)
          SyncRawNotebook(
            localId: _syncInt(row.data['id']),
            notebookId: _syncStr(row.data['notebook_id']),
            name: _syncStr(row.data['name']),
            kind: _syncStr(row.data['kind']),
            visibility: _syncStr(row.data['visibility']),
            payload: _syncStr(row.data['payload']),
            sortOrder: _syncInt(row.data['sort_order']),
            isPinned: _syncBool(row.data['is_pinned']),
            isClosed: _syncBool(row.data['is_closed']),
            createdAt: _syncInt(row.data['created_at']),
            updatedAt: _syncInt(row.data['updated_at']),
            parentId: _syncStrOrNull(row.data['parent_id']),
          ),
      ],
      memberships: <SyncRawMembership>[
        for (final row in membershipRows)
          SyncRawMembership(
            diaryLocalId: _syncInt(row.data['diary_id']),
            notebookLocalId: _syncInt(row.data['notebook_id']),
            chapterId: _syncStrOrNull(row.data['chapter_id']),
            position: _syncInt(row.data['position']),
            addedAt: _syncInt(row.data['added_at']),
          ),
      ],
      comments: <SyncRawComment>[
        for (final row in commentRows)
          SyncRawComment(
            localId: _syncInt(row.data['id']),
            commentId: _syncStr(row.data['comment_id']),
            diaryId: _syncStr(row.data['diary_id']),
            content: _syncStr(row.data['content']),
            mood: _syncStrOrNull(row.data['mood']),
            createdAt: _syncInt(row.data['created_at']),
            editedAt: _syncIntOrNull(row.data['edited_at']),
          ),
      ],
      templates: <SyncRawTemplate>[
        for (final row in templateRows)
          SyncRawTemplate(
            localId: _syncInt(row.data['id']),
            templateId: _syncStr(row.data['template_id']),
            name: _syncStr(row.data['name']),
            payload: _syncStr(row.data['payload']),
            sortOrder: _syncInt(row.data['sort_order']),
            createdAt: _syncInt(row.data['created_at']),
            updatedAt: _syncInt(row.data['updated_at']),
          ),
      ],
      anniversaries: <SyncRawAnniversary>[
        for (final row in anniversaryRows)
          SyncRawAnniversary(
            localId: _syncInt(row.data['id']),
            anniversaryId: _syncStr(row.data['anniversary_id']),
            title: _syncStr(row.data['title']),
            baseDate: _syncStr(row.data['base_date']),
            recurrence: _syncStr(row.data['recurrence']),
            lunarYear: _syncIntOrNull(row.data['lunar_year']),
            lunarMonth: _syncIntOrNull(row.data['lunar_month']),
            lunarDay: _syncIntOrNull(row.data['lunar_day']),
            linkedDiaryId: _syncStrOrNull(row.data['linked_diary_id']),
            note: _syncStr(row.data['note']),
            isPinned: _syncBool(row.data['is_pinned']),
            metadata: _syncStr(row.data['metadata']),
            createdAt: _syncInt(row.data['created_at']),
            updatedAt: _syncInt(row.data['updated_at']),
          ),
      ],
      dayMoods: <SyncRawDayMood>[
        for (final row in dayMoodRows)
          SyncRawDayMood(
            day: _syncStr(row.data['day']),
            mood: _syncStr(row.data['mood']),
            updatedAt: _syncInt(row.data['updated_at']),
          ),
      ],
    );
  }
}

/// SQLite 整数列读出来是 int；损坏数据里偶尔是浮点数或字符串，按截断取整与容错解析。
int _syncInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed.toInt();
  }
  return fallback;
}

int? _syncIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed.toInt();
  }
  return null;
}

/// 安全读取文本列，杜绝 null 导致的强转 TypeError
String _syncStr(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

String? _syncStrOrNull(Object? value) {
  if (value == null) return null;
  return value.toString();
}

/// Drift 的布尔列存 0/1。
bool _syncBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value.toInt() != 0;
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
