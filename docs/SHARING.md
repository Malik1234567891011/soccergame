# Getting PANNA onto friends' phones

Two separate things have to be true for friends to play each other:

1. **The server is on the internet.** Private rooms run on `Server/` (Vapor). It's ready to deploy (`Dockerfile` and `railway.json`).
2. **The app is on their phones.** Apple controls this; the options are below.

## 1. Deploy the server (one time, about 5 minutes)

```sh
railway login                      # opens the browser; needs Malik
cd ~/soccergame && railway init    # create project "panna-server"
railway volume add --mount-path /data   # keeps players/crews across deploys
railway up                         # builds the Dockerfile, deploys
railway domain                     # prints https://<name>.up.railway.app
```

Then set `OnlineClient.defaultURL` (device branch) to `wss://<that domain>/ws` and rebuild.

- Railway's free trial covers this. After that it costs about $5/month.
- Any Docker host works: Fly.io, Render, or a $4 VPS.

## 2. Install options

| Option | Cost | Friends need | Lasts | Notes |
|---|---|---|---|---|
| **Your Mac, cable** (free Apple ID) | free | to physically plug their iPhone into your Mac once, with Developer Mode on | **7 days**, then re-install | Max 3 apps per device. Fine for a weekend session, annoying long-term. |
| **AltStore / SideStore** | free | their own Apple ID and a one-time setup on their computer | 7 days, refreshes over Wi-Fi automatically | You send them the `.ipa`. Works worldwide without paying Apple. |
| **Ad Hoc build** (paid Apple Developer, $99/yr) | $99/yr | send you their device UDID once (the udid.tech site or Finder) | 1 year | Up to 100 devices. You share one link (install page or Diawi), they tap install. **No TestFlight, no review.** |
| **TestFlight** (same $99/yr) | $99/yr | the TestFlight app plus your invite link | 90 days per build | Up to 10,000 testers. The first external build needs a quick Beta Review (about a day). Easiest for lots of people. |
| **App Store** | $99/yr | nothing | permanent | Full review. Real-player likenesses and the names used in looks would be a review risk. |

**Recommendation.**

- Without paying: **AltStore/SideStore**. It's the only free way that doesn't need their phone at your Mac, and it auto-refreshes.
- If you'll pay the $99: **Ad Hoc** is the no-TestFlight answer. One link, and it works for a year.

The build is `Panna.app` signed with your team, exported as `.ipa`. I can script that once there's a team: `xcodebuild archive` + `-exportArchive` with method `ad-hoc` or `release-testing`.

Current state: device builds are signed with a free personal team (profile expires every 7 days). That is option 1.

## Playing a private room

1. Both open **Online**. One taps **CREATE ROOM**, then **INVITE**. This shares the code plus a `panna://join/CODE` link that opens the app straight into the room.
2. The other taps the link, or types the code and taps **JOIN**.
3. The host picks **VERSUS** (you each captain a side, AI teammates fill the rest) or **TEAM UP** (both of you against an AI crew), then **START**.
4. After the match you're both back in the same room: **START** again for a rematch.
5. Leaving the app for up to 90 s (for example to send the code) doesn't lose your place or your match seat. The app reconnects on its own.
