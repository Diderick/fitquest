# Profile and dated nutrition

## Profile

Profile → Add/Change photo supports gallery selection and mobile camera capture.
Photos are re-rendered as centered 256×256 PNG thumbnails, excluding original
EXIF/location metadata. The image bytes are saved in the account's offline cache,
not as a temporary picker file path, and queue for private account sync. Photos
can be changed or removed. Android picker recovery restores interrupted captures
only to the account that initiated them. iOS photo-library/camera usage text is
configured; camera/gallery permissions still need physical-device QA.

Gender offers Not set, Male, Female and Other. It is an optional profile field,
not an input that silently changes calorie targets. Both gender and photo remain
private and are excluded from friend suggestions, community posts and external
activity sharing. New sync keys are `profile_gender` and `profile_photo_v1`.
The backend validates the enum and bounds the PNG thumbnail payload. Offline
storage uses the existing unencrypted per-account cache; session tokens remain
in OS secure storage.

## Daily food and drink diary

Open Train → Nutrition. The displayed day defaults to the current local date.
Use the date picker, previous/next controls or Today to change the viewed day.
Log food / Log drink opens an editor for name, portion, whole-portion calories,
date and time. New entries default to the selected diary date and current local
time; opening the diary starts on today. Zero-calorie entries are allowed for
items such as water. Each entry can be edited, moved to another date, or deleted.
Recorded date/time are local calendar values and remain as entered across sync.

```text
daily allowance = base goal for that date + estimated activity calories for that date
remaining       = daily allowance - food and drink calories for that date
```

Only logged workouts on the selected local date contribute credit. Prior/future
days' workouts are excluded, and steps are not credited again. The app currently
uses its existing rough workout estimate (`Workout.kcal = minutes × 6`), not
measured total energy expenditure or a personalized nutrition recommendation.
The UI shows base goal, activity credit, adjusted allowance, consumed calories
and remaining/over allowance separately.

Base goals are stored by date (`nutrition_goal.YYYY-MM-DD`), with the existing
`nutrition_goal_kcal` as a fallback (otherwise 2200). Recording the first entry on
a date snapshots its base goal. Changing a date's goal does not rewrite other
dates' goals. Entries use independent `nutrition_entry.ID` records so offline
adds on different devices do not overwrite an entire meal list. Edits/deletes use
the existing version checks and durable outbox.

## Old data

The old `nutrition_entries_v1` list had neither dates nor times. Those records
are preserved as deterministic undated entries under Older entries need a date.
They are excluded from dated totals until the user assigns a date/time; no date
is fabricated. Editing creates a new per-entry record using the same legacy ID.
Deletion records a tombstone, including for an item that previously existed only
in the legacy list, so it does not reappear after restart or sync.

## Checks

```sh
flutter test test/nutrition_test.dart test/nutrition_ui_test.dart test/profile_identity_test.dart
node --test apps/fitquest/profile_nutrition.test.mjs
flutter analyze
```

Tests cover selected-day totals/credit, zero-calorie drinks, default timestamps,
legacy preservation, edit/delete/restart behavior, thumbnail sizing/persistence,
gender selection and server-side validation. The live smoke test also verifies
private profile/nutrition sync and account isolation using temporary accounts.
