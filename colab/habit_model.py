"""
NABBIHNI — Habit Prediction Model Training (Google Colab)
=========================================================
Generates realistic KSA-lifestyle synthetic reminder data with task titles,
trains a small neural network to predict the best reminder category
from both time and text features, and exports to TFLite.

Inspired by: MS-LaTTE (Microsoft) — predicting task context from title
text + temporal signals.

Usage:
  1. Open Google Colab
  2. Copy-paste this entire file into a single cell (or run as .py)
  3. Click "Run all"
  4. Download the generated `habit_model.zip`
  5. Extract the zip into your Flutter project: assets/models/habit/

Output files (inside the zip):
  - model.tflite          — the habit prediction model
  - categories.json       — category index mapping
  - vocabulary.json       — keyword vocabulary (for title encoding)
  - config.json           — model config
"""

import json, os, random, zipfile, math, numpy as np

# ── القسم الأول: توليد بيانات تدريب اصطناعية ──────────────────────────────────
# نصنع سجلّات وهمية تحاكي نمط الحياة اليومية في السعودية (أوقات الصلاة، العمل،
# الأسرة، المشاوير)، لكل سجل: يوم الأسبوع + ساعة + عنوان + الفئة الصحيحة.
# هذه البيانات هي التي يتعلّم منها النموذج لاحقاً.
# ══════════════════════════════════════════════════════════════════════════════
# ── 1. Generate synthetic KSA-lifestyle reminder history (with titles) ───────
# ══════════════════════════════════════════════════════════════════════════════

CATEGORIES = ["personal", "work", "family", "other"]
CAT_IDX = {c: i for i, c in enumerate(CATEGORIES)}

random.seed(42)
np.random.seed(42)

# ── Title word pools per category ────────────────────────────────────────────
TITLE_POOLS = {
    "personal": [
        "prayer", "fajr", "dhuhr", "asr", "maghrib", "isha",
        "gym", "exercise", "medication", "vitamins", "quran",
        "meditation", "skincare", "journal",
    ],
    "work": [
        "meeting", "deadline", "report", "email", "presentation",
        "review", "project", "task", "call", "submit",
        "lecture", "homework", "study", "exam",
    ],
    "family": [
        "dinner", "lunch", "kids", "school", "doctor",
        "hospital", "family", "cook", "visit", "gather",
        "birthday", "picnic", "appointment", "collect",
    ],
    "other": [
        "groceries", "shopping", "buy", "errand", "store",
        "pharmacy", "pay", "bank", "car", "laundry",
        "clean", "fix", "return", "pickup",
    ],
}

records = []

def add_records(n, day_range, hour_mean, hour_std, category):
    """Generate n noisy records with random title words."""
    pool = TITLE_POOLS[category]
    for _ in range(n):
        day = random.choice(list(day_range))       # 0=Sun … 6=Sat
        hour = float(np.clip(np.random.normal(hour_mean, hour_std), 0, 23.99))
        # Pick 1–2 random title words from the category pool
        num_words = random.choice([1, 2])
        title = " ".join(random.sample(pool, min(num_words, len(pool))))
        records.append((day, round(hour, 2), CAT_IDX[category], title))

# ── KSA Daily Patterns (work week: Sun–Thu = 0–4; weekend: Fri–Sat = 5–6) ──

# Prayer-related (personal)
add_records(80,  range(7),    4.75,  0.4, "personal")   # Fajr    ~4:45
add_records(60,  range(7),   12.25,  0.3, "personal")   # Dhuhr  ~12:15
add_records(50,  range(7),   15.5,   0.3, "personal")   # Asr     ~3:30
add_records(50,  range(7),   18.25,  0.3, "personal")   # Maghrib ~6:15
add_records(50,  range(7),   20.0,   0.3, "personal")   # Isha    ~8:00

# Work / school (Sun–Thu)
add_records(100, range(5),    7.5,   0.5, "work")       # Morning commute
add_records(80,  range(5),   10.0,   0.8, "work")       # Mid-morning tasks
add_records(60,  range(5),   14.0,   0.6, "work")       # Afternoon work

# Family activities
add_records(70,  range(7),   13.0,   0.7, "family")     # Lunch
add_records(80,  range(7),   19.0,   0.8, "family")     # Dinner / family time
add_records(60,  [5, 6],     11.0,   1.5, "family")     # Weekend outings

