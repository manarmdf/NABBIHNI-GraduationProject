import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../shared/ocr_helper.dart' as ocr;
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'reminder_model.dart';
import '../location/location_picker_screen.dart';
import '../location/user_locations_service.dart';
import '../shared/constants.dart';
import '../shared/habit_helper.dart';
import '../shared/text_parser.dart' as nlp;
import 'widgets/mic_button.dart';
import 'widgets/suggestion_chips.dart';
import 'widgets/place_type_picker.dart';
import 'widgets/category_chip.dart';
import 'widgets/date_time_chip.dart';

/// ورقة إضافة/تعديل تذكير — تُرجع كائن [Reminder] عند الحفظ أو null عند الإلغاء.
class AddReminderSheet extends StatefulWidget {
  final String prefill;
  final DateTime? prefillDate;
  final String? prefillCategory;
  final String? prefillLocationType;
  final String? existingId;
  final stt.SpeechToText speech;
  final bool speechAvailable;
  final HabitHelper habitHelper;
  final Map<String, UserLocation> personalLocs;

  const AddReminderSheet({
    super.key,
    required this.prefill,
    this.prefillDate,
    this.prefillCategory,
    this.prefillLocationType,
    this.existingId,
    required this.speech,
    required this.speechAvailable,
    required this.habitHelper,
    this.personalLocs = const {},
  });

  bool get isEditing => existingId != null;

  @override
  State<AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<AddReminderSheet> {
  late final TextEditingController _titleCtrl;
  DateTime? _pickedDate;
  TimeOfDay? _pickedTime;
  String _category = 'personal';
  String? _locationType;
  bool _categoryManuallySet = false;
  bool _timeManuallySet = false;
  List<HabitSuggestion> _suggestions = [];
  String _speechLang = 'en';
  String _priority = 'medium';
  Timer? _debounceTimer;

  double? _pickedLat;
  double? _pickedLng;
  String? _pickedAddress;

  // ── دورة الحياة ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _locationType = widget.prefillLocationType;

    nlp.ParsedReminder? parsed;
    if (widget.prefillDate != null) {
      _pickedDate = widget.prefillDate;
      _pickedTime = TimeOfDay.fromDateTime(widget.prefillDate!);
      _titleCtrl = TextEditingController(text: widget.prefill);
      if (widget.prefill.isNotEmpty) {
        parsed = nlp.parseReminderText(widget.prefill);
      }
    } else if (widget.prefill.isNotEmpty) {
      parsed = nlp.parseReminderText(widget.prefill);
      _titleCtrl = TextEditingController(
        text: parsed.title.isNotEmpty ? parsed.title : widget.prefill,
      );
      if (parsed.dateTime != null) {
        _pickedDate = parsed.dateTime;
        _pickedTime = TimeOfDay(
          hour: parsed.dateTime!.hour,
          minute: parsed.dateTime!.minute,
        );
        _timeManuallySet = true;
      }
    } else {
      _titleCtrl = TextEditingController(text: widget.prefill);
    }

    if (_locationType == null && parsed?.locationType != null) {
      _locationType = parsed!.locationType;
    }

    if (widget.prefillCategory != null) {
      _category = widget.prefillCategory!;
      _categoryManuallySet = true;
    } else if (parsed?.category != null) {
      _category = parsed!.category!;
      _categoryManuallySet = true;
      _suggestFromTitle(_titleCtrl.text, preparsed: parsed);
    } else {
      _suggestFromTitle(_titleCtrl.text, preparsed: parsed);
    }

    _titleCtrl.addListener(_onTitleChanged);
  }

  /// يُستدعى عند تغيير نص العنوان — يحلّل النص تلقائياً بعد تأخير قصير.
  void _onTitleChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final text = _titleCtrl.text;
      if (text.trim().length >= 2) {
        final parsed = nlp.parseReminderText(text);
        if (parsed.dateTime != null && !_timeManuallySet) {
          setState(() {
            _pickedDate = parsed.dateTime;
            _pickedTime = TimeOfDay(
              hour: parsed.dateTime!.hour,
              minute: parsed.dateTime!.minute,
            );
          });
        }
      }
      _suggestFromTitle(text);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── منطق الاقتراحات ───────────────────────────────────────────────────

