import 'package:taskr/services/models.dart';

/// When saving a task should ask the server to schedule the "pay for parking?"
/// prompt.
///
/// The morning cron schedules the prompt for any Work Train task that exists
/// when it runs; this covers one added or retimed after that. The gate lives on
/// the client because a Firestore trigger can only filter by path, so it would
/// run on every task write. The server re-checks everything, so this only has
/// to avoid needless calls, not be the authority.
class ParkingSchedule {
  /// Must match `WORK_TRAIN_TITLE` in the functions, which matches it exactly.
  static const workTrainTitle = 'Work Train';

  static bool shouldRequest({Task? before, required Task after, required String today}) {
    if (after.id == null || after.title != workTrainTitle) return false;
    final start = after.startTime;
    if (start == null || start.isEmpty) return false;
    // Other days are left to that day's cron.
    if (after.dueDate != today) return false;
    // Unchanged departure (e.g. an edit to the description): already scheduled.
    if (before != null &&
        before.title == after.title &&
        before.startTime == start &&
        before.dueDate == after.dueDate) {
      return false;
    }
    return true;
  }
}