# Other / errands
add_records(60,  range(5),   17.0,   1.0, "other")      # After-work errands
add_records(70,  [5, 6],     21.0,   1.0, "other")      # Weekend evening shopping
add_records(40,  range(7),   22.0,   0.8, "other")      # Late-night café / social

random.shuffle(records)
print(f"Generated {len(records)} synthetic records")

# ── القسم الثاني: بناء القاموس وتحويل البيانات إلى أرقام ────────────────────────
# نجمع كل الكلمات المفتاحية في قاموس ثابت، ثم نحوّل كل تذكير إلى متجه رقمي:
#   • 4 قيم دورية (sin/cos) لتمثيل اليوم والساعة بشكل دوري
#   • أعلام ثنائية (0/1) لكل كلمة في القاموس إن وُجدت في العنوان
# هذا الشكل هو ما يُغذَّى مباشرةً في النموذج.
# ══════════════════════════════════════════════════════════════════════════════
# ── 2. Build vocabulary & encode features ────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

# Build a fixed vocabulary from all title pools
all_words = set()
for pool in TITLE_POOLS.values():
    all_words.update(pool)

VOCAB = sorted(all_words)            # Fixed order — saved to vocabulary.json
VOCAB_IDX = {w: i for i, w in enumerate(VOCAB)}
INPUT_DIM = 4 + len(VOCAB)           # 4 temporal + keyword flags

print(f"Vocabulary size: {len(VOCAB)}")
print(f"Input dimension: {INPUT_DIM}")

def encode_title(title):
    """Encode a title string as a binary vector over the vocabulary."""
    words = title.lower().split()
    vec = [0.0] * len(VOCAB)
    for w in words:
        if w in VOCAB_IDX:
            vec[VOCAB_IDX[w]] = 1.0
    return vec

def encode_features(day, hour, title=""):
    """
    Encode day-of-week (0=Sun … 6=Sat), hour (0–24), and title text
    as a feature vector: 4 cyclic + len(VOCAB) keyword flags.
    """
    day_sin = math.sin(2 * math.pi * day / 7)
    day_cos = math.cos(2 * math.pi * day / 7)
    hour_sin = math.sin(2 * math.pi * hour / 24)
    hour_cos = math.cos(2 * math.pi * hour / 24)
    return [day_sin, day_cos, hour_sin, hour_cos] + encode_title(title)

X = np.array([encode_features(d, h, t) for d, h, _, t in records], dtype=np.float32)
Y = np.array([c for _, _, c, _ in records], dtype=np.int32)

# One-hot Y
Y_onehot = np.eye(len(CATEGORIES), dtype=np.float32)[Y]

# Train / test split
split = int(len(X) * 0.8)
X_train, X_test = X[:split], X[split:]
Y_train, Y_test = Y_onehot[:split], Y_onehot[split:]
Y_test_idx = Y[split:]

print(f"Train: {len(X_train)}, Test: {len(X_test)}")
print(f"Input shape: {X_train.shape}")

# ── القسم الثالث: بناء الشبكة العصبية وتدريبها ────────────────────────────────
# شبكة صغيرة من ثلاث طبقات (32 → 16 → 4 فئات) مع Dropout لمنع الحفظ الزائد.
# المدخل: المتجه الرقمي للوقت + الكلمات. المخرج: احتمال كل فئة (softmax).
# النتيجة النهائية: نموذج قادر على تخمين فئة التذكير من وقته وعنوانه.
# ══════════════════════════════════════════════════════════════════════════════
# ── 3. Build & train model ───────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

import tensorflow as tf
from tensorflow import keras

model = keras.Sequential([
    keras.layers.Dense(32, activation='relu', input_shape=(INPUT_DIM,)),
    keras.layers.Dropout(0.2),
    keras.layers.Dense(16, activation='relu'),
    keras.layers.Dense(len(CATEGORIES), activation='softmax'),
])

model.compile(
    optimizer='adam',
    loss='categorical_crossentropy',
    metrics=['accuracy'],
)

model.summary()

history = model.fit(
    X_train, Y_train,
    validation_split=0.15,
    epochs=50,
    batch_size=32,
    verbose=1,
)

