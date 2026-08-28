# Reminder System Algorithms Documentation

---

## 1. Personalized Reminder Suggestion Algorithm

### Pseudocode

```
FUNCTION predictPersonalized(day, hour, title):
    inputVector ← encode(day, hour, title)
    globalPrediction ← runTFLiteModel(inputVector)

    userHistory ← loadRemindersFromFirestore(currentUser)

    IF userHistory < 5 records:
        RETURN globalPrediction

    personalScores ← kernelDensityEstimate(userHistory, hour)

    IF userHistory between 5 and 10 records:
        alpha ← userHistory.count / 10
        blendedScores ← alpha × personalScores + (1 − alpha) × globalPrediction
    ELSE:
        blendedScores ← personalScores

    bestCategory ← highestScore(blendedScores.categories)
    bestLocation ← highestScore(globalPrediction.locations)

    RETURN Suggestion(bestCategory, bestLocation)
END FUNCTION
```

### Description

This algorithm figures out the best category and location to suggest when a user is creating a reminder.

It starts by encoding the reminder title and current time (day of week + hour) into a list of numbers — this becomes the input for a TFLite machine learning model. The model was trained to recognize patterns like "workout at 7am → personal category + gym location".

At the same time, the app loads all the reminders the user has previously saved from Firestore. It then runs a scoring process called **Kernel Density Estimation**, which basically asks: "How often did this user create this *type* of reminder around this *time of day*?" — and gives higher scores to categories that match the user's habits.

The interesting part is how these two signals (global model + personal history) are mixed:

- If the user has **fewer than 5 reminders**, the app just uses the AI model alone, since there isn't enough personal data yet.
- If the user has **between 5 and 10 reminders**, the app blends both together. The more history there is, the more weight goes to the user's personal data.
- If the user has **more than 10 reminders**, the app relies fully on their personal history.

This means the app gets smarter the more the user uses it — it gradually learns their habits and gives better suggestions over time.

---

## 2. Add Reminder Algorithm

### Pseudocode

```
FUNCTION addReminder():
    method ← user selects "Manual" OR "AI Input"

    IF method = Manual:
        details ← user fills form (title, date, time, location, category, priority)
        IF details are invalid:
            prompt user to correct → repeat
        END IF

    ELSE IF method = AI Input:
        inputType ← user selects Text, Voice, or Image

        IF inputType = Voice:
            language ← user selects English or Arabic
            rawContent ← transcribe audio to text (Speech-to-Text)
        ELSE IF inputType = Image:
            rawContent ← extract text from image (OCR)
        ELSE:
            rawContent ← read typed text directly
        END IF

        details ← NLP parser extracts (title, date, time, locationType, category)
                   from rawContent
    END IF

    details ← user reviews and optionally corrects details

    suggestion ← predictPersonalized(details)   // AI suggests category + location
    IF user accepts suggestion:
        details ← apply suggestion
    END IF

    save reminder to Firestore
    schedule notification if dateTime is set
END FUNCTION
```

### Description

This algorithm gives the user two different ways to create a reminder.

**Manual method:** The user opens a form and fills in the details themselves — title, date, time, location type, category, and priority. Everything is validated before saving.

**AI-assisted method:** The user provides natural input, and the app figures out the details automatically. There are three types of input:

- **Voice:** The user taps the microphone button and speaks. They first choose their language (English or Arabic), and the app transcribes what they say into text.
- **Image:** The user picks an image (like a photo of a note or a receipt), and the app uses OCR (Optical Character Recognition) to read the text from it.
- **Text:** The user types freely, like saying "remind me to buy milk tomorrow at 5pm".

After getting the raw text (from any of the three methods), a **Natural Language Parser** processes it. This parser understands both English and Arabic, and it scans the text for:
- Time references like "at 3pm", "الساعة 5 مساء", "noon"
- Date references like "tomorrow", "بكرة", "next Monday", "April 7"
- Location keywords like "gym", "pharmacy", "صيدلية", "مطعم"
- Category signals like "meeting → work", "doctor → personal"

Once the details are extracted (or manually entered), the user sees a review screen where they can correct anything. Then the **Personalized Suggestion Algorithm** runs in the background to recommend a category and location. The user can accept or ignore the suggestion before the reminder is finally saved to Firestore and a notification is scheduled.

---

## 3. Main Application Flow Algorithm

### Pseudocode

