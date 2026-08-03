import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hansol_high_school/api/timetable_data_api.dart';
import 'package:hansol_high_school/data/analytics_service.dart';
import 'package:hansol_high_school/data/auth_service.dart' show AuthService;
import 'package:hansol_high_school/data/setting_data.dart';
import 'package:hansol_high_school/data/subject_data_manager.dart';
import 'package:hansol_high_school/l10n/app_localizations.dart';
import 'package:hansol_high_school/screens/sub/timetable_select_screen.dart';
import 'package:hansol_high_school/screens/sub/teacher_timetable_select_screen.dart';
import 'package:hansol_high_school/data/auth_service.dart';
import 'package:hansol_high_school/styles/app_colors.dart';
import 'package:hansol_high_school/styles/responsive.dart';
import 'package:hansol_high_school/widgets/error_view.dart';
import 'package:hansol_high_school/widgets/home/current_subject_card.dart';
import 'package:hansol_high_school/widgets/setting/grade_and_class_picker.dart';
import 'package:hansol_high_school/screens/sub/timetable_widgets/color_picker_dialog.dart';
import 'package:hansol_high_school/screens/sub/timetable_widgets/conflict_dialog.dart';
import 'package:hansol_high_school/screens/sub/timetable_widgets/timetable_cell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hansol_high_school/widgets/home_widget/widget_service.dart';
import 'dart:convert';

class TimetableViewScreen extends StatefulWidget {
  const TimetableViewScreen({super.key});

  @override
  State<TimetableViewScreen> createState() => _TimetableViewScreenState();
}

class _TimetableViewScreenState extends State<TimetableViewScreen> {
  late Future<_TimetableResult> _future;
  late int _grade;
  late int _classNum;

  Map<String, String> _conflictResolutions = {};
  bool _isShowingConflictDialog = false;
  Map<String, int> _subjectColors = {};
  bool _isTeacher = false;
  bool _showWeekly = true;
  Timer? _clockTimer;
  DateTime _clockNow = DateTime.now();

  static const _periodTimes = [
    [8, 40, 9, 30],
    [9, 40, 10, 30],
    [10, 40, 11, 30],
    [11, 40, 12, 30],
    [13, 30, 14, 20],
    [14, 30, 15, 20],
    [15, 30, 16, 20],
  ];

  /// 0-based index of the period happening right now, or -1 if between/after classes.
  int get _currentPeriodIndex {
    if (_clockNow.weekday > 5) return -1;
    final nowMinutes = _clockNow.hour * 60 + _clockNow.minute;
    for (int i = 0; i < _periodTimes.length; i++) {
      final startMin = _periodTimes[i][0] * 60 + _periodTimes[i][1];
      final endMin = _periodTimes[i][2] * 60 + _periodTimes[i][3];
      if (nowMinutes >= startMin && nowMinutes < endMin) return i;
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.trackFirstVisit('timetable');
    _grade = SettingData().grade;
    _classNum = SettingData().classNum;
    _loadConflictResolutions();
    _loadSubjectColors();

    final cached = AuthService.cachedProfile;
    if (cached?.isTeacher == true) {
      _isTeacher = true;
      _future = _buildTeacherTimetable();
    } else if (SettingData().isGradeSet) {
      _future = _buildTimetable();
    } else {
      _future = Future.value(_TimetableResult(
        grid: List.generate(5, (_) => List.filled(7, '')),
        conflicts: {},
      ));
    }
    _checkTeacher();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _clockNow = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSubjectColors() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('subject_colors');
    if (json != null) {
      _subjectColors = Map<String, int>.from(jsonDecode(json));
    }
  }

  Future<void> _saveSubjectColors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subject_colors', jsonEncode(_subjectColors));
  }

  void _showColorPicker(String subject) {
    showDialog(
      context: context,
      builder: (_) => TimetableColorPickerDialog(
        subjectName: subject,
        currentColor: _subjectColors.containsKey(subject)
            ? Color(_subjectColors[subject]!)
            : null,
        onColorSelected: (color) {
          setState(() {
            if (color == const Color(0x00000000)) {
              _subjectColors.remove(subject);
            } else {
              _subjectColors[subject] = color.toARGB32();
            }
          });
          _saveSubjectColors();
        },
      ),
    );
  }

