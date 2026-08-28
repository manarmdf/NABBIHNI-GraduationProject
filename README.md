# Nabbihni

**Nabbihni** is a bilingual smart reminder mobile application built with Flutter. It helps users create, organize, and receive reminders using manual input, natural-language text, voice input, handwritten-note recognition, personalized suggestions, scheduled notifications, and location-aware reminder triggers.

The application supports both **Arabic** and **English**.

## Main Features

### Reminder Management

Users can create, view, edit, complete, and delete reminders. A reminder may include:

- Title
- Date and time
- Category
- Priority
- Location type
- Optional coordinates and address
- Snooze duration
- Completion status

When a reminder includes a date and time, the application schedules a local notification. Editing a reminder reschedules the alert, while deleting a reminder cancels the related notification.

### Natural-Language Reminder Extraction

Users can enter a reminder as a normal sentence instead of filling every field manually.

Examples:

```text
Remind me to buy medicine tomorrow at 5pm
ذكرني أشتري حليب بكرة الساعة ٦ مساء
```

The parser extracts structured information such as the task title, date, time, category, and location type. It supports English and Arabic expressions, including Arabic numerals such as `٠١٢٣٤٥٦٧٨٩`.

### Voice Reminder Input

The application supports speech-to-text input for faster reminder creation. The extracted text is processed by the same natural-language parser used for typed reminders.

### Handwriting Reminder and Task Extraction

Users can select an image from the camera or gallery. The image is converted to Base64 and sent to an Ollama-compatible vision endpoint. The vision model is instructed to:

- Read English and Arabic handwriting
- Ignore crossed-out words
- Correct obvious recognition mistakes caused by unclear handwriting
- Preserve the original language
- Return only the clean extracted text

The extracted text is then passed to the reminder parser so the application can identify the task title, date, time, category, and location type. The user reviews the result before saving it.

### Personalized Reminder Prediction

Nabbihni uses an on-device TensorFlow Lite model to suggest a reminder category and, when available, an appropriate location type.

The prediction input includes:

- Day of the week
- Hour of the day
- Reminder-title keywords
- English and Arabic keyword features

The day and hour are encoded using sine and cosine values so the model correctly understands cyclical time relationships. For example, 11:00 PM is close to 12:00 AM.

The application also learns from the user's saved reminder history. When enough previous reminders are available, it combines the general model prediction with personalized scores based on recent habits and similar reminder times.

### Location-Aware Reminder Triggers

Nabbihni can detect useful places near the user's current GPS coordinates. It queries the OpenStreetMap Overpass API and maps nearby amenities and shops into supported application categories such as:

- Pharmacy
- Hospital
- Grocery store
- Bank
- Gym
- Restaurant
- Cafe
- School
- Store

The application calculates distances using the Haversine formula, removes duplicate places, and sorts results from closest to farthest. If an active reminder matches a nearby location type, the application can highlight the reminder and notify the user.

### Notifications and Snooze

The application schedules local notifications in the device timezone. Android reminders use alarm-clock scheduling mode for reliable delivery. Notifications include a snooze action that postpones the reminder by 15 minutes.

### Authentication and Cloud Sync

Firebase Authentication manages user login and registration. Cloud Firestore stores reminders, saved locations, and user-specific settings.

## Technology Stack

| Area | Technology |
| --- | --- |
| Mobile application | Flutter and Dart |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| Local notifications | `flutter_local_notifications` |
| Timezone support | `timezone` |
| Voice input | `speech_to_text` |
| Text-to-speech | `flutter_tts` |
| GPS location | `geolocator` |
| Maps | `google_maps_flutter` |
| Nearby-place lookup | OpenStreetMap Overpass API |
| On-device prediction | TensorFlow Lite using `tflite_flutter` |
| Image selection | `image_picker` |
| Handwriting extraction | Ollama-compatible vision API |
| HTTP requests | `http` |

## Firestore Structure

```text
users/{uid}
├── profile fields
├── locations/{locationId}
│   ├── name
│   ├── type
│   ├── lat
│   └── lng
└── reminders/{reminderId}
    ├── id
    ├── title
    ├── dateTime
    ├── category
    ├── locationType
    ├── lat
    ├── lng
    ├── address
    ├── priority
    ├── isCompleted
    ├── snoozeDurationMinutes
    └── createdAt
```

