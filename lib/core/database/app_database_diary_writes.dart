part of 'app_database.dart';

/// 日记的时间胶囊两列（解封时刻、封存时刻），见 [_AppDatabaseDiaryWrites.updateDiary]。
typedef DiaryCapsuleColumns = ({DateTime? unlockAt, DateTime? lockedAt});

/// 日记写入与状态变更实现。
///
/// 该分区负责：
/// - 创建/更新日记；
/// - 归档、软删除、恢复；
/// - 日记与标签、日记与日记本关联关系维护。
mixin _AppDatabaseDiaryWrites on _$AppDatabase, _AppDatabaseNotebookEntryOps {
  /// 创建日记并写入关联标签与所在日记本。
  ///
  /// 事务内完成“主表插入 + 关联表写入”，保证一致性。[notebookIds] 为日记本
  /// 业务 id，新日记接在各本最后；智能或不存在的本子忽略。
  /// [notebookChapterIds] 为日记本业务 id → 章节 id（在日记本里按章节新建时
  /// 带上）：只对 [notebookIds] 里的本子生效，章节已不在那本里时落到“未分章”。
  Future<String> createDiary({
    required String title,
    required String contentDocJson,
    required String contentText,
    required String metadataJson,
    String? cover,
    List<int> tagIds = const <int>[],
    DateTime? createdAtOverride,
    DateTime? capsuleUnlockAt,
    DateTime? capsuleLockedAt,
    List<String>? notebookIds,
    Map<String, String> notebookChapterIds = const <String, String>{},
  }) async {
    final now = createdAtOverride ?? DateTime.now();
    final diaryId = _generateDiaryId();
    // 弹性规范化 metadata：格式异常时自动降级为空对象，绝不抛出 FormatException
    String normalizedMetadata;
    try {
      normalizedMetadata = normalizeMetadataJson(metadataJson);
    } catch (_) {
      normalizedMetadata = '{}';
    }
    final normalizedCover = _normalizeCover(cover);
    final normalizedTagIds = tagIds.toSet().toList();

    // 将标签 ID 列表同步写入 metadata 字段中的 tagIds 数组，保证跨设备与兜底查询的一致性
    try {
      final dynamic decoded = jsonDecode(normalizedMetadata);
      if (decoded is Map) {
        final Map<String, Object?> map = Map<String, Object?>.from(decoded);
        map['tagIds'] = normalizedTagIds;
        normalizedMetadata = jsonEncode(map);
      }
    } catch (_) {}

    // 弹性重试机制：应对 Windows/各平台偶发瞬时锁争用与只读锁 (SqliteException 8 / 5)
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        return await transaction<String>(() async {
          final localDiaryId = await into(diaries).insert(
            DiariesCompanion.insert(
              diaryId: diaryId,
              title: Value<String>(title.trim()),
              content: contentDocJson,
              contentText: contentText,
              cover: Value<String?>(normalizedCover),
              metadata: Value<String>(normalizedMetadata),
              createdAt: now,
              updatedAt: now,
              capsuleUnlockAt: Value<DateTime?>(capsuleUnlockAt),
              capsuleLockedAt: Value<DateTime?>(capsuleLockedAt),
            ),
          );

          await _replaceDiaryTags(localDiaryId, normalizedTagIds);
          if (notebookIds != null && notebookIds.isNotEmpty) {
            try {
              await _replaceDiaryNotebooks(
                localDiaryId,
                notebookIds.toSet(),
                chapterIds: notebookChapterIds,
              );
            } catch (_) {}
          }
          return diaryId;
        });
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isLockOrReadonly = errorStr.contains('readonly') ||
            errorStr.contains('busy') ||
            errorStr.contains('code 8') ||
            errorStr.contains('code 5') ||
            errorStr.contains('database is locked');
        if (isLockOrReadonly && attempts < 5) {
          // 遇到并发读锁或杀毒软件索引锁冲突时，按 150ms 步进弹性退避重试 (最多 5 次)
          await Future<void>.delayed(Duration(milliseconds: 150 * attempts));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 更新日记并覆盖标签绑定关系。
  ///
  /// 事务内先更新主表，再重建关联表数据。[createdAt] 是发表时间，传 null
  /// 时保持原值：只改正文的路径（如预览页勾选待办）不应触碰发表时间。
  /// [notebookIds] 为 null 时不动所在日记本；否则改为恰好在这些本子里，仍在的
  /// 本子保留章节与成书位置（见 `_replaceDiaryNotebooks`），新加入的本子按
  /// [notebookChapterIds] 落进章节（同 [createDiary]）。
  /// [capsule] 为 null 时不动时间胶囊两列（编辑页不管胶囊）；否则两列改写为
  /// 给定值，两者都为 null 即取消胶囊。只有刚发表、仍停在发布页的新日记会
  /// 传它：发布页面板里的胶囊与其他信息一样随改随存。
  Future<void> updateDiary({
    required String diaryId,
    required String title,
    required String contentDocJson,
    required String contentText,
    required String metadataJson,
    String? cover,
    List<int> tagIds = const <int>[],
    DateTime? createdAt,
    List<String>? notebookIds,
    Map<String, String> notebookChapterIds = const <String, String>{},
    DiaryCapsuleColumns? capsule,
  }) async {
    // 弹性规范化 metadata：格式异常时自动降级为空对象，绝不抛出 FormatException 阻断用户保存修改
    String normalizedMetadata;
    try {
      normalizedMetadata = normalizeMetadataJson(metadataJson);
    } catch (_) {
      normalizedMetadata = '{}';
    }
    final normalizedCover = _normalizeCover(cover);
    final normalizedTagIds = tagIds.toSet().toList();

    // 同步将当前选中的标签 ID 列表更新到 metadata JSON 中的 tagIds 数组，防止元数据与关联表不同步
    try {
      final dynamic decoded = jsonDecode(normalizedMetadata);
      if (decoded is Map) {
        final Map<String, Object?> map = Map<String, Object?>.from(decoded);
        map['tagIds'] = normalizedTagIds;
        normalizedMetadata = jsonEncode(map);
      }
    } catch (_) {}

    // 弹性重试机制：应对 Windows 平台瞬时文件锁、杀毒软件扫描锁或 SqliteException 8 (readonly) / 5 (busy)
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        await transaction<void>(() async {
          Diary? diary = await (select(
            diaries,
          )..where((Diaries t) => t.diaryId.equals(diaryId))).getSingleOrNull();
          // 若按业务 diaryId 未命中，尝试按自增整型主键 id 查找兜底（兼容从某些内部索引或特殊场景传入数字 id 的情况）
          if (diary == null) {
            final parsedLocalId = int.tryParse(diaryId);
            if (parsedLocalId != null) {
              diary = await (select(
                diaries,
              )..where((Diaries t) => t.id.equals(parsedLocalId))).getSingleOrNull();
            }
          }
          if (diary == null) {
            throw StateError('未找到 diaryId=$diaryId 对应的日记');
          }

          // 提取非空强类型的自增主键 ID，避免在内部闭包中因类型提升限制报错
          final effectiveLocalId = diary.id;

          // 精确使用确定命中的自增整型主键 id 进行更新，避免 UUID 匹配异常
          await (update(
            diaries,
          )..where((Diaries t) => t.id.equals(effectiveLocalId))).write(
            DiariesCompanion(
              title: Value<String>(title.trim()),
              content: Value<String>(contentDocJson),
              contentText: Value<String>(contentText),
              cover: Value<String?>(normalizedCover),
              metadata: Value<String>(normalizedMetadata),
              createdAt: Value<DateTime>.absentIfNull(createdAt),
              updatedAt: Value<DateTime>(DateTime.now()),
              capsuleUnlockAt: capsule == null
                  ? const Value<DateTime?>.absent()
                  : Value<DateTime?>(capsule.unlockAt),
              capsuleLockedAt: capsule == null
                  ? const Value<DateTime?>.absent()
                  : Value<DateTime?>(capsule.lockedAt),
              isArchived: const Value<bool>(false),
              archivedAt: const Value<DateTime?>(null),
              isDeleted: const Value<bool>(false),
              deletedAt: const Value<DateTime?>(null),
            ),
          );

          await _replaceDiaryTags(effectiveLocalId, normalizedTagIds);
          if (notebookIds != null) {
            try {
              await _replaceDiaryNotebooks(
                effectiveLocalId,
                notebookIds.toSet(),
                chapterIds: notebookChapterIds,
              );
            } catch (_) {}
          }
        });
        break; // 成功执行，跳出循环
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isLockOrReadonly = errorStr.contains('readonly') ||
            errorStr.contains('busy') ||
            errorStr.contains('code 8') ||
            errorStr.contains('code 5') ||
            errorStr.contains('database is locked');
        if (isLockOrReadonly && attempts < 5) {
          // 遇到并发读锁或杀毒软件锁冲突时，退避重试 (150ms, 300ms, 450ms, 600ms)
          await Future<void>.delayed(Duration(milliseconds: 150 * attempts));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 只更新正文（富文本 JSON 与纯文本）与 `updatedAt`。
  ///
  /// 供预览页勾选待办等“只改正文”的路径使用：[updateDiary] 会顺带取消归档、
  /// 取消删除并重写标签，从归档列表打开的日记勾一下待办就会被移出归档；这里
  /// 不碰归档、删除、置顶、标签与 metadata。日记不存在时静默不写。
  Future<void> updateDiaryContent({
    required String diaryId,
    required String contentDocJson,
    required String contentText,
  }) async {
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        await (update(
          diaries,
        )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
          DiariesCompanion(
            content: Value<String>(contentDocJson),
            contentText: Value<String>(contentText),
            updatedAt: Value<DateTime>(DateTime.now()),
          ),
        );
        break;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isLockOrReadonly = errorStr.contains('readonly') ||
            errorStr.contains('busy') ||
            errorStr.contains('code 8') ||
            errorStr.contains('code 5') ||
            errorStr.contains('database is locked');
        if (isLockOrReadonly && attempts < 5) {
          await Future<void>.delayed(Duration(milliseconds: 150 * attempts));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 更新时间胶囊解封时间，不触碰正文以避免未解封管理页泄露内容。
  Future<void> updateDiaryCapsuleSchedule({
    required String diaryId,
    required DateTime unlockAt,
  }) async {
    final diary = await (select(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).getSingleOrNull();
    final nextMetadata = _metadataWithUpdatedCapsuleUnlockAt(
      diary?.metadata,
      unlockAt,
    );
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        metadata: Value<String>(nextMetadata),
        capsuleUnlockAt: Value<DateTime?>(unlockAt),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  String _metadataWithUpdatedCapsuleUnlockAt(String? raw, DateTime unlockAt) {
    try {
      final decoded = jsonDecode(raw ?? '{}');
      if (decoded is Map<String, dynamic>) {
        final capsule = decoded['capsule'];
        final nextCapsule = capsule is Map<String, dynamic>
            ? Map<String, Object?>.from(capsule)
            : <String, Object?>{};
        nextCapsule['unlockAt'] = unlockAt.toIso8601String();
        decoded['capsule'] = nextCapsule;
        return jsonEncode(decoded);
      }
    } catch (_) {
      // 非法 metadata 由 normalizeMetadataJson 兜底成空对象，避免管理页写入失败。
    }
    return jsonEncode(<String, Object?>{
      'capsule': <String, Object?>{'unlockAt': unlockAt.toIso8601String()},
    });
  }

  /// 置顶日记（固定显示在列表前部）。
  ///
  /// 默认不修改 `updatedAt`，避免仅置顶操作打乱“最近编辑时间”语义。
  Future<void> pinDiary(String diaryId, {bool touchUpdatedAt = false}) async {
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isPinned: const Value<bool>(true),
        updatedAt: touchUpdatedAt
            ? Value<DateTime>(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// 取消置顶日记。
  Future<void> unpinDiary(String diaryId, {bool touchUpdatedAt = false}) async {
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isPinned: const Value<bool>(false),
        updatedAt: touchUpdatedAt
            ? Value<DateTime>(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// 归档日记（不删除，仅从主列表隐藏）。
  Future<void> archiveDiary(
    String diaryId, {
    bool touchUpdatedAt = true,
  }) async {
    final now = DateTime.now();
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isArchived: const Value<bool>(true),
        archivedAt: Value<DateTime?>(now),
        updatedAt: touchUpdatedAt ? Value<DateTime>(now) : const Value.absent(),
      ),
    );
  }

  /// 取消归档日记。
  Future<void> unarchiveDiary(
    String diaryId, {
    bool touchUpdatedAt = true,
  }) async {
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isArchived: const Value<bool>(false),
        archivedAt: const Value<DateTime?>(null),
        updatedAt: touchUpdatedAt
            ? Value<DateTime>(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// 软删除日记（不物理删除）。
  ///
  /// 不动标签与日记本关联行：从回收站恢复后日记自然回到原来的本子与章节；
  /// 日记本的篇数与列表按 `is_deleted` 过滤，不会把回收站里的算进去。
  ///
  /// `touchUpdatedAt=false` 可用于“可撤销删除”场景，避免恢复后排序变化。
  Future<void> softDeleteDiary(
    String diaryId, {
    bool touchUpdatedAt = true,
  }) async {
    final now = DateTime.now();
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isArchived: const Value<bool>(false),
        archivedAt: const Value<DateTime?>(null),
        isDeleted: const Value<bool>(true),
        deletedAt: Value<DateTime?>(now),
        updatedAt: touchUpdatedAt ? Value<DateTime>(now) : const Value.absent(),
      ),
    );
  }

  /// 恢复软删除日记。
  ///
  /// `touchUpdatedAt=false` 可用于“撤销删除”场景，避免列表排序跳到最前。
  Future<void> restoreDiary(
    String diaryId, {
    bool touchUpdatedAt = true,
  }) async {
    await (update(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).write(
      DiariesCompanion(
        isArchived: const Value<bool>(false),
        archivedAt: const Value<DateTime?>(null),
        isDeleted: const Value<bool>(false),
        deletedAt: const Value<DateTime?>(null),
        updatedAt: touchUpdatedAt
            ? Value<DateTime>(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// 彻底删除日记（物理删除，不可恢复）。
  ///
  /// 显式清理 diary_tags 与 diary_notebooks：本库不开启外键，diary_tags 声明
  /// 的级联不会生效，diary_notebooks 则根本没有声明外键；关联这篇日记的
  /// 纪念日同时解除关联、留言一并删除（两者都只存日记业务 id、没有外键）。
  /// 软删除不动关联与留言，从回收站恢复后都还在。
  /// 只删除数据库记录：正文媒体可能被其他日记或草稿复用（复制粘贴图片），
  /// 文件由 DiaryMediaCleanupService 确认无人引用后再回收。
  Future<void> hardDeleteDiary(String diaryId) async {
    final targetDiary = await (select(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).getSingleOrNull();
    if (targetDiary == null) {
      return;
    }

    // 旧连接可能没有开启外键，显式清理绑定，避免再次导出悬空关联。
    await transaction(() async {
      await (delete(
        diaryTags,
      )..where((DiaryTags t) => t.diaryId.equals(targetDiary.id))).go();
      await (delete(
        diaryNotebooks,
      )..where((t) => t.diaryId.equals(targetDiary.id))).go();
      await (delete(
        diaries,
      )..where((Diaries t) => t.diaryId.equals(diaryId))).go();
      await (update(anniversaries)
            ..where((t) => t.linkedDiaryId.equals(diaryId)))
          .write(const AnniversariesCompanion(linkedDiaryId: Value(null)));
      await (delete(
        diaryComments,
      )..where((t) => t.diaryId.equals(diaryId))).go();
    });
  }

  /// 按业务 diaryId 获取单条日记及其标签。
  ///
  /// 刻意不排除私密日记：这是“按 id 直接打开”（编辑页、私密日记本里的预览
  /// 等），调用方已经拿到了 id，说明它来自一个允许看到它的范围。
  Future<DiaryWithTags?> getDiaryWithTagsByDiaryId(String diaryId) async {
    Diary? diary = await (select(
      diaries,
    )..where((Diaries t) => t.diaryId.equals(diaryId))).getSingleOrNull();
    // 若按业务 diaryId 未命中，尝试按自增整型主键 id 查找兜底（兼容从某些内部索引或特殊场景传入数字 id 的情况）
    if (diary == null) {
      final parsedLocalId = int.tryParse(diaryId);
      if (parsedLocalId != null) {
        diary = await (select(
          diaries,
        )..where((Diaries t) => t.id.equals(parsedLocalId))).getSingleOrNull();
      }
    }
    if (diary == null) {
      return null;
    }

    final relatedTags = await _getTagsForDiary(diary.id);
    return DiaryWithTags(diary: diary, tags: relatedTags);
  }

  /// 覆盖写入某条日记的标签关系。
  Future<void> _replaceDiaryTags(int diaryId, List<int> tagIds) async {
    // 先清理原日记关联的全部标签行
    await (delete(
      diaryTags,
    )..where((DiaryTags t) => t.diaryId.equals(diaryId))).go();

    // 标签列表去重并过滤非正数 ID
    final normalizedTagIds = tagIds.where((int id) => id > 0).toSet().toList();
    if (normalizedTagIds.isEmpty) {
      return;
    }

    // 逐条安全写入关联记录，避免事务内嵌套 batch 导致的驱动锁阻塞或冲突中断事务；
    // 采用 insertOrIgnore 模式防御唯一键与主键重复，并对单条外键异常进行防御性捕获
    for (final tagId in normalizedTagIds) {
      try {
        await into(diaryTags).insert(
          DiaryTagsCompanion.insert(diaryId: diaryId, tagId: tagId),
          mode: InsertMode.insertOrIgnore,
        );
      } catch (_) {
        // 若某个 tagId 在 tags 表中已不存在（如跨设备同步或草稿遗留），忽略单条失效关联，确保日记修改与同步流程不被中断
      }
    }
  }

  /// 查询某条日记绑定的全部标签。
  Future<List<Tag>> _getTagsForDiary(int diaryId) async {
    final rows =
        await (select(
                diaryTags,
              ).join([innerJoin(tags, tags.id.equalsExp(diaryTags.tagId))])
              ..where(diaryTags.diaryId.equals(diaryId))
              ..orderBy([OrderingTerm.asc(tags.name)]))
            .get();

    return rows.map((TypedResult row) => row.readTable(tags)).toList();
  }

  String? _normalizeCover(String? rawCover) {
    final normalized = rawCover?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _generateDiaryId() => _newBusinessUuid();
}

/// 业务唯一 id（UUID v4）：日记与纪念日共用，跨设备合并时按它判定同一条。
String _newBusinessUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