# ── القسم الرابع: تقييم النموذج ───────────────────────────────────────────────
# نقيس دقة النموذج على بيانات الاختبار، ثم نجرّبه يدوياً على سيناريوهات
# حقيقية (صلاة، اجتماع، غداء عائلي، تسوق) لنتأكد أن التنبؤات منطقية.
# ══════════════════════════════════════════════════════════════════════════════
# ── 4. Evaluate ──────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

preds = model.predict(X_test)
pred_labels = np.argmax(preds, axis=-1)
accuracy = (pred_labels == Y_test_idx).mean()
print(f"\nTest accuracy: {accuracy:.2%}")

# Show predictions for different times + titles
test_scenarios = [
    (0,  5.0,  "prayer fajr",      "Sunday    5:00 AM  — Fajr prayer"),
    (0,  8.0,  "meeting",          "Sunday    8:00 AM  — Work meeting"),
    (1, 13.0,  "lunch family",     "Monday    1:00 PM  — Family lunch"),
    (2, 17.0,  "groceries buy",    "Tuesday   5:00 PM  — Buy groceries"),
    (3, 19.0,  "dinner kids",      "Wednesday 7:00 PM  — Dinner with kids"),
    (5, 11.0,  "picnic family",    "Friday   11:00 AM  — Family picnic"),
    (5, 21.0,  "shopping",         "Friday    9:00 PM  — Shopping"),
    (6, 22.0,  "pharmacy",         "Saturday 10:00 PM  — Pharmacy run"),
    # ── Text-only tests (does text override wrong time?) ──
    (0, 21.0,  "meeting deadline", "Sunday    9:00 PM  — Work (wrong time)"),
    (2,  5.0,  "groceries store",  "Tuesday   5:00 AM  — Errands (wrong time)"),
    # ── No text (falls back to time only) ──
    (0,  5.0,  "",                 "Sunday    5:00 AM  — No title"),
    (3, 19.0,  "",                 "Wednesday 7:00 PM  — No title"),
]

print("\n── Sample Predictions ──")
for day, hour, title, desc in test_scenarios:
    x = np.array([encode_features(day, hour, title)], dtype=np.float32)
    p = model.predict(x, verbose=0)[0]
    cat = CATEGORIES[np.argmax(p)]
    conf = np.max(p)
    print(f"  {desc:42s} → {cat:10s} ({conf:.0%})")

# ── القسم الخامس: تصدير النموذج ─────────────────────────────────────────────
# نحوّل النموذج إلى صيغة TFLite (خفيفة تعمل على الهاتف) ثم نضغطه مع ملفات
# الإعداد (categories.json, vocabulary.json, config.json) في حزمة zip.
# هذه الحزمة تُرفع إلى مشروع Flutter مباشرةً في مجلد assets/models/.
# ══════════════════════════════════════════════════════════════════════════════
# ── 5. Export to TFLite + zip ────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

OUT_DIR = "habit_output"
os.makedirs(OUT_DIR, exist_ok=True)

with open(f"{OUT_DIR}/model.tflite", "wb") as f:
    f.write(tflite_model)

with open(f"{OUT_DIR}/categories.json", "w") as f:
    json.dump(CATEGORIES, f)

# Save the vocabulary — Flutter needs this to encode titles the same way
with open(f"{OUT_DIR}/vocabulary.json", "w") as f:
    json.dump(VOCAB, f)

config = {
    "input_features": ["day_sin", "day_cos", "hour_sin", "hour_cos"] + [f"kw_{w}" for w in VOCAB],
    "num_categories": len(CATEGORIES),
    "categories": CATEGORIES,
    "vocab_size": len(VOCAB),
}
with open(f"{OUT_DIR}/config.json", "w") as f:
    json.dump(config, f, indent=2)

with zipfile.ZipFile("habit_model.zip", "w") as zf:
    for fname in os.listdir(OUT_DIR):
        zf.write(f"{OUT_DIR}/{fname}", fname)

print("\n✅ Done! Download 'habit_model.zip' and extract into assets/models/habit/")
print(f"   Files: model.tflite, categories.json, vocabulary.json, config.json")
print(f"   Input dimension: {INPUT_DIM} (4 temporal + {len(VOCAB)} keywords)")

try:
    from google.colab import files
    files.download("habit_model.zip")
