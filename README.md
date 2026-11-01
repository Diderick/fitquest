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
- Create an account, find friends by username, and follow their community posts.
- Save changes offline and automatically sync your private account when connected.
- Count real phone sensor steps with permission; workout distance does not add estimated steps.
- Save a starting weight now and add the next weigh-in later.
- Preview quiet sponsor placements on Home and Community, with a free hide option.
- Create military-style, CrossFit-style or custom fitness challenges, set exercise targets, and log results offline.
- Share challenges with followers, join friends' tests, and compare per-exercise results in separate prescribed/scaled divisions.
- Share an activity as an image card or text through the phone's share sheet, or post its summary to the FitQuest feed. Notes and route sketches default off.
- Google/Facebook sign-in and account linking are prepared; activation needs [provider registration](apps/fitquest/SOCIAL_SETUP.md).
- Review opt-in social matches and follow selected people, or share invitation links with explicit follow-and-join actions. [Provider import setup](apps/fitquest/FRIENDS_SETUP.md) needs extra permissions.

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

Accounts, following and private offline sync connect to the FitQuest backend; see [backend setup](apps/fitquest/README.md) for deployment, configuration and limitations. Creating an account or first sign-in needs a connection. Existing sessions and guest mode work offline. Live clubs, competitions, coach services and connected wearables still need support. Community demo posts and leaderboard competitors are fictional. Ads are placeholders until provider and store IDs are supplied.

Workout, route, nutrition, post, goal, and plan data is stored locally using `shared_preferences` and is not encrypted. Avoid using this prototype for sensitive health data without secure storage, a privacy policy, and an appropriate backend.