```
FUNCTION mainAppFlow():
    // ── On launch ────────────────────────────────────────
    user ← check Firebase Auth
    IF user is not logged in:
        show Login / Register screen
        wait for authentication
    END IF

    reminders ← load user's reminders from Firestore (live stream)
    nearbyPlaces ← get current GPS location → query OSM + personal locations
    display main screen with today's reminders sorted by time

    // ── Main interaction loop ────────────────────────────
    WHILE app is open:
        action ← user input OR incoming notification OR location update

        IF action = Add reminder:
            addReminder()
            refresh reminder list
            IF reminder was added via voice:
                read reminder title aloud (Text-to-Speech)
            END IF

        ELSE IF action = Tap reminder:
            show reminder details
            choice ← user selects Done, Edit, or Delete
            IF choice = Done:
                mark reminder as completed
            ELSE IF choice = Edit:
                open reminder in edit mode
                save changes + reschedule notification
            ELSE IF choice = Delete:
                remove reminder from Firestore
                cancel notification
            END IF
            refresh reminder list

        ELSE IF action = Notification fired:
            choice ← user selects Snooze or Dismiss
            IF choice = Snooze:
                reschedule notification (default: reminder's snooze duration in minutes)
                update reminder dateTime in Firestore
            ELSE IF choice = Dismiss:
                notification is dismissed
            END IF

        ELSE IF action = Location update:
            nearbyPlaces ← re-check GPS position
            nearbyMatches ← match active reminders against nearby place types
            IF nearbyMatches is not empty:
                show nearby reminder banner at top of screen
            END IF
        END IF

        refresh main screen
    END WHILE
END FUNCTION
```

### Description

When the app starts, it first checks if the user is logged in through Firebase Authentication. If not, it shows the login or register screen. Once authenticated, the app loads the user's reminders from Firestore as a **live stream** — meaning the screen updates automatically whenever any reminder changes, without needing to refresh manually.

At the same time, the app checks the device's GPS location and queries nearby places using **OpenStreetMap (OSM)**. It also checks the user's saved personal locations (like "home" or "work"). If any of these nearby places match the location type of an active reminder, a banner appears at the top of the screen to alert the user.

The app then enters a continuous loop, listening for different types of events:

**Adding a reminder:** The user can tap the "Add Reminder" button for manual or AI input, or tap the microphone icon for quick voice input. After saving, if the reminder was added by voice, the app reads the saved title out loud using Text-to-Speech (TTS) to confirm it.

**Tapping a reminder:** The user can mark it done, edit it, or delete it. Editing reopens the form with existing details pre-filled. Deleting also cancels any scheduled notification. Completing a reminder moves it to the "Completed" tab.

**Notifications:** When a reminder notification fires, the user can snooze it (the app reschedules the notification and updates the time in Firestore) or dismiss it.

**Location changes:** The app continuously monitors location. If the user gets close to a place that matches a reminder's location type — like walking near a pharmacy when they have a "pick up medicine" reminder — the app surfaces that reminder in a highlighted banner at the top.

Overall, this flow keeps the app responsive and in sync at all times, combining time-based and location-based triggers so the user never misses an important reminder.

---

## 4. Nearby Place Detection Algorithm (Haversine + OSM)

### Pseudocode

```
FUNCTION detectNearbyPlaces(userLat, userLng, radiusMeters):
    // ── Step 1: Query OpenStreetMap via Overpass API ──────
    query ← build Overpass query for amenities + shops within radiusMeters
    rawElements ← sendHttpRequest(overpassAPI, query)

    // ── Step 2: Map OSM tags to app place types ───────────
    places ← []
    FOR each element in rawElements:
        lat, lng ← extract coordinates (or center point for buildings)
        amenity ← element.tags["amenity"]
        shop    ← element.tags["shop"]
        type    ← mapToAppType(amenity OR shop)  // e.g. "pharmacy", "gym"
        IF type is recognized:
            dist ← haversineDistance(userLat, userLng, lat, lng)
            places.add(Place(type, name, lat, lng, dist))
        END IF
    END FOR

    // ── Step 3: Add user's saved personal locations ───────
    personalLocs ← loadPersonalLocations(currentUser)
    FOR each savedLocation in personalLocs:
        dist ← haversineDistance(userLat, userLng, savedLocation.lat, savedLocation.lng)
        IF dist ≤ radiusMeters:
            places.add(Place(savedLocation.type, savedLocation.name, dist))
        END IF
    END FOR

    // ── Step 4: Deduplicate and sort ──────────────────────
    seen ← {}
    FOR each place in places:
        key ← place.type + "|" + place.name
        IF key not in seen OR place.dist < seen[key].dist:
            seen[key] ← place
        END IF
    END FOR

    result ← seen.values sorted by distance (closest first)
    RETURN result
END FUNCTION

FUNCTION haversineDistance(lat1, lng1, lat2, lng2):
    R ← 6,371,000  // Earth radius in meters
    dLat ← toRadians(lat2 − lat1)
    dLng ← toRadians(lng2 − lng1)
    a ← sin(dLat/2)² + cos(lat1) × cos(lat2) × sin(dLng/2)²
    RETURN R × 2 × arcsin(√a)
END FUNCTION
```

### Description

This algorithm answers one question: "What useful places are near the user right now?" — so the app can alert them about relevant reminders.

It works in two parts running together:

**Part 1 — OpenStreetMap query:** The app sends a request to the free Overpass API (which serves OpenStreetMap data) asking for all amenities and shops within the given radius around the user's GPS coordinates. The raw results come back as a list of map elements with tags like `amenity=pharmacy` or `shop=supermarket`. The app maps each tag to one of its own place types (pharmacy, grocery, gym, bank, school, etc.). For large buildings like hospitals or malls that don't have a single point coordinate, the app uses the building's center point instead.

