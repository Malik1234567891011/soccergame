# Retention and Monetization Research for STREET XI

What keeps players coming back to top mobile games, written as design rules for STREET XI (a 3v3 arcade soccer game with one controlled footballer and 2–3 minute matches). Figures marked *(est.)* are our own tuning proposals. All other figures come from the cited sources.

---

## 1. Benchmarks to aim for

- **Retention.** GameAnalytics' 2025 data covers 11.6k apps. The median game keeps about 22% of players on D1, under 4% on D7 and about 0.7% on D30. The top quartile keeps 26–28% on D1, and the top 1% keeps 64–68% on D1 and 13–15% on D30 ([GameAnalytics 2025](https://www.gameanalytics.com/reports/2025-mobile-gaming-benchmarks), [Segwise](https://segwise.ai/blog/mobile-gaming-app-user-retention-strategies)). Arcade games do best of any genre on D1 but lose players over the long term ([Mistplay/MAF list](https://maf.ad/en/blog/mobile-game-retention-benchmarks/)). **Targets for STREET XI: D1 ≥ 40%, D7 ≥ 15%, D30 ≥ 6%.** The arcade genre puts D1 within reach. D7 and D30 depend entirely on the meta systems.
- **Sessions.** The median mobile session is 5–6 minutes, and top-quartile games reach 8–9 minutes with 5.3–5.7 sessions a day ([Udonis](https://www.blog.udonis.co/mobile-marketing/mobile-games/session-length), [Segwise stats](https://segwise.ai/blog/mobile-gaming-statistics)). **Design for a 3-match session of about 9 minutes, including menus.** A 2.5-minute match is the right length.
- **Tutorial drop-off.** DeltaDNA found that about 20% of players never finish the first tutorial quest ([Udonis FTUE](https://www.blog.udonis.co/mobile-marketing/mobile-games/first-time-user-experience)). Every screen shown before the first goal loses players.

## 2. First session (FTUE)

**Rules**
1. **Kick-off before any menu.** The first match should start within 10 seconds of launch *(est.)*. Put the player straight onto the pitch against weak bots, with no account setup or avatar creator first. Customisation comes after the first win, when the player cares about the character.
2. **Script the first win and the first highlight moment.** Guarantee a goal in the first 30 seconds and a win in match 1. Fill the Hype meter during match 1 so Flow state fires before the final whistle. The first session should show off the game's signature feature.
3. **Introduce one system per match.** Supersonic and GameAnalytics both advise rolling out mechanics gradually ([Supersonic](https://supersonic.com/learn/blog/optimizing-ftue/), [GameAnalytics FTUE tips](https://www.gameanalytics.com/blog/tips-for-a-great-first-time-user-experience-ftue-in-f2p-games)). Suggested order: M1 controls and Flow → reward screen → M2 first Scout Pack (rigged to contain a Legacy card) → M3 equip the card → the Road opens → M5 daily quests unlock.
4. **Log funnel events locally from day one** (`ftue_step_n`, `match_n_complete`) so drop-off points can be measured once analytics are added.
5. **Aim for a first session of about 10–15 minutes** that ends on an unfinished goal the player can see, such as "2 wins to next Road reward" or a chest that unlocks tomorrow.

## 3. Reward schedules and the core loop

- **Reward every match, win or lose, and give winners roughly 3× what losers get.** A loss that pays zero invites uninstalls. A loss that pays some Coins plus progress toward the daily win count keeps players queueing. Clash Royale dropped its chest-slot and timer system in 2025. Supercell's reasons were that chests delayed the payoff of winning, that the 4 slots made further wins feel worthless, and that the system forced logins that drove away casual players ([RoyaleAPI](https://royaleapi.com/blog/rip-chests-2025-q1-update?lang=en)). **Do not build timed chest slots.**
- **Mix fixed and variable rewards.** Fixed rewards (Coins, XP) show steady progress, and variable rewards (drops that can upgrade) create excitement. Brawl Stars caps daily variable rewards: Starr Drops come after win 1, win 4 and win 8, for a maximum of 3 a day ([Starr Drops wiki](https://brawlstars.fandom.com/wiki/Starr_Drops)). The widening gaps pace the session. Once the cap is reached, the player has a reason to stop, which prevents burnout.
- **Show the upgrade chances in the reveal.** Starr Drops open at 50% Rare, 28% Super Rare, 15% Epic, 5% Mythic and 2% Legendary, and each drop can upgrade a tier or more before revealing its contents ([Supercell odds](https://support.supercell.com/brawl-stars/en/articles/starr-drops-chances-2.html), [theriagames](https://theriagames.com/guide/brawl-stars-starr-drops/)). Clash Royale's Lucky Drops take 3 taps, and each tap can upgrade the rarity ([Game Rant](https://gamerant.com/clash-royale-how-do-lucky-drops-work/)). The player gets to take part in each step, and each upgrade feels like a small win. Starr Drop rarity is decided when the drop is awarded, and the taps are only a reveal ([Brawl.tube](https://brawl.tube/brawl-stars-starr-drops-complete-guide/)). Do the same.
- **Why near-misses work.** In Clark et al. (Neuron, 2009), near-misses felt worse than clear misses but increased the desire to play again. The brain's reward circuitry responded to them as it does to wins, but only when the player felt they had some control ([PubMed](https://pubmed.ncbi.nlm.nih.gov/19217383/)). Apply this where the player really did have control, such as a shot off the post or a Road bar at 9/10. **Do not fake near-misses in paid packs** (for example, a Legendary glow that fades). It is manipulative, and it tends to draw regulator attention.

## 4. Streaks and daily habit

- **Pokémon GO's daily bonus.** The first catch of each day gives 500 XP and 600 Stardust, and 7 days in a row gives 2,500 XP and 3,000 Stardust. Missing a day resets the streak ([Pokémon GO Hub](https://pokemongohub.net/post/wiki/daily-weekly-streaks/), [Forbes](https://www.forbes.com/sites/davidthier/2016/11/08/first-catch-of-the-day-pokestop-how-daily-bonuses-and-streaks-work-in-pokemon-go/)). **Rule: the first win of the day pays about 5× a normal win, and day 7 pays about 5× a daily bonus.**
- **Royal Match win streak.** Consecutive wins give pre-boosted boards, and a 72-hour window stops streaks from running forever ([Naavik](https://naavik.co/deep-dives/royal-match/), [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey)). Players will play again to protect a streak they can see, which is loss aversion at work. **Rule: show the in-match win streak as a flame by the player's name, with bonus trophies that climb (+1, +2, +3, capped). A loss resets the streak but never takes away rewards already paid.**
- **Streak repair.** Allow one free "streak freeze" a week *(est.)*. Punishing streaks drive away casual players, which was part of Supercell's reasoning in the Clash Royale changes above.
- **Login calendar.** Use a 7-day cycle that pauses instead of resetting when a day is missed (a gentler version of Pokémon GO). Days 1–6 give small rewards, and day 7 gives a Scout Pack. Add a 28-day monthly track with an exclusive cosmetic at the end.

## 5. Trophy Road and visible progression

- **Clash Royale Trophy Road.** Once a player reaches an arena, trophy gates stop them from falling below it ([Supercell support](https://support.clashroyale.com/hc/en-us/articles/49484914645915-Trophy-Road), [wiki](https://clashroyale.fandom.com/wiki/Trophies)). A trophy count that only ever rises is the most reliable progress bar in mobile games.
- **Brawl Stars at low trophies.** A win gains more trophies than a loss costs, and players only start losing more than they win at about 1,100 trophies ([Brawl Stars trophies wiki](https://brawlstars.fandom.com/wiki/Trophies), [Sportskeeda](https://sportskeeda.com/mobile-games/brawl-stars-new-trophy-system-explained)).
- **STREET XI Road.** Plan 60 nodes for v1, with a reward about every 2–4 wins early on and every 6–8 wins later *(est.)*. Make every 5th node a large reward: a new pitch, a new Prospect or a guaranteed Epic pack. Put permanent floors at each district (every 300 trophies). Below 1,000 trophies, a win gives +8 and a loss costs −3. After that, a win gives +8 and a loss costs −6 *(est.)*.

## 6. Ranked ladder

- **Rocket League** has 8 ranks with 3 tiers each and 4 visible divisions per tier. It has no promotion series, gives a short demotion buffer after promotion, and uses 10 placement matches with a soft reset each season ([Epic support](https://www.epicgames.com/help/c-202300000001622/c-Trending_0/what-are-rocket-league-competitive-ranks-a202300000013438), [esportstalk](https://www.esportstalk.com/blog/rocket-league-ranks-ranking-up-guide/)). The divisions give players a small visible step every few games.
- **Brawl Stars Ranked** uses a visible Elo. Each Bronze or Silver tier costs 250 Elo, Gold to Mythic costs 500, Legendary 750 and Masters 1,000. Gold and Diamond have floors, so a player cannot drop out of the rank for the rest of the season. Win streaks don't count in Ranked, and wins get a +10% boost until the player gets back to last season's peak ([Brawl Stars Ranked wiki](https://brawlstars.fandom.com/wiki/Ranked)).
- **STREET XI ladder:** Rookie, Amateur, Semi-Pro, Pro, Elite, World Class, Icon. That is 7 ranks, the first 6 with 3 divisions, for 19 steps. Each division is worth 100 RP. A win gives +25 RP, plus 5 per streak step up to +10. A loss costs −20 RP. Add a 3-loss shield after each promotion, and floors at Semi-Pro and Elite. Each season, soft-reset players 2 divisions down and give a catch-up boost of +50% RP on wins until they are back where they were *(est.)*. When the game goes offline-to-online, reuse the same ladder data model with bot MMR.

## 7. Gacha: pity, banners, duplicates

- **HoYoverse model.** Genshin's 5★ rate is 0.6% per pull until pull 73. From pull 74 it rises by about 6% per pull ("soft pity", 0.6% → 6.6%), and pull 90 guarantees a 5★ ("hard pity"). Each 5★ has a 50/50 chance of being the featured one, and losing guarantees that the next one is featured. Capturing Radiance lifts the effective featured rate to about 55% ([Game8](https://game8.co/games/Genshin-Impact/archives/305937), [PlayAware](https://playaware.gg/guides/genshin-pity)). Honkai: Star Rail's Light Cone banner has 80-pull hard pity, a 75/25 featured split, and a pity count that carries over between banners ([HoYoverse support](https://support.hoyoverse.com/hc/en-us/articles/50913708153625-How-does-the-guarantee-system-work-for-the-Light-Cone-Event-Warp-and-does-my-pity-carry-over)).
- **Step-ups.** Captain Tsubasa Dream Team guarantees an SSR at step 3 and a *new* SSR at step 5, at 250 Dreamballs per 10-pull ([Pocket Gamer](https://www.pocketgamer.com/captain-tsubasa-dream-team/5th-anniv-celeb/)). The first 10-pull is discounted to 30 paid Dreamballs, once only.
- **Box draws with no repeats.** In eFootball's Epic boxes, a player drawn from the box is removed, so 150 spins guarantees all 3 Epics ([eFootballLAB](https://efootballlab.com/blog/how-to-get-epic-players-in-efootball.html)). The cost of the worst case is known up front and players see it as fair.
- **Duplicates.** Brawl Stars turns duplicates into a second currency called Credits: Epic 800, Mythic 1,500, Legendary 3,200 ([Credits wiki](https://brawlstars.fandom.com/wiki/Credits)). Mini Football shows how many copies of each card the player owns and uses them to level the card up ([Pocket Tactics](https://www.pockettactics.com/mini-football/miniclip)). **Rule: a duplicate is never worthless.** It either levels up a card's *mastery*, which should add cosmetic flair and small side-grades, or converts to Shards that buy a chosen card.
- **Disclosure.** Apple 3.1.1 requires that odds for paid random items are shown before purchase ([Fenwick](https://www.fenwick.com/insights/publications/apple-now-requires-disclosure-of-loot-box-odds)). Mini Football markets its visible drop rates as a selling point ([Miniclip](https://support.miniclip.com/hc/en-us/articles/39139542954897-Mini-Football-v4-0)). Also show the pity counter on screen ("Legendary guaranteed in 23").

## 8. Pack reveal sequence

FIFA/FC walkouts began in FIFA 17. The walkout gives clues in order: a tunnel, then position, nation, league and club shown on LED screens, before the card appears through smoke ([FUT walkout guide](https://fifauteam.com/fc-27-walkout-player/), [GAMES.GG](https://games.gg/ea-sports-fc-26/guides/ea-fc-26-walkout-animation/)). Players learn to read these signals, which turns waiting into active reading of the clues. Rules for STREET XI:
1. **Rarity signal first (0.5–1 s).** The pack's colour and sound give away the highest rarity inside: blue for Common, purple for Epic, gold for Legendary. Show it before the pack opens so anticipation builds.
2. **Clues in stages for Legendary Legacy cards (5–7 s).** Show era, then position, then nation flag, then a silhouette of the signature move, then the card. The player should be able to guess who it is just before the reveal.
3. **Tap to advance.** Each stage waits for a tap, and holding the screen speeds it up. After the first 20 packs, offer a Skip button that jumps straight to the summary.
4. **Scale the payoff to the rarity.** A Common flips in 0.3 s. An Epic gets a particle burst and haptic feedback. A Legendary gets a slow-motion walkout, a pose, a crowd roar and a camera orbit.
5. **Finish on "Equip now" or "Try it in a match".** Getting from reward to use in one tap sends the player straight into another match.

## 9. Post-match screen

- Order the screens: result → XP bar filling with a sound for each tick → Road or rank bar moving with the new amount → rewards → **"Play again" as the primary button, placed where the thumb rests**. Clash Royale's reason for removing chest timers was that anything delaying the celebration of a win weakens it ([RoyaleAPI](https://royaleapi.com/blog/rip-chests-2025-q1-update?lang=en)).
- Always show the **next goal and how far away it is**: "1 win to Daily Drop #2", "40 RP to Semi-Pro II", "Streak ×3: next win +3".
- After a loss, show a highlight the player can be proud of, such as their best Flow moment or a stat of the match, next to the rewards they still earned. Loss aversion also works in the game's favour here: a "Protect your streak shield: 1 left" nudge gets players to play again.

## 10. Game feel

The "Juice It or Lose It" talk (Jonasson and Purho, 2012) and Vlambeer's "Art of Screenshake" describe the standard techniques: hit-stop, screen shake, particles, squash-and-stretch, and layered sound ([Game Developer](https://www.gamedeveloper.com/design/squeezing-more-juice-out-of-your-game-design-)). For STREET XI:
- On a shot, freeze time for 60–90 ms *(est.)*. On a goal, run slow motion at 0.3× for 1 s, shake the camera and make the net ripple.
- Use strong UIImpactFeedbackGenerator haptics on shots, tackles and goals, and a UINotificationFeedbackGenerator success pulse when Flow triggers.
- Every coin and XP tick after the match needs its own sound, and the pitch of the sound should rise as the bar fills.
- Input must feel instant: make the player move the frame after the touch, and show the result of every action on screen.

## 11. Battle pass, cosmetics, fair monetization

- Fortnite's Battle Pass pays back more premium currency than it costs, so a player who finishes it can buy the next one ([Deconstructing Fortnite](https://mobilefreetoplay.com/deconstructing-fortnite-a-deeper-look-at-the-battle-pass/), [esports.gg](https://esports.gg/news/fortnite/how-fortnite-battle-pass-works/)). Brawl Pass pays back about half its price in Gems ([Naavik Brawl Stars](https://naavik.co/deep-dives/brawl-stars-deconstruction/)). A paid pass that pays for itself keeps a paying player for years.
- **Staying fair.** Players see Brawl Stars as fair when the core is skill-based and resent it when it drifts toward power levels ([Naavik](https://naavik.co/deep-dives/brawl-stars-deconstruction/), [SportsDunia](https://www.sportsdunia.com/gaming/brawl-stars-f2p-progression-guide)). Royal Match's 2.0 update took the potions out of streaks so every player moves through the meta at the same pace ([Naavik digest](https://naavik.co/digest/royal-match-finding-success-through-iteration/)). **Rule: money can buy speed, choice and style, but never ranked stat advantage.** Legacy cards are *sidegrades*: different techniques with the same power budget. Ranked matches normalise stats. Only the offline career mode allows stat growth.
- Monopoly Go's sticker albums last about 2 months, which makes collection a long-term goal, while events come in short bursts of hours to days ([Balancy deconstruct](https://balancy.co/blog/2023/09/01/monopoly-go-core-game-play-and-liveops-deconstruct-by-ashwin-sundar-reliance-games-2/)). STREET XI can do the same with a season album of Legacy cards.
- Score! Hero reviews complain about heavy ads and progress walls, while Soccer Super Star wins players with gentler progression and offline play ([Marlvel intel](https://marlvel.ai/intel-report/games/com-firsttouch-story)). **Use no forced interstitial ads, and make everything playable offline.**

---

## Concrete recommendations for STREET XI v1 (offline, bots)

1. **Launch straight into a match.** The first match starts within 10 s. The player gets a guaranteed goal before 0:30, a guaranteed win in M1, and Flow fires in M1.
2. **FTUE unlock order:** M1 controls and Flow, M2 a Scout Pack rigged to hold a Legacy card, M3 equip the card, M4 the Road, M5 daily quests. The avatar creator comes after the first win.
3. **Bot difficulty curve.** Matches 1–3: bots at 40% skill. Matches 4–10: 55%. After that, adjust within ±10% to keep the win rate at 55–60% *(est.)*. After 2 losses in a row, drop difficulty one step without telling the player.
4. **Match rewards.** A win gives 100 Coins and 50 XP. A draw gives 50 Coins and 30 XP. A loss gives 30 Coins and 20 XP (about 3:1 between win and loss). The Man of the Match gets +20%.
5. **First win of the day ×5** (500 Coins and a Standard Scout Pack).
6. **Daily Drops** after wins 1, 3 and 6, capped at 3 a day. Drops start at 50% Common, 30% Rare, 14% Epic, 5% Legendary and 1% Mythic, and can upgrade over 3 taps. Rarity is fixed when the drop is awarded.
7. **Win-streak flame** with bonus trophies of +1/+2/+3/+4/+5, capped at 5. A loss resets it and nothing is taken back. One free Streak Shield a week.
8. **7-day login calendar** that pauses (never resets) when a day is missed. Day 7 gives a Premium Scout Pack. Add a 28-day monthly track ending in an exclusive kit.
9. **Street Road:** 60 nodes with rewards every 2–4 wins early and every 6–8 later. Every 5th node is a big reward. District floors every 300 trophies.
10. **Trophy maths:** a win gives +8. A loss costs −3 below 1,000 trophies and −6 above it. Streak bonus trophies are added on top.
11. **Ranked ladder:** 7 ranks with 3 divisions each (Icon has no divisions), 100 RP per division. A win gives +25 RP (up to +10 more from streaks) and a loss costs −20. Add a 3-loss shield after each promotion and floors at Semi-Pro and Elite. Unlock Ranked at 300 trophies.
12. **Seasons of 6 weeks** *(est.)*. Soft-reset 2 divisions and give +50% RP on wins until the player is back to last season's peak.
13. **Scout Pack pity:** 0.8% Legendary base rate, soft pity from pull 50 (+6% per pull), hard pity at 70 *(est.)*. The pity count carries over between banners and is always shown on screen.
14. **Featured banner at 75/25, not 50/50.** Losing the 25% guarantees the next one is featured. The player gets a smaller share of bad outcomes than in Genshin.
15. **Epic guaranteed in every 10-pull.** Step-up: step 3 guarantees an Epic+, step 5 guarantees a *new* Legendary.
16. **Duplicates become Mastery and Shards.** Copies 2 to 5 of a Legacy card each raise its Mastery star, which adds visual flair to the move and a small cooldown side-grade. Further copies convert to Shards: Rare 20, Epic 100, Legendary 400. 1,200 Shards buy any Legendary on the current banner.
17. **Prospect box draw.** Each event box holds a fixed set with no repeats, so the worst-case cost is known up front, as in eFootball's Epic boxes.
18. **Staged Legendary reveal:** pack colour, then era, position, flag and silhouette, then a walkout of 5–7 s. Each step is tap-to-advance, with Skip after 20 packs. Commons take 0.3 s. End on "Try it now".
19. **Show odds on screen** for every pack (tier rates plus the pity counter). This is required by Apple 3.1.1 later, but build it in now.
20. **Legacy cards are sidegrades on a fixed power budget.** Ranked normalises stats, and only Career mode allows stat growth.
21. **Post-match screen order:** result, XP ticks with rising pitch, Road or rank bar, rewards, next-goal line, then a large "Play Again" in the thumb zone.
22. **After a loss, show a highlight** (best Flow moment or the player's top stat) and the streak shields left, never just a "DEFEAT" screen.
23. **Game-feel budget:** 70 ms hit-stop on shots, 1 s slow motion at 0.3× on goals, haptics on shot, tackle and goal, and an input-to-movement delay of one frame at most.
24. **Offline Street Pass skeleton:** 40 tiers over a 6-week season, a free track, and a premium track stubbed in for later IAP. The premium track pays back about 60% of its price in Gems *(est.)*. Cosmetics only.
25. **Season album and crews for later.** Collecting all Legacy cards in a season completes an album that gives a unique celebration. Store crew and ranked data in models that can sync to a server later.
26. **Local telemetry from day one:** `ftue_step`, `match_end` (result, duration, Flow count), `pack_open` (rarity, pity), `session_start`, all written to a local JSONL file for balancing now and uploading later.
27. **Economy rules:** no energy or stamina gates, no timed chests and no forced ads. Session length is held by the daily caps (3 Daily Drops, first-win bonus), not by making the player wait.
