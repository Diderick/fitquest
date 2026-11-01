# FitQuest

FitQuest is a Flutter fitness-tracking prototype with Strava-inspired activity logging and training features.

## Features

- Manually log activities with duration, distance, and notes.
- Track more sports including swimming, rowing, yoga, HIIT, and tennis.
- Record foreground GPS routes for running, cycling, walking, and hiking.
- Review saved activities, weekly distance and time, longest recorded distance, and activity streaks.
- Set a weekly activity-time goal.
- Choose from local starter and goal-based training plans (weight loss, strength, and swim endurance) and log sessions.
- Plan meals and record calories in the Nutrition tab with a daily target and quick-add entries.
- Write local community posts, join sample challenges, and react to feed posts.
- Keep activity data, weekly goals, plans, nutrition entries, posts, challenge membership, and reactions on the device.

## Run

Install the Flutter SDK, then from this directory run:

```sh
flutter pub get
flutter run
```

## Build Android APK

```sh
flutter build apk --release
```

GPS recording asks for location permission when started and works only while the recorder screen is open. Android location permissions are included in the manifest. Route points are stored with the activity on the device.

## Prototype limitations

Activity storage can connect to the authenticated FitQuest backend; see [backend setup](apps/fitquest/README.md) for deployment and Flutter build configuration. Builds without API configuration retain local storage. Accounts, live clubs and challenges, coach services, connected wearables, and real social sharing still need backend support. Community demo posts and leaderboard competitors are fictional.

Workout, route, nutrition, post, goal, and plan data is stored locally using `shared_preferences` and is not encrypted. Avoid using this prototype for sensitive health data without secure storage, a privacy policy, and an appropriate backend.