## Key Project Files

```text
lib/
├── main.dart                         # Application startup, Firebase, timezone, and notifications
├── shared/
│   ├── text_parser.dart              # Arabic and English reminder-text extraction
│   ├── habit_helper.dart             # TensorFlow Lite prediction and personalized blending
│   ├── ocr_helper.dart               # Handwriting image extraction through a vision endpoint
│   └── notifications.dart            # Scheduling, cancellation, and snooze actions
├── location/
│   └── osm_place_service.dart        # Nearby-place lookup and Haversine distance calculation
└── reminders/
    └── widgets/
        └── nearby_banner.dart         # Displays matching nearby reminders

assets/
└── models/                            # TensorFlow Lite model and model metadata

docs/
└── algorithms_documentation.md        # Detailed algorithm pseudocode and descriptions
```

## Data Processing Summary

### Reminder Text

The text parser:

1. Removes extra spaces.
2. Converts Eastern Arabic digits into Western digits.
3. Removes reminder prefixes such as `remind me`, `ذكرني`, and `نبهني`.
4. Extracts date and time expressions.
5. Detects category and location keywords.
6. Cleans the remaining task title.
7. Returns structured reminder data.

### Prediction Input

The prediction helper:

1. Converts the title to lowercase.
2. Extracts Arabic and English words.
3. Handles known synonyms.
4. Applies basic stemming to English words.
5. Converts title keywords into a binary multi-hot vector.
6. Encodes day and hour cyclically using sine and cosine.
7. Uses TensorFlow Lite for prediction.
8. Blends the global prediction with normalized user-history scores when enough history exists.

### Nearby Places

The location service:

1. Queries OpenStreetMap through the Overpass API.
2. Reads node coordinates or building-center coordinates.
3. Maps OSM tags into supported application place types.
4. Ignores unsupported or unusable results.
5. Calculates the distance in meters using the Haversine formula.
6. Removes duplicates and keeps the closest matching place.
7. Sorts results from nearest to farthest.

## Getting Started

### Prerequisites

Install the following before running the project:

- Flutter SDK compatible with Dart `^3.10.8`
- Android Studio or another Flutter-compatible development environment
- A Firebase project
- A physical device or emulator
- An Ollama-compatible API endpoint and model for handwriting extraction

### Install Dependencies

```bash
flutter pub get
```

### Firebase Setup

Configure Firebase for the application and ensure that the generated Firebase options and required platform configuration files are available.

Enable:

- Firebase Authentication
- Cloud Firestore

### OCR Configuration

Provide the OCR endpoint, API key, and model through Dart environment definitions. Do not commit real API keys to the repository.

```bash
flutter run \
  --dart-define=OLLAMA_BASE_URL=https://ollama.com/api \
  --dart-define=OLLAMA_API_KEY=YOUR_API_KEY \
  --dart-define=OLLAMA_MODEL=kimi-k2.6:cloud
```

### Platform Permissions

Ensure that the required Android or iOS permissions are configured for the features you plan to use:

- Notifications
- Exact alarms where required
- Location access
- Microphone access
- Camera and photo-library access
- Internet access

### Run the Application

```bash
flutter run
```

## Basic Workflow

1. Register or sign in.
2. Create a reminder manually, by voice, by typed natural-language text, or from a handwritten image.
3. Review the extracted reminder details.
4. Accept or modify the suggested category and location type.
5. Save the reminder.
6. Receive a scheduled alert or a nearby-place reminder when applicable.
7. Snooze, complete, edit, or delete the reminder as needed.

## Testing and Code Quality

Run the standard Flutter checks:

```bash
flutter analyze
flutter test
```

## Documentation

Detailed algorithm pseudocode and explanations are available in:

```text
docs/algorithms_documentation.md
```

## Security Notes

- Keep Firebase configuration appropriate for the target environment.
- Restrict Firestore access using user-scoped security rules.
- Never commit real OCR API keys or private credentials.
- Review platform permissions before deployment.