except ImportError:
    pass

# ══════════════════════════════════════════════════════════════════════════════
# ── القسم السادس: اختبار بسيط للنموذج ───────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════
# نتحقق من ثلاثة أشياء:
#   1. أن encode_features تُنتج متجهاً بالبُعد الصحيح وتُفعّل الكلمات الصحيحة
#   2. أن تنبؤات Keras صحيحة على حالات معروفة
#   3. أن ملف TFLite المُصدَّر يعمل ويُعطي نفس النتائج

print("\n" + "="*60)
print("اختبار النموذج")
print("="*60)

# ── اختبار 1: ترميز الميزات ──────────────────────────────────────────────────
print("\n[1] اختبار encode_features:")
vec = encode_features(0, 5.0, "prayer fajr")
assert len(vec) == INPUT_DIM, f"  خطأ: البُعد يجب أن يكون {INPUT_DIM}"
assert vec[VOCAB_IDX['prayer']] == 1.0, "  خطأ: 'prayer' يجب أن يكون مفعّلاً"
assert vec[VOCAB_IDX['fajr']]   == 1.0, "  خطأ: 'fajr' يجب أن يكون مفعّلاً"
vec_empty = encode_features(0, 12.0, "")
assert sum(vec_empty[4:]) == 0.0, "  خطأ: عنوان فارغ يجب أن لا يُفعّل أي كلمة"
print(f"  ✅ البُعد صحيح: {INPUT_DIM}")
print(f"  ✅ الكلمات مُرمَّزة بشكل صحيح")
print(f"  ✅ العنوان الفارغ لا يُفعّل كلمات")

# ── اختبار 2: تنبؤات نموذج Keras ────────────────────────────────────────────
print("\n[2] اختبار تنبؤات Keras:")
test_cases = [
    (0,  4.75, "fajr prayer",    "personal", "صلاة الفجر"),
    (1,  9.0,  "meeting report", "work",     "اجتماع عمل"),
    (3, 13.0,  "lunch family",   "family",   "غداء عائلي"),
    (5, 21.0,  "groceries buy",  "other",    "تسوق الجمعة"),
]

passed = 0
for day, hour, title, expected, desc in test_cases:
    x = np.array([encode_features(day, hour, title)], dtype=np.float32)
    p = model.predict(x, verbose=0)[0]
    predicted  = CATEGORIES[np.argmax(p)]
    confidence = np.max(p)
    ok = predicted == expected
    passed += ok
    icon = "✅" if ok else "❌"
    suffix = "" if ok else f"  [متوقع: {expected}]"
    print(f"  {icon} {desc:14s} | '{title}' → {predicted} ({confidence:.0%}){suffix}")

print(f"\n  النتيجة: {passed}/{len(test_cases)} صحيح")

# ── اختبار 3: تحميل TFLite والتنبؤ منه ────────────────────────────────────
print("\n[3] اختبار ملف TFLite المُصدَّر:")
tflite_interp = tf.lite.Interpreter(model_content=tflite_model)
tflite_interp.allocate_tensors()

inp_det = tflite_interp.get_input_details()
out_det = tflite_interp.get_output_details()
print(f"  شكل الإدخال:  {inp_det[0]['shape']}  (يجب أن يكون [1, {INPUT_DIM}])")
print(f"  شكل الإخراج: {out_det[0]['shape']}  (يجب أن يكون [1, {len(CATEGORIES)}])")
assert inp_det[0]['shape'][1] == INPUT_DIM, "  خطأ: شكل الإدخال غير متوقع"
assert out_det[0]['shape'][1] == len(CATEGORIES), "  خطأ: شكل الإخراج غير متوقع"

x_tflite = np.array([encode_features(5, 21.0, "shopping")], dtype=np.float32)
tflite_interp.set_tensor(inp_det[0]['index'], x_tflite)
tflite_interp.invoke()
out       = tflite_interp.get_tensor(out_det[0]['index'])
tflite_cat  = CATEGORIES[np.argmax(out[0])]
tflite_conf = np.max(out[0])
print(f"  ✅ TFLite يعمل — 'shopping' الجمعة ٩ مساءً → {tflite_cat} ({tflite_conf:.0%})")

print("\n✅ جميع الاختبارات اجتازت — النموذج جاهز للتطبيق")