**Part 2 — Personal saved locations:** The user can save personal locations like "home", "gym", or "work" with their real GPS coordinates. These are stored in Firestore. The algorithm also checks these personal locations and includes them if they fall within the radius.

After collecting all places from both sources, the algorithm removes duplicates — if the same pharmacy appears twice (once from OSM, once as a personal location), only the closer entry is kept. Finally, all results are sorted from closest to farthest.

The distance between any two GPS points is calculated using the **Haversine formula**, which accounts for the curvature of the Earth and gives an accurate distance in meters.

Once the nearby place types are known, the app compares them against the user's active reminders. Any reminder whose location type matches a nearby place gets highlighted in a banner at the top of the screen.

---

## 5. OCR Image-to-Reminder Algorithm

### Pseudocode

```
FUNCTION recognizeTextFromImage(imagePath):
    // ── Step 1: Read and encode the image ────────────────
    imageBytes ← readFile(imagePath)
    base64Image ← base64Encode(imageBytes)

    // ── Step 2: Send to AI vision model ──────────────────
    request ← {
        model: "kimi-k2.6",
        messages: [{
            role: "user",
            content: systemPrompt,   // instructs model to read handwriting
            images: [base64Image]
        }],
        temperature: 0.1             // low temperature → more accurate, less creative
    }
    response ← sendHttpRequest(ollamaAPI, request, timeout=120s)

    // ── Step 3: Extract clean text ────────────────────────
    rawText ← response.message.content.trim()
    RETURN rawText

FUNCTION addReminderFromImage():
    imagePath ← user picks image from gallery or camera
    rawText   ← recognizeTextFromImage(imagePath)
    details   ← NLPParser.parse(rawText)   // same parser as text/voice input
    show details to user for review
    save reminder
END FUNCTION
```

### Description

This algorithm lets the user create a reminder by taking a photo of a handwritten note, a sticky note, or any written text — and the app reads it automatically.

When the user picks an image, the app reads the image file and converts it to a Base64 string (a text representation of the image data). This string is then sent to a cloud-based AI vision model called **Kimi K2**, which is specifically good at reading handwriting in both English and Arabic.

The model receives a system prompt that tells it:
- Read the handwriting carefully
- Ignore any crossed-out words
- Fix spelling mistakes caused by messy handwriting
- Do not translate — keep the original language as-is
- Return only the clean, final text with no extra explanation

The model uses a very low temperature setting (0.1), which means it stays focused and accurate rather than creative or paraphrasing.

Once the clean text is returned, it goes through the exact same **Natural Language Parser** used for typed and voice input. So if the note says "buy medicine Saturday at 4pm", the app automatically sets the title, date, time, and even suggests the location type (pharmacy) and category (personal).

---

## 6. Notification Scheduling Algorithm

### Pseudocode

```
FUNCTION scheduleNotification(id, title, scheduledDateTime):
    IF scheduledDateTime is in the past:
        skip silently
        RETURN
    END IF

    notification ← {
        id: id,
        title: title,
        body: "Tap to open Nabbihni",
        scheduledDate: scheduledDateTime (converted to device timezone),
        actions: [SnoozeButton("تأجيل ١٥ دقيقة")]
    }
    register as AlarmClock-mode notification   // fires even in Doze mode
END FUNCTION

FUNCTION snoozeNotification(id, title, minutes):
    cancelNotification(id)
    newTime ← now + minutes
    scheduleNotification(id, title, newTime)
END FUNCTION

FUNCTION onNotificationFired(response):
    IF user tapped Snooze button:
        snoozeTime ← now + 15 minutes
        reschedule notification at snoozeTime
    ELSE IF user tapped notification body:
        open app
    END IF
END FUNCTION

FUNCTION generateNotificationId(reminderId):
    RETURN abs(reminderId.hashCode) mod 2,000,000,000
END FUNCTION
```

### Description

This algorithm manages how and when reminder notifications are delivered to the user.

When a reminder is saved with a date and time, the app immediately schedules a local notification for that exact moment. It uses **AlarmClock mode** on Android, which means the notification will fire even if the phone is in battery-saving (Doze) mode — making it reliable for important reminders.

Each notification is identified by a unique integer ID that is derived from the reminder's Firestore document ID using a hash function. This ensures the app can always find and cancel the right notification when a reminder is edited or deleted.

Every notification includes a **Snooze button** labelled "تأجيل ١٥ دقيقة" (Postpone 15 minutes). When the user taps it, the current notification is cancelled and a new one is scheduled 15 minutes later. This works whether the app is open in the foreground or completely closed in the background.

The snooze duration can also be customized per reminder using the `snoozeDurationMinutes` field stored on the reminder itself, so different reminders can have different snooze lengths.

When a reminder is edited, its old notification is cancelled first, and a new one is scheduled with the updated time. When a reminder is deleted, its notification is cancelled entirely so the user is not disturbed by stale alerts.