  /// يولّد اقتراحات الفئة والموقع من عنوان التذكير باستخدام نموذج ML.
  void _suggestFromTitle(String text, {nlp.ParsedReminder? preparsed}) {
    if (text.trim().length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final parsed = preparsed ?? nlp.parseReminderText(text);
    final top = widget.habitHelper.predictAll(title: text).take(3).toList();
    if (top.isNotEmpty && mounted) {
      setState(() {
        _suggestions = top;
        if (!_categoryManuallySet) {
          _category = parsed.category ?? top.first.category;
        }
        _locationType ??= parsed.locationType ?? top.first.locationType;
      });
    } else if (mounted && _suggestions.isNotEmpty) {
      setState(() => _suggestions = []);
    }
  }

  /// يُرجع الوقت الافتراضي حسب الفئة.
  TimeOfDay _defaultTimeFor(String category) => switch (category) {
    'work' => const TimeOfDay(hour: 9, minute: 0),
    'family' => const TimeOfDay(hour: 19, minute: 0),
    'personal' => const TimeOfDay(hour: 6, minute: 0),
    _ => const TimeOfDay(hour: 17, minute: 0),
  };

  /// يُطبّق اقتراح الذكاء الاصطناعي على الحقول.
  void _applySuggestion(HabitSuggestion s) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    setState(() {
      _category = s.category;
      _pickedDate ??= today;
      if (!_timeManuallySet) _pickedTime = _defaultTimeFor(s.category);
      _categoryManuallySet = true;
      _suggestions = [];
    });
  }

  // ── الحفظ ──────────────────────────────────────────────────────────────

  /// يحفظ التذكير ويعيده عبر Navigator.pop.
  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final effectiveTime = _pickedTime ?? _defaultTimeFor(_category);
    DateTime? dt;
    if (_pickedDate != null) {
      dt = DateTime(
        _pickedDate!.year, _pickedDate!.month, _pickedDate!.day,
        effectiveTime.hour, effectiveTime.minute,
      );
    }

    if (_locationType == null && title.isNotEmpty) {
      final parsed = nlp.parseReminderText(title);
      if (parsed.locationType != null) {
        _locationType = parsed.locationType;
      } else {
        final top = widget.habitHelper.predictAll(title: title);
        if (top.isNotEmpty && top.first.locationType != null) {
          _locationType = top.first.locationType;
        }
      }
    }

