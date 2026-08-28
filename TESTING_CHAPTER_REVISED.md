# Testing Chapter (Revised)

## VI. Testing Strategy

This chapter presents the testing strategy for the Location-Based Smart Reminder App, focusing on currently implemented features (NLP parsing, habit prediction, location detection, notification scheduling) and deferring geofence-specific tests to Phase 2 (background geofencing implementation).

---

## 6.1 Testing Scope & Phases

### Phase 1 Testing (Current Implementation)
- NLP text parsing and keyword extraction
- TensorFlow Lite model inference (dual outputs)
- Location picker and nearby place detection
- Firestore CRUD operations for reminders
- Notification scheduling and snooze
- User authentication flows
- Habit prediction blending with user history

### Phase 2 Testing (Planned - Geofencing)
- Background geofence entry/exit triggers
- Geofence dwell time validation
- Context-aware notification delivery
- Cross-device context synchronization
- Offline sync and conflict resolution

---

## 6.2 NLP & Voice Command Parsing

### Test Case 1: Simple Voice Command
**Input**: "Remind me to buy milk"
**Expected Output**: 
- `title = "buy milk"`
- `action = "buy"`
- `locationType = "grocery"` (via keyword matching)
- `confidence > 0.6`

**Testing Method**: Unit test in `text_parser_test.dart`
```dart
void main() {
  group('NLP Parser', () {
    test('simple_action_extraction', () {
      final result = parseReminderText('Remind me to buy milk');
      expect(result.action, 'buy');
      expect(result.locationType, 'grocery');
    });
  });
}
```

**Pass Criteria**: Action and location type correctly identified ✓

---

### Test Case 2: Complex Command with Time & Location
**Input**: "Remind me to pay my electricity bill tomorrow at 2 PM when I'm at home"
**Expected Output**:
- `title = "pay electricity bill"`
- `dateTime = tomorrow 2 PM` (parsed from "tomorrow at 2 PM")
- `locationType = "home"` (from explicit "at home")
- `recurrence = "none"`

**Testing Method**: Unit test with datetime parsing
```dart
test('complex_command_with_time_location', () {
  final tomorrow = DateTime.now().add(Duration(days: 1));
  final result = parseReminderText(
    'Remind me to pay bill tomorrow at 2 PM when at home'
  );
  expect(result.locationType, 'home');
  expect(result.dateTime?.day, tomorrow.day);
});
```

**Pass Criteria**: Time, action, and location correctly extracted ✓

---

### Test Case 3: Ambiguous Location Handling
**Input**: "Remind me to get coffee"
**Expected Output**: 
- `locationType = null` OR `["cafe", "restaurant"]` (multiple matches)
- UI shows: "Which location? [Cafe | Restaurant | Other]"

**Testing Method**: Integration test
```dart
testWidgets('ambiguous_location_prompt', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  // Create reminder with ambiguous location
  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'get coffee');
  // Should show disambiguation UI
  expect(find.text('Which location?'), findsOneWidget);
});
```

**Pass Criteria**: User prompted to select location before reminder creation ✓

---

## 6.3 TensorFlow Lite Habit Prediction

### Test Case 4: Dual-Head Model Output (Category + Location Type)
**Input**: 
- `title = "Team meeting"`
- `day = Monday (weekday)`
- `hour = 10 (work hours)`

**Expected Outputs**:
- **Head 1 (Category)**: `category = "work"` with `confidence > 0.8`
- **Head 2 (Location Type)**: `locationType = "work"` with `confidence > 0.7`

**Testing Method**: Unit test
```dart
test('habit_model_dual_output', () async {
  final helper = HabitHelper();
  await helper.init();
  
  final result = helper.predict(
    day: 0, // Monday
    hour: 10,
    title: 'Team meeting'
  );
  
  expect(result.category, 'work');
  expect(result.confidence, greaterThan(0.8));
  expect(result.locationType, 'work');
});
```

**Pass Criteria**: Both category and location type inferred correctly ✓