  Future<void> _loadConflictResolutions() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('conflict_resolutions_$_grade');
    if (json != null) {
      _conflictResolutions = Map<String, String>.from(jsonDecode(json));
    }
  }

  Future<void> _saveConflictResolutions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'conflict_resolutions_$_grade', jsonEncode(_conflictResolutions));
  }

  Future<void> _checkTeacher() async {
    final profile = await AuthService.getCachedProfile();
    if (profile?.isTeacher == true && mounted) {
      setState(() => _isTeacher = true);
      _future = _buildTeacherTimetable();
      setState(() {});
    }
  }

  Future<_TimetableResult> _buildTeacherTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('teacher_timetable_selections');
    if (json == null) return _TimetableResult(grid: List.generate(5, (_) => List.filled(7, '')), conflicts: {});
    final selectedKeys = Set<String>.from(jsonDecode(json));
    final teacherSubjects = <int, Map<String, Set<int>>>{};
    for (var key in selectedKeys) {
      final parts = key.split('_');
      if (parts.length < 3) continue;
      final g = int.tryParse(parts[0]);
      final c = int.tryParse(parts.last);
      if (g == null || c == null) continue;
      final name = parts.sublist(1, parts.length - 1).join('_');
      teacherSubjects.putIfAbsent(g, () => {}).putIfAbsent(name, () => {}).add(c);
    }
    const maxPeriods = 7;
    final grid = List.generate(5, (_) => List.filled(maxPeriods, ''));
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final friday = monday.add(const Duration(days: 4));
    for (var entry in teacherSubjects.entries) {
      final timetable = await TimetableDataApi.getTimeTable(startDate: monday, endDate: friday, grade: entry.key.toString());
      timetable.forEach((dateStr, classMap) {
        if (dateStr == 'error') return;
        final weekday = DateTime(int.parse(dateStr.substring(0, 4)), int.parse(dateStr.substring(4, 6)), int.parse(dateStr.substring(6, 8))).weekday;
        if (weekday > 5) return;
        classMap.forEach((classNum, subjects) {
          if (classNum == 'error') return;
          final classInt = classNum == 'special' ? -1 : (int.tryParse(classNum) ?? -1);
          for (int p = 0; p < subjects.length && p < maxPeriods; p++) {
            final name = subjects[p];
            if (name.isEmpty || name.contains('[보강]') || name == '토요휴업일') continue;
            if (entry.value.containsKey(name) && entry.value[name]!.contains(classInt)) {
              final label = classInt < 0 ? '특' : '$classInt';
              grid[weekday - 1][p] = '$name\n(${entry.key}-$label)';
            }
          }
        });
      });
    }
    return _TimetableResult(grid: grid, conflicts: {});
  }

  Future<_TimetableResult> _buildTimetable() async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final friday = monday.add(const Duration(days: 4));

    if (_grade == 1) {
      return _buildClassTimetable(monday, friday);
    } else {
      return _buildSelectedTimetable(monday, friday);
    }
  }

  Future<_TimetableResult> _buildClassTimetable(
      DateTime monday, DateTime friday) async {
    final timetable = await TimetableDataApi.getTimeTable(
      startDate: monday,
      endDate: friday,
      grade: _grade.toString(),
      classNum: _classNum.toString(),
    );

    const maxPeriods = 7;
    final grid = List.generate(5, (_) => List.filled(maxPeriods, ''));

    timetable.forEach((dateStr, classMap) {
      if (dateStr == 'error') return;
      final weekday = DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(4, 6)),
        int.parse(dateStr.substring(6, 8)),
      ).weekday;
      if (weekday > 5) return;

      classMap.forEach((_, subjects) {
        for (int p = 0; p < subjects.length && p < maxPeriods; p++) {
          final name = subjects[p];
          if (name.isEmpty || name.contains('[보강]') || name == '토요휴업일') continue;
          grid[weekday - 1][p] = name;
        }
      });
    });

    return _TimetableResult(grid: grid, conflicts: {});
  }

  Future<_TimetableResult> _buildSelectedTimetable(
      DateTime monday, DateTime friday) async {
    final selected = await SubjectDataManager.loadSelectedSubjects(_grade);

    final timetable = await TimetableDataApi.getTimeTable(
      startDate: monday,
      endDate: friday,
      grade: _grade.toString(),
    );

    const maxPeriods = 7;
    final grid = List.generate(5, (_) => List.filled(maxPeriods, ''));
    final conflictSlots = <String, List<String>>{};

    final selectedMap = <String, int>{};
    for (var s in selected) {
      selectedMap[s.subjectName] = s.subjectClass;
    }

    timetable.forEach((dateStr, classMap) {
      if (dateStr == 'error') return;
      final weekday = DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(4, 6)),
        int.parse(dateStr.substring(6, 8)),
      ).weekday;
      if (weekday > 5) return;
      final dayName = ['월', '화', '수', '목', '금'][weekday - 1];

      classMap.forEach((classNum, subjects) {
        if (classNum == 'error') return;
        final classInt = classNum == 'special' ? -1 : (int.tryParse(classNum) ?? -1);
        for (int p = 0; p < subjects.length && p < maxPeriods; p++) {
          final name = subjects[p];
          if (name.isEmpty || name.contains('[보강]') || name == '토요휴업일') continue;
          if (selectedMap.containsKey(name) && selectedMap[name] == classInt) {
            final slot = '${dayName}_${p + 1}';

            if (grid[weekday - 1][p].isNotEmpty &&
                grid[weekday - 1][p] != name) {
              final existing = grid[weekday - 1][p];
              conflictSlots.putIfAbsent(slot, () => [existing]);
              if (!conflictSlots[slot]!.contains(name)) {
                conflictSlots[slot]!.add(name);
              }

              if (_conflictResolutions.containsKey(slot)) {
                grid[weekday - 1][p] = _conflictResolutions[slot]!;
              }
            } else {
              grid[weekday - 1][p] = name;
            }
          }
        }
      });
    });

    return _TimetableResult(grid: grid, conflicts: conflictSlots);
  }

  Future<void> _showConflictResolver(_TimetableResult result) async {
    if (_isShowingConflictDialog) return;
    _isShowingConflictDialog = true;

    try {
      final unresolved = <String, List<String>>{};
      for (var entry in result.conflicts.entries) {
        if (!_conflictResolutions.containsKey(entry.key)) {
          unresolved[entry.key] = entry.value;
        }
      }

      if (unresolved.isEmpty) return;

      for (var entry in unresolved.entries) {
        final slot = entry.key;
        final parts = slot.split('_');
        final dayName = parts[0];
        final period = parts[1];

        if (!mounted) return;
        final chosen = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ConflictDialog(
            dayName: dayName,
            period: period,
            subjects: entry.value,
          ),
        );

        if (chosen != null) {
          _conflictResolutions[slot] = chosen;
        }
      }

      await _saveConflictResolutions();
      _future = _buildTimetable();
      if (mounted) setState(() {});
    } finally {
      _isShowingConflictDialog = false;
    }
  }

  Future<void> _resolveConflictSlot(String slot, List<String> subjects) async {
    if (_isShowingConflictDialog) return;
    _isShowingConflictDialog = true;
    try {
      final parts = slot.split('_');
      final chosen = await showDialog<String>(
        context: context,
        builder: (_) => ConflictDialog(
          dayName: parts[0],
          period: parts[1],
          subjects: subjects,
        ),
      );
      if (chosen != null) {
        _conflictResolutions[slot] = chosen;
        await _saveConflictResolutions();
        _future = _buildTimetable();
        if (mounted) setState(() {});
      }
    } finally {
      _isShowingConflictDialog = false;
    }
  }

  Widget _buildEmptyView(bool hasConflicts, int conflictCount) {
    final notSet = !SettingData().isGradeSet;
    final is1st = _grade == 1;

    String title;
    String buttonLabel;
    IconData buttonIcon;
    VoidCallback onPressed;

    if (_isTeacher) {
      title = AppLocalizations.of(context)!.timetable_setTeachingMsg;
      buttonLabel = AppLocalizations.of(context)!.timetable_setSetting; buttonIcon = Icons.settings;
      onPressed = () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTimetableSelectScreen()));
        _future = _buildTeacherTimetable(); setState(() {});
      };
    } else if (notSet) {
      title = AppLocalizations.of(context)!.timetable_setGradeMsg;
      buttonLabel = AppLocalizations.of(context)!.timetable_setGrade;
      buttonIcon = Icons.school;
      onPressed = () => _showClassPicker();
    } else if (is1st) {
      title = AppLocalizations.of(context)!.timetable_set1stMsg;
      buttonLabel = AppLocalizations.of(context)!.timetable_setGrade;
      buttonIcon = Icons.school;
      onPressed = () => _showClassPicker();
    } else {
      title = AppLocalizations.of(context)!.timetable_setSubjectMsg;
      buttonLabel = AppLocalizations.of(context)!.timetable_setSubject;
      buttonIcon = Icons.settings;
      onPressed = () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TimetableSelectScreen()),
        );
        setState(() => _future = _buildTimetable());
      };
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar_outlined, size: Responsive.r(context, 56),
                color: AppColors.theme.darkGreyColor),
            const SizedBox(height: 16),
            Text(title,
              style: TextStyle(fontSize: Responsive.sp(context, 17), fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(buttonIcon),
              label: Text(buttonLabel),
              style: _buttonStyle(),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.theme.primaryColor,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }

  Future<void> _showClassPicker() async {
    final pickerGrade = _grade > 0 ? _grade : 1;
    final pickerClass = _classNum > 0 ? _classNum : 1;
    final classCount = await TimetableDataApi.getClassCount(pickerGrade);
    if (!mounted) return;
    final result = await showDialog<List<int>>(
      context: context,
      builder: (_) => GradeAndClassPickerDialog(
        initialGrade: pickerGrade,
        initialClass: pickerClass,
        classCount: classCount > 0 ? classCount : 10,
      ),
    );
    if (result != null && result.length == 2) {
      _grade = result[0];
      _classNum = result[1];
      SettingData().grade = _grade;
      SettingData().classNum = _classNum;
      _syncGradeToFirestore(_grade, _classNum);

      if (_grade >= 2) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TimetableSelectScreen()),
        );
      }
      _conflictResolutions.clear();
      _future = _buildTimetable();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTeacher && SettingData().isGradeSet &&
        (_grade != SettingData().grade || _classNum != SettingData().classNum)) {
      _grade = SettingData().grade;
      _classNum = SettingData().classNum;
      _future = _buildTimetable();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        title: Text(_isTeacher ? AppLocalizations.of(context)!.timetable_teacherScreenTitle : SettingData().isGradeSet ? AppLocalizations.of(context)!.timetable_classTitle(_grade, _classNum) : AppLocalizations.of(context)!.timetable_screenTitle),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_isTeacher)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTimetableSelectScreen()));
                _future = _buildTeacherTimetable(); setState(() {});
              },
              tooltip: AppLocalizations.of(context)!.timetable_setting,
            ),
          if (!_isTeacher && _grade == 1)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: _showClassPicker,
              tooltip: AppLocalizations.of(context)!.timetable_changeClass,
            ),
          if (!_isTeacher && _grade >= 2)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _conflictResolutions.clear();
                _saveConflictResolutions();
                _future = _buildTimetable();
                setState(() {});
              },
              tooltip: AppLocalizations.of(context)!.timetable_refresh,
            ),
        ],
      ),
      body: FutureBuilder<_TimetableResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: AppLocalizations.of(context)!.timetable_loadError,
              onRetry: () { setState(() => _future = _buildTimetable()); },
            );
          }
          if (!snapshot.hasData) {
            return Center(child: Text(AppLocalizations.of(context)!.timetable_loadError));
          }

          final result = snapshot.data!;
          final isEmpty = result.grid.every(
              (day) => day.every((s) => s.isEmpty));

          if (isEmpty) return _buildEmptyView(false, 0);

          if (result.conflicts.isNotEmpty && !_isShowingConflictDialog) {
            final hasUnresolved = result.conflicts.keys
                .any((k) => !_conflictResolutions.containsKey(k));
            if (hasUnresolved) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showConflictResolver(result);
              });
            }
          }

          return _buildGridView(result, isDark);
        },
      ),
    ),
    );
  }

  String _formatClock(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Widget _buildGridView(_TimetableResult result, bool isDark) {
    final todayWeekday = _clockNow.weekday;
    final l10n = AppLocalizations.of(context)!;
    final days = [l10n.timetable_dayMon, l10n.timetable_dayTue, l10n.timetable_dayWed, l10n.timetable_dayThu, l10n.timetable_dayFri];
    int maxPeriod = 0;
    for (int d = 0; d < 5; d++) {
      for (int p = 6; p >= 0; p--) {
        if (result.grid[d][p].isNotEmpty) {
          if (p + 1 > maxPeriod) { maxPeriod = p + 1; }
          break;
        }
      }
    }
    if (maxPeriod == 0) maxPeriod = 7;

    return Column(children: [Expanded(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(10, 8, 10, MediaQuery.of(context).padding.bottom + 12),
      child: Column(children: [
        _buildTabToggle(l10n),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: CurrentSubjectCard(),
        ),
        const SizedBox(height: 12),
        _showWeekly
            ? _buildWeeklyGrid(result, isDark, days, maxPeriod, todayWeekday)
            : _buildTodayView(result, isDark, days, maxPeriod, todayWeekday, l10n),
      ]),
    ))]);
  }

  Widget _buildTabToggle(AppLocalizations l10n) {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).scaffoldBackgroundColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 2, offset: const Offset(0, 1))] : null,
          ),
          child: Center(child: Text(label, style: TextStyle(
            fontSize: Responsive.sp(context, 11.5),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Theme.of(context).textTheme.bodyLarge?.color : AppColors.theme.darkGreyColor,
          ))),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.theme.lightGreyColor, borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        segment(l10n.timetable_tabToday, !_showWeekly, () => setState(() => _showWeekly = false)),
        segment(l10n.timetable_tabWeekly, _showWeekly, () => setState(() => _showWeekly = true)),
      ]),
    );
  }

  Widget _buildWeeklyGrid(_TimetableResult result, bool isDark, List<String> days, int maxPeriod, int todayWeekday) {
    final currentPeriod = _currentPeriodIndex;
    return Column(children: [
        Row(children: [
          SizedBox(width: Responsive.w(context, 36)),
          ...List.generate(5, (i) {
            final isToday = todayWeekday == i + 1;
            return Expanded(child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: isToday ? BoxDecoration(color: AppColors.theme.primaryColor, borderRadius: BorderRadius.circular(12)) : null,
              child: Text(days[i], style: TextStyle(fontSize: Responsive.sp(context, 13), fontWeight: FontWeight.w700,
                color: isToday ? Colors.white : AppColors.theme.darkGreyColor)),
            )));
          }),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: Responsive.w(context, 36), child: Column(children: List.generate(maxPeriod, (p) {
            final isNow = p == currentPeriod && todayWeekday <= 5;
            return SizedBox(height: Responsive.r(context, 58), child: Center(child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 1.5),
              width: Responsive.w(context, 26),
              decoration: BoxDecoration(
                color: isNow ? AppColors.theme.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(child: Text('${p + 1}', style: TextStyle(fontSize: Responsive.sp(context, 12), fontWeight: FontWeight.w700,
                color: isNow ? Colors.white : AppColors.theme.darkGreyColor))),
            )));
          }))),
          ...List.generate(5, (day) {
            final isToday = todayWeekday == day + 1;
            return Expanded(child: Container(
              decoration: isToday ? BoxDecoration(
                color: (isDark ? AppColors.theme.tertiaryColor : AppColors.theme.primaryColor).withAlpha(23),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.theme.primaryColor.withAlpha(36), width: 1),
              ) : null,
              child: Column(children: List.generate(maxPeriod, (p) {
                final name = result.grid[day][p];
                final slot = '${days[day]}_${p + 1}';
                final isConflict = result.conflicts.containsKey(slot);
                return SizedBox(height: Responsive.r(context, 58), child: TimetableCell(subject: name, isConflict: isConflict, isDark: isDark, isToday: isToday,
                  isCurrentPeriod: isToday && p == currentPeriod,
                  customColor: _subjectColors.containsKey(name) ? Color(_subjectColors[name]! | 0xFF000000) : null,
                  onLongPress: name.isEmpty ? null : () => _showColorPicker(name),
                  onTap: isConflict ? () => _resolveConflictSlot(slot, result.conflicts[slot]!) : null));
              })),
            ));
          }),
        ]),
    ]);
  }

  Widget _buildTodayView(_TimetableResult result, bool isDark, List<String> days, int maxPeriod, int todayWeekday, AppLocalizations l10n) {
    if (todayWeekday > 5) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(l10n.widget_weekend,
          style: TextStyle(fontSize: Responsive.sp(context, 14), color: AppColors.theme.darkGreyColor))),
      );
    }

    final todayIndex = todayWeekday - 1;
    final currentPeriod = _currentPeriodIndex;
    final nowMinutes = _clockNow.hour * 60 + _clockNow.minute;
    final rows = <int>[for (int p = 0; p < maxPeriod; p++) if (result.grid[todayIndex][p].isNotEmpty) p];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(l10n.widget_noClass,
            style: TextStyle(fontSize: Responsive.sp(context, 14), color: AppColors.theme.darkGreyColor))),
        )
      else
        ...rows.map((p) {
          final name = result.grid[todayIndex][p];
          final slot = '${days[todayIndex]}_${p + 1}';
          final isConflict = result.conflicts.containsKey(slot);
          final isCurrent = p == currentPeriod;
          final endMin = _periodTimes[p][2] * 60 + _periodTimes[p][3];
          final isPast = nowMinutes >= endMin;
          final accentColor = TimetableCell.colorsFor(name, isDark,
              _subjectColors.containsKey(name) ? Color(_subjectColors[name]! | 0xFF000000) : null).text;

          return Opacity(
            opacity: isPast && !isCurrent ? 0.55 : 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: GestureDetector(
                onTap: isConflict ? () => _resolveConflictSlot(slot, result.conflicts[slot]!) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: isConflict ? TimetableCell.conflictColorFor(isDark) : AppColors.theme.lightGreyColor,
                      width: isConflict || isCurrent ? 1.5 : 1,
                    ),
                    boxShadow: isCurrent ? [BoxShadow(color: AppColors.theme.primaryColor.withAlpha(40), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${p + 1}', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: Responsive.sp(context, 11), fontWeight: FontWeight.w700, color: AppColors.theme.darkGreyColor))),
                    const SizedBox(width: 8),
                    Container(width: 3, height: 26, decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 9),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(fontSize: Responsive.sp(context, 13.5), fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color)),
                      if (isConflict)
                        Text(l10n.timetable_conflictHint, style: TextStyle(fontSize: Responsive.sp(context, 10.5), fontWeight: FontWeight.w600,
                          color: TimetableCell.conflictColorFor(isDark)))
                      else
                        Text('${_formatClock(_periodTimes[p][0], _periodTimes[p][1])} - ${_formatClock(_periodTimes[p][2], _periodTimes[p][3])}',
                          style: TextStyle(fontSize: Responsive.sp(context, 10.5), color: AppColors.theme.mealTypeTextColor)),
                    ])),
                    if (isCurrent)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.theme.primaryColor, borderRadius: BorderRadius.circular(7)),
                        child: Text(l10n.timetable_current, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)))
                    else if (isConflict)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: TimetableCell.conflictColorFor(isDark).withAlpha(40), borderRadius: BorderRadius.circular(7)),
                        child: Text(l10n.timetable_conflictBadge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: TimetableCell.conflictColorFor(isDark)))),
                  ]),
                ),
              ),
            ),
          );
        }),
      const SizedBox(height: 16),
      Text(l10n.timetable_thisWeek, style: TextStyle(fontSize: Responsive.sp(context, 11), fontWeight: FontWeight.w700, color: AppColors.theme.darkGreyColor)),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.theme.lightGreyColor),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: List.generate(5, (day) {
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(children: [
              Text(days[day], style: TextStyle(fontSize: Responsive.sp(context, 10), fontWeight: FontWeight.w600, color: AppColors.theme.darkGreyColor)),
              const SizedBox(height: 4),
              ...List.generate(maxPeriod, (p) {
                final name = result.grid[day][p];
                final barColor = name.isEmpty
                    ? AppColors.theme.lightGreyColor
                    : TimetableCell.colorsFor(name, isDark, _subjectColors.containsKey(name) ? Color(_subjectColors[name]! | 0xFF000000) : null).bg;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Container(height: 8, decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(3))),
                );
              }),
            ]),
          ));
        })),
      ),
    ]);
  }

  Future<void> _syncGradeToFirestore(int g, int c) async {
    if (!AuthService.isLoggedIn) return;
    try {
      final uid = AuthService.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'grade': g,
        'classNum': c,
      });
    } catch (e) {
      log('TimetableViewScreen: Firestore grade sync error: $e');
    }
  }
}

class _TimetableResult {
  final List<List<String>> grid;
  final Map<String, List<String>> conflicts;
  _TimetableResult({required this.grid, required this.conflicts}) {
    _saveGridAndUpdateWidget(grid);
  }

  static Future<void> _saveGridAndUpdateWidget(List<List<String>> grid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = grid.map((row) => row.join(',')).toList();
      await prefs.setStringList('widget_timetable_grid', encoded);
      await WidgetService.updateTimetableWidget();
    } catch (e) {
      log('TimetableViewScreen: save grid error: $e');
    }
  }
}