    Navigator.pop(
      context,
      Reminder(
        id: widget.existingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        dateTime: dt,
        category: _category,
        locationType: _locationType,
        lat: _pickedLat,
        lng: _pickedLng,
        address: _pickedAddress,
        priority: _priority,
      ),
    );
  }

  // ── بناء الواجهة ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildTitleRow(),
            const SizedBox(height: 8),
            if (widget.speechAvailable) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Voice Input Lang: ',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'ar', label: Text('AR', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_speechLang},
                    onSelectionChanged: (set) => setState(() => _speechLang = set.first),
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_suggestions.isNotEmpty && !widget.isEditing)
              SuggestionChips(
                suggestions: _suggestions,
                defaultTimeFor: _defaultTimeFor,
                pickedDate: _pickedDate,
                pickedTime: _pickedTime,
                onPick: _applySuggestion,
                onDismiss: () => setState(() => _suggestions = []),
              ),
            const SizedBox(height: 8),
            _buildLocationField(),
            const SizedBox(height: 8),
            _buildDateTimeRow(),
            const SizedBox(height: 12),
            _buildCategoryRow(),
            const SizedBox(height: 12),
            _buildPriorityRow(),
            const SizedBox(height: 12),
            _buildSummaryBar(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.isEditing ? 'Update Reminder' : 'Save Reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// يبني رأس الورقة (عنوان + زر إغلاق).
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(widget.isEditing ? 'Edit Reminder' : 'New Reminder',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  /// يبني صف إدخال العنوان مع أزرار الميكروفون والكاميرا.
  Widget _buildTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _titleCtrl,
            autofocus: widget.prefill.isEmpty,
            minLines: 1, maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: 'What do you need to remember?'),
          ),
        ),
        const SizedBox(width: 8),
        MicButton(
          speech: widget.speech, available: widget.speechAvailable,
          lang: _speechLang,
          onResult: (text) {
            final parsed = nlp.parseReminderText(text);
            setState(() {
              _titleCtrl.text = parsed.title.isNotEmpty ? parsed.title : text;
              _titleCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _titleCtrl.text.length));
              if (parsed.dateTime != null) {
                _pickedDate = parsed.dateTime;
                _pickedTime = TimeOfDay(hour: parsed.dateTime!.hour, minute: parsed.dateTime!.minute);
                _timeManuallySet = true;
              }
              if (_locationType == null && parsed.locationType != null) _locationType = parsed.locationType;
              if (!_categoryManuallySet && parsed.category != null) {
                _category = parsed.category!;
                _categoryManuallySet = true;
              }
            });
          },
        ),
        const SizedBox(width: 4),
        _buildOcrButton(),
      ],
    );
  }

  /// يبني زر مسح الصور (OCR).
  Widget _buildOcrButton() {
    return IconButton(
      icon: const Icon(Icons.document_scanner_outlined, color: AppColors.textSecondary),
      tooltip: 'Scan note image',
      onPressed: _pickAndScanImage,
    );
  }

  /// يعرض نافذة تحميل أثناء مسح الصورة.
  void _showOcrLoading() {
    showDialog<void>(
      context: context, barrierDismissible: false, useRootNavigator: true,
      builder: (_) => const _OcrLoadingDialog(),
    );
  }

  /// يلتقط صورة من الكاميرا ويستخرج النص منها بالـ OCR.
  Future<void> _pickAndScanImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;

    _showOcrLoading();
    String scannedText = '';
    try {
      scannedText = await ocr.recognizeText(picked.path);
    } catch (e) {
      debugPrint('OCR error: $e');
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    try {
      if (scannedText.isNotEmpty) {
        final parsed = nlp.parseReminderText(scannedText);
        setState(() {
          _titleCtrl.text = parsed.title.isNotEmpty ? parsed.title : scannedText;
          _titleCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _titleCtrl.text.length));
          if (parsed.dateTime != null) {
            _pickedDate = parsed.dateTime;
            _pickedTime = TimeOfDay(hour: parsed.dateTime!.hour, minute: parsed.dateTime!.minute);
            _timeManuallySet = true;
          }
          if (_locationType == null && parsed.locationType != null) _locationType = parsed.locationType;
          if (!_categoryManuallySet && parsed.category != null) {
            _category = parsed.category!;
            _categoryManuallySet = true;
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No text found in image')));
      }
    } catch (e) {
      debugPrint('OCR error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR failed: $e')));
      }
    }
  }

  /// يبني صف اختيار التاريخ والوقت.
  Widget _buildDateTimeRow() {
    return Row(
      children: [
        Expanded(
          child: DateTimeChip(
            icon: Icons.calendar_today_outlined,
            label: _pickedDate != null ? DateFormat('EEE, MMM d').format(_pickedDate!) : 'Date',
            active: _pickedDate != null,
            onTap: () async {
              final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              final d = await showDatePicker(
                context: context, initialDate: _pickedDate ?? today,
                firstDate: today, lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _pickedDate = d);
            },
            onClear: _pickedDate != null
                ? () => setState(() { _pickedDate = null; _pickedTime = null; _timeManuallySet = false; })
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DateTimeChip(
            icon: Icons.access_time_outlined,
            label: _pickedTime != null ? _pickedTime!.format(context) : 'Time',
            active: _pickedTime != null,
            onTap: () async {
              final t = await showTimePicker(
                context: context, initialTime: _pickedTime ?? TimeOfDay.now(),
              );
              if (t != null) setState(() { _pickedTime = t; _timeManuallySet = true; });
            },
            onClear: _pickedTime != null
                ? () => setState(() { _pickedTime = null; _timeManuallySet = false; })
                : null,
          ),
        ),
      ],
    );
  }

  /// يبني صف اختيار الفئة (شخصي / عمل / عائلة / أخرى).
  Widget _buildCategoryRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Category', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            CategoryChip(label: 'Personal', icon: Icons.favorite_rounded, color: Colors.pinkAccent,
              selected: _category == 'personal',
              onTap: () => setState(() { _category = 'personal'; _categoryManuallySet = true; })),
            const SizedBox(width: 8),
            CategoryChip(label: 'Work', icon: Icons.work_outline_rounded, color: AppColors.primary,
              selected: _category == 'work',
              onTap: () => setState(() { _category = 'work'; _categoryManuallySet = true; })),
            const SizedBox(width: 8),
            CategoryChip(label: 'Family', icon: Icons.group_outlined, color: AppColors.success,
              selected: _category == 'family',
              onTap: () => setState(() { _category = 'family'; _categoryManuallySet = true; })),
            const SizedBox(width: 8),
            CategoryChip(label: 'Other', icon: Icons.more_horiz, color: AppColors.textSecondary,
              selected: _category == 'other',
              onTap: () => setState(() { _category = 'other'; _categoryManuallySet = true; })),
          ]),
        ),
      ],
    );
  }

  /// يفتح شاشة اختيار الموقع على الخريطة.
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(
        title: 'Pick Location', initialLat: _pickedLat, initialLng: _pickedLng,
      )),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickedLat = result.lat;
      _pickedLng = result.lng;
      _pickedAddress = result.address;
      _locationType = null;
    });
  }

  /// يبني حقل الموقع — خريطة أو شرائح أنواع الأماكن.
  Widget _buildLocationField() {
    final hasSpecific = _pickedAddress != null || _pickedLat != null;
    final hasGeneric  = _locationType != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openLocationPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: hasSpecific ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(10),
              color: hasSpecific ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
            ),
            child: Row(children: [
              Icon(hasSpecific ? Icons.pin_drop_rounded : Icons.location_on_outlined,
                size: 20, color: hasSpecific ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: hasSpecific
                    ? Text(
                        _pickedAddress != null
                            ? _pickedAddress!.length > 50
                                  ? '${_pickedAddress!.substring(0, 50)}…'
                                  : _pickedAddress!
                            : '${_pickedLat!.toStringAsFixed(5)}, ${_pickedLng!.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        maxLines: 2, overflow: TextOverflow.ellipsis)
                    : const Text('Tap to pick location on map',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              if (hasSpecific)
                GestureDetector(
                  onTap: () => setState(() { _pickedLat = null; _pickedLng = null; _pickedAddress = null; }),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textSecondary))
              else
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ]),
          ),
        ),
        if (!hasSpecific) ...[
          const SizedBox(height: 6),
          PlaceTypePicker(
            selected: hasGeneric ? _locationType : null,
            preferredFirst: _suggestions.isNotEmpty ? _suggestions.first.locationType : null,
            onChanged: (val) => setState(() => _locationType = val),
            personalLocs: widget.personalLocs,
          ),
        ],
      ],
    );
  }

  /// يبني صف اختيار الأولوية (عالية / متوسطة / منخفضة).
  Widget _buildPriorityRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Priority', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'high', label: Text('High')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'low', label: Text('Low')),
            ],
            selected: {_priority},
            onSelectionChanged: (set) => setState(() => _priority = set.first),
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }

  /// يبني شريط ملخص التذكير قبل الحفظ.
  Widget _buildSummaryBar() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return const SizedBox.shrink();

    final parts = <String>[];
    parts.add('"$title"');
    if (_pickedDate != null) parts.add(DateFormat('EEE, MMM d').format(_pickedDate!));
    if (_pickedTime != null) {
      final h = _pickedTime!.hour;
      final m = _pickedTime!.minute;
      final ampm = h >= 12 ? 'PM' : 'AM';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      parts.add('$h12:${m.toString().padLeft(2, '0')} $ampm');
    }
    parts.add(_category);
    if (_locationType != null) parts.add(_locationType!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.summarize_outlined, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(parts.join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// نافذة تحميل OCR — تُعرض أثناء مسح الصورة.
class _OcrLoadingDialog extends StatelessWidget {
  const _OcrLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(width: 40, height: 40,
              child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(height: 16),
            Text('Reading text from image…',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            SizedBox(height: 4),
            Text('This can take up to a minute.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
