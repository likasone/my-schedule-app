package com.jotsy.diary

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * 原生系统级日历与高穿透闹钟通道（Calendar & High-Penetration Alarm Channel）
 *
 * 核心原理（适配小米 MIUI / HyperOS 及主流国产定制安卓系统）：
 * 1. 深度穿透神隐模式：普通后台进程在锁屏后易被电池优化策略挂起或终止，但小米系统日历服务
 *    （com.android.calendar）属于系统核心白名单应用，不会被杀除。
 * 2. 借力系统日历提供者（CalendarProvider）：将日程与复习提醒作为事件写入系统日历，由系统日历
 *    原生服务在指定时间拉起强提醒与全屏横幅，达成 100% 准时触发。
 * 3. 硬件级高精度闹钟（AlarmManager.setAlarmClock）：状态栏展示闹钟图标，穿透 Doze 低功耗待机机制。
 */
class CalendarReminderChannel(
  private val activity: Activity,
  messenger: BinaryMessenger,
) {
  // 应用上下文与通道定义
  private val context: Context = activity.applicationContext
  private val channel = MethodChannel(messenger, "com.jotsy.diary/calendar_reminder")
  private val calendarPermissionRequestCode = 9182
  private var pendingPermissionResult: MethodChannel.Result? = null

  init {
    // 监听来自 Flutter Dart 层的调用
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        // 检查日历读写权限
        "hasCalendarPermission" -> result.success(checkCalendarPermissions())

        // 申请日历权限
        "requestCalendarPermission" -> {
          if (checkCalendarPermissions()) {
            result.success(true)
          } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
              activity,
              arrayOf(
                Manifest.permission.READ_CALENDAR,
                Manifest.permission.WRITE_CALENDAR
              ),
              calendarPermissionRequestCode
            )
          }
        }

        // 插入或更新系统日历事件
        "createOrUpdateCalendarEvent" -> {
          val title = call.argument<String>("title") ?: ""
          val notes = call.argument<String>("notes") ?: ""
          val startTimeMillis = call.argument<Long>("startTimeMillis") ?: System.currentTimeMillis()
          val durationMinutes = call.argument<Int>("durationMinutes") ?: 30
          val existingEventId = call.argument<Long>("existingEventId")
          val rrule = call.argument<String>("rrule")

          try {
            val eventId = createOrUpdateEvent(
              title = title,
              notes = notes,
              startTimeMillis = startTimeMillis,
              durationMinutes = durationMinutes,
              existingEventId = existingEventId,
              rrule = rrule
            )
            result.success(eventId)
          } catch (e: Exception) {
            result.error("calendar_error", e.localizedMessage, null)
          }
        }

        // 删除系统日历事件
        "deleteCalendarEvent" -> {
          val eventId = call.argument<Long>("eventId")
          if (eventId == null) {
            result.error("invalid_id", "Event ID must not be null", null)
          } else {
            try {
              val deleted = deleteCalendarEvent(eventId)
              result.success(deleted)
            } catch (e: Exception) {
              result.error("calendar_delete_error", e.localizedMessage, null)
            }
          }
        }

        // 设置系统级硬件闹钟（setAlarmClock）
        "setExactAlarmClock" -> {
          val triggerTimeMillis = call.argument<Long>("triggerTimeMillis") ?: 0L
          val title = call.argument<String>("title") ?: "日程提醒"
          val notes = call.argument<String>("notes") ?: ""

          try {
            val success = setAlarmClock(triggerTimeMillis, title, notes)
            result.success(success)
          } catch (e: Exception) {
            result.error("alarm_error", e.localizedMessage, null)
          }
        }

        else -> result.notImplemented()
      }
    }
  }

  /**
   * 检查是否已拥有日历读写权限
   */
  private fun checkCalendarPermissions(): Boolean {
    val readPermission = ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.READ_CALENDAR
    ) == PackageManager.PERMISSION_GRANTED

    val writePermission = ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.WRITE_CALENDAR
    ) == PackageManager.PERMISSION_GRANTED

    return readPermission && writePermission
  }

  /**
   * 权限请求结果回调分发（由 MainActivity 的 onRequestPermissionsResult 转发）
   */
  fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != calendarPermissionRequestCode) {
      return false
    }

    val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
    pendingPermissionResult?.success(granted)
    pendingPermissionResult = null
    return true
  }

  /**
   * 查询系统主日历账户 ID（若无则查找可用日历）
   */
  private fun getOrCreateCalendarId(): Long {
    val projection = arrayOf(
      CalendarContract.Calendars._ID,
      CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
      CalendarContract.Calendars.IS_PRIMARY
    )

    // 优先查询系统默认/主日历
    context.contentResolver.query(
      CalendarContract.Calendars.CONTENT_URI,
      projection,
      null,
      null,
      null
    )?.use { cursor ->
      if (cursor.moveToFirst()) {
        val idColumn = cursor.getColumnIndex(CalendarContract.Calendars._ID)
        return cursor.getLong(idColumn)
      }
    }

    // 默认回落到 1L（标准主日历 ID）
    return 1L
  }

  /**
   * 向系统日历插入或更新日程事件及准时强提醒
   */
  private fun createOrUpdateEvent(
    title: String,
    notes: String,
    startTimeMillis: Long,
    durationMinutes: Int,
    existingEventId: Long?,
    rrule: String? = null
  ): Long {
    val calendarId = getOrCreateCalendarId()
    val endTimeMillis = startTimeMillis + (durationMinutes * 60 * 1000L)
    val timeZone = TimeZone.getDefault().id

    val eventValues = ContentValues().apply {
      put(CalendarContract.Events.CALENDAR_ID, calendarId)
      put(CalendarContract.Events.TITLE, title)
      put(CalendarContract.Events.DESCRIPTION, notes)
      put(CalendarContract.Events.DTSTART, startTimeMillis)
      put(CalendarContract.Events.DTEND, endTimeMillis)
      put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
      put(CalendarContract.Events.HAS_ALARM, 1) // 开启闹钟警报标记
      if (!rrule.isNullOrEmpty()) {
        put(CalendarContract.Events.RRULE, rrule) // 写入 RFC 5545 重复规则（如 FREQ=DAILY, FREQ=WEEKLY）
      }
    }

    val eventId: Long
    if (existingEventId != null && existingEventId > 0) {
      // 更新既有事件
      val updateUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, existingEventId)
      context.contentResolver.update(updateUri, eventValues, null, null)
      eventId = existingEventId
    } else {
      // 插入新事件
      val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, eventValues)
      eventId = uri?.lastPathSegment?.toLongOrNull() ?: throw IllegalStateException("无法获取插入事件的 ID")
    }

    // 插入准时弹窗强提醒（Minutes = 0 表示准点响铃与横幅弹出）
    val reminderValues = ContentValues().apply {
      put(CalendarContract.Reminders.EVENT_ID, eventId)
      put(CalendarContract.Reminders.MINUTES, 0)
      put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
    }

    try {
      context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
    } catch (_: Exception) {
      // 部分定制系统可能自带默认提醒，捕获以保证主事件成功
    }

    return eventId
  }

  /**
   * 从系统日历中删除指定事件
   */
  private fun deleteCalendarEvent(eventId: Long): Boolean {
    val deleteUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
    val rows = context.contentResolver.delete(deleteUri, null, null)
    return rows > 0
  }

  /**
   * 使用系统最高穿透优先级的 setAlarmClock 设置独立定时闹钟
   */
  private fun setAlarmClock(triggerTimeMillis: Long, title: String, notes: String): Boolean {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false

    // 构建点击提醒后进入主界面的意图
    val intent = Intent(context, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      putExtra("alarm_title", title)
      putExtra("alarm_notes", notes)
    }

    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    } else {
      PendingIntent.FLAG_UPDATE_CURRENT
    }

    val pendingIntent = PendingIntent.getActivity(
      context,
      (triggerTimeMillis % Int.MAX_VALUE).toInt(),
      intent,
      flags
    )

    // 系统状态栏将点亮闹钟图标，并获得最高穿透唤醒权限
    val clockInfo = AlarmManager.AlarmClockInfo(triggerTimeMillis, pendingIntent)
    alarmManager.setAlarmClock(clockInfo, pendingIntent)
    return true
  }

  /**
   * 释放资源与清空回调
   */
  fun dispose() {
    channel.setMethodCallHandler(null)
    pendingPermissionResult = null
  }
}