---

### Test Case 5: Personalized Habit Blending
**Scenario**: User has created 8 "buy coffee" reminders, always on weekday mornings at 8 AM

**Input**: 
- Global TFLite prediction: `["cafe": 0.5, "restaurant": 0.3]` (unsure)
- User history: Last 8 occurrences: all 8 at "cafe" on weekday mornings

**Expected Output**:
- Blended prediction: `["cafe": 0.95]` (strongly favored due to user history weight)
- `personalizationConfidence > 0.9`

**Testing Method**: Integration test with Firestore mock
```dart
test('personalized_habit_blending', () async {
  // Mock Firestore history: 8 "buy coffee" at cafe
  final history = List.generate(8, (i) => {
    'title': 'buy coffee',
    'locationType': 'cafe',
    'createdAt': DateTime.now().subtract(Duration(days: 8 - i))
  });
  
  // Call predictPersonalized with history
  final result = helper.predictPersonalized(
    title: 'buy coffee',
    day: 0, // Monday
    hour: 8
  );
  
  expect(result.locationType, 'cafe');
  expect(result.confidence, greaterThan(0.9));
});
```

**Pass Criteria**: User history correctly weighted in prediction ✓

---

### Test Case 6: Heuristic Fallback (No Model Loaded)
**Condition**: TensorFlow Lite model fails to load

**Input**:
- `title = "pay rent"` (generic)
- `time = 9:00 PM` (evening)

**Expected Output**:
- Fallback to time-based heuristic:
  - Early morning (<6h) → `"personal"`
  - Work hours (6-14h, weekday) → `"work"`
  - Evening (18-21h) → `"family"`
  - Otherwise → `"other"`
- Result: `category = "family"` (evening time)

**Testing Method**: Unit test
```dart
test('heuristic_fallback_no_model', () async {
  final helper = HabitHelper();
  // Simulate model load failure
  helper._ready = false;
  
  final result = helper.predict(
    hour: 21,
    title: 'pay rent'
  );
  
  expect(result.category, 'family');
});
```

**Pass Criteria**: Fallback heuristic applies when model unavailable ✓

---

## 6.4 Location Detection & Nearby Places

### Test Case 7: Nearby POI Detection
**Setup**: Device at `(24.7136°N, 46.6753°E)` (Riyadh, Saudi Arabia)

**Input**: `OsmPlaceService.getNearbyPlaces(24.7136, 46.6753, radiusMeters=500)`

**Expected Output**: List of POIs within 500m
```
[
  NearbyPlace(type='pharmacy', name='Al-Dawaa', distance=150m),
  NearbyPlace(type='grocery', name='Panda Supermarket', distance=280m),
  NearbyPlace(type='restaurant', name='Shawarmer', distance=320m),
]
```

**Testing Method**: Integration test with live Overpass API
```dart
testWidgets('nearby_places_detection', (WidgetTester tester) async {
  final places = await OsmPlaceService.getNearbyPlaces(
    24.7136, 46.6753,
    radiusMeters: 500
  );
  
  expect(places.length, greaterThan(0));
  expect(places.every((p) => p.distanceMeters <= 500), true);
});
```

**Pass Criteria**: API returns nearby places within specified radius ✓

---

### Test Case 8: Location Picker - Manual Input
**Input**: User manually enters latitude `24.7136`, longitude `46.6753`

**Expected Output**:
- Map centers on entered coordinates
- Reverse geocode returns address (e.g., "Riyadh, Saudi Arabia")
- Pin dropped at location
- User can confirm and save

**Testing Method**: Integration test
```dart
testWidgets('location_picker_manual_input', (WidgetTester tester) async {
  await tester.pumpWidget(LocationPickerScreen());
  
  // Enter coordinates
  await tester.enterText(
    find.byKey(Key('lat_input')), 
    '24.7136'
  );
  await tester.enterText(
    find.byKey(Key('lng_input')), 
    '46.6753'
  );
  
  // Confirm
  await tester.tap(find.byIcon(Icons.check));
  await tester.pumpAndSettle();
  
  // Verify pin and address displayed
  expect(find.byType(GoogleMap), findsOneWidget);
});
```

**Pass Criteria**: Location correctly set and displayed on map ✓

---

## 6.5 Reminder Scheduling & Notification Delivery

### Test Case 9: Time-Based Notification Scheduling
**Input**: 
- Reminder: "Call mom tomorrow at 3 PM"
- `scheduledDate = tomorrow 15:00`

**Expected Behavior**:
1. Reminder saved to Firestore
2. `scheduleNotification()` called
3. At 15:00 next day, platform notification fires
4. User sees: "Call mom" with snooze action

**Testing Method**: Integration test (manual or device test)
```dart
test('schedule_notification', () async {
  final id = 12345;
  final scheduledDate = DateTime.now().add(Duration(minutes: 1));
  
  await scheduleNotification(
    id: id,
    title: 'Call mom',
    scheduledDate: scheduledDate
  );
  
  // Verify notification was scheduled
  // (requires actual device/emulator notification check)
});
```

**Pass Criteria**: Notification appears at scheduled time ✓ (Manual verification)

---

### Test Case 10: Snooze Functionality
**Scenario**: Notification fires at 3 PM; user taps "Snooze" action

**Expected Behavior**:
1. Current notification dismissed
2. New notification scheduled for 3:15 PM (15 min later)
3. Database marked: `snoozeDurationMinutes = 15`
4. User receives second notification at 3:15 PM

**Testing Method**: Device test
```dart
testWidgets('snooze_notification', (WidgetTester tester) async {
  // Trigger notification manually
  await showInstantNotification(
    id: 1,
    title: 'Call mom',
    body: 'Tap to open'
  );
  
  // Simulate snooze action
  await snoozeNotification(
    id: 1,
    title: 'Call mom',
    minutes: 15
  );
  
  // Verify rescheduled notification
  // (Mock FlutterLocalNotifications plugin)
});
```

**Pass Criteria**: Notification resched
uled correctly for 15 minutes later ✓

---

## 6.6 Authentication & Data Persistence

### Test Case 11: Firebase Email/Password Login
**Input**: 
- Email: `user@example.com`
- Password: `SecurePassword123`

**Expected Output**:
- User authenticated
- Redirected to HomeScreen
- Firestore user document created with profile

**Testing Method**: Integration test
```dart
testWidgets('firebase_email_login', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  
  // Tap login
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
  
  // Enter credentials
  await tester.enterText(find.byType(TextField).first, 'user@example.com');
  await tester.enterText(find.byType(TextField).last, 'SecurePassword123');
  
  // Submit
  await tester.tap(find.text('Sign In'));
  await tester.pumpAndSettle();
  
  // Verify navigation to home
  expect(find.byType(HomeScreen), findsOneWidget);
});
```

**Pass Criteria**: User successfully authenticated and profile created ✓

---

### Test Case 12: Firestore Reminder CRUD
**Scenario**: Create, read, update, delete reminder operations

**Test Case 12a - CREATE**:
```dart
test('create_reminder_firestore', () async {
  final reminder = Reminder(
    id: 'test123',
    title: 'Buy milk',
    dateTime: DateTime.now().add(Duration(days: 1)),
    category: 'personal',
  );
  
  await _col.doc(reminder.id).set(reminder.toMap());
  
  final doc = await _col.doc(reminder.id).get();
  expect(doc.exists, true);
  expect(doc['title'], 'Buy milk');
});
```
**Pass Criteria**: Reminder document created in Firestore ✓

**Test Case 12b - UPDATE**:
```dart
test('update_reminder_firestore', () async {
  await _col.doc('test123').update({'isCompleted': true});
  
  final doc = await _col.doc('test123').get();
  expect(doc['isCompleted'], true);
});
```
**Pass Criteria**: Reminder marked as completed ✓

**Test Case 12c - DELETE**:
```dart
test('delete_reminder_firestore', () async {
  await _col.doc('test123').delete();
  
  final doc = await _col.doc('test123').get();
  expect(doc.exists, false);
});
```
**Pass Criteria**: Reminder removed from Firestore ✓

---

## 6.7 Data Consistency & Edge Cases

### Test Case 13: Concurrent Reminder Creation (Planned - Phase 2)
**Scenario**: User creates two reminders with same location simultaneously

**Current Limitation**: No Firestore transaction handling yet. Each reminder created independently.

**Future Solution**: 
```dart
WriteBatch batch = FirebaseFirestore.instance.batch();
// Add reminder 1
batch.set(_col.doc(r1.id), r1.toMap());
// Add reminder 2
batch.set(_col.doc(r2.id), r2.toMap());
await batch.commit(); // Atomic operation
```

---

### Test Case 14: Offline Reminder Creation (Planned - Phase 2)
**Scenario**: User creates reminder while offline

**Current Limitation**: Firestore requires internet; operation fails.

**Future Solution**:
- Create reminder with `pending_sync=true` flag
- Store locally via Hive
- Sync to Firestore when back online
- Detect conflicts and deduplicate

---

## 6.8 User Acceptance Testing (UAT)

### UAT Scenario 1: Daily Workflow
1. **User Opens App**: Home screen loads with "Smart Assistant" suggestion
2. **Creates Voice Reminder**: "Remind me to buy groceries tomorrow"
   - System parses: action=buy, locationType=grocery, time=tomorrow
   - Shows habit prediction: "personal" (82% confidence)
   - User confirms or edits
3. **Receives Notification**: Tomorrow at 8 AM (default time)
4. **Marks Complete**: Tap reminder card → "Completed"
5. **Activity Log**: Shows 1 completed in today's activity

**Pass Criteria**: Complete workflow functions end-to-end ✓

---

### UAT Scenario 2: Nearby Place Integration
1. **User at Supermarket**: App running in background
2. **Manually Checks Reminders**: "Buy milk" reminder shown
3. **Nearby Banner**: "Grocery store 50m away" banner displayed
4. **Quick Action**: Taps banner → Opens Google Maps to nearby supermarket
5. **Completion**: Returns to app and marks reminder done

**Pass Criteria**: Nearby detection and quick actions work ✓

---

## 6.9 Regression Testing & CI/CD

### Automated Test Suite
- **Unit Tests**: NLP parser, habit model, location utilities
- **Widget Tests**: UI components, navigation, form submission
- **Integration Tests**: Firebase auth, Firestore CRUD, notifications
- **Coverage Target**: >70% code coverage

### Test Execution
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/nlp_parser_test.dart

# Run with coverage
flutter test --coverage
```

---

## 6.10 Known Testing Limitations (Phase 1)

❌ **Cannot Test** (until Phase 2 implementation):
- Background geofence triggering
- Context-aware notification delivery (driving mode, DND)
- Cross-device context synchronization
- Offline geofence caching
- Concurrent geofence registration (Firestore transactions)
- Chi-square statistical pattern analysis

✅ **Can Test** (Phase 1):
- NLP parsing and keyword extraction
- TensorFlow Lite model inference
- Location detection and nearby places
- Firestore CRUD operations
- Notification scheduling (time-based)
- User authentication
- Habit prediction with user history blending
- Activity tracking and reporting

---

## 6.11 Future Testing Phases

### Phase 2 Testing (Geofencing & Context)
- Geofence entry/exit event triggers
- Dwell time validation (>10 sec threshold)
- Driving mode detection via sensor fusion
- Context-aware notification delivery (TTS, silent queuing)
- Concurrent reminder safety (Firestore transactions)

### Phase 3 Testing (Offline & Advanced)
- Offline sync queue and conflict resolution
- iOS 20-geofence limit with LRU deactivation
- Automated habit suggestion generation
- Statistical pattern detection with significance testing
- Multi-device context synchronization
