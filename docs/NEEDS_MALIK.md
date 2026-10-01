# Things that need Malik (only when no workaround exists)

1. **Deploy the online server** — Railway CLI is logged out on this Mac. Run `railway login` (or tell me another host),
   DONE 2026-09-30: deployed to Railway (project panna-server, volume at /data).
   server (`cd Server && swift run PannaServer`) — the simulator connects to `ws://127.0.0.1:8080/ws`.
   After deploy: set the production URL in `OnlineClient.defaultURL`.
2. (Optional) Apple Developer team for device builds / TestFlight — set `DEVELOPMENT_TEAM` in project.yml.
3. **In-app purchases** — StoreKit 2 is wired (gems 320/1800/8000, Street Pass Premium S1) and testable from Xcode via
   `Panna/Resources/Panna.storekit` (scheme Run option). For TestFlight/App Store, create the same product IDs in
   App Store Connect (`com.malik.panna.gems.320`, `.gems.1800`, `.gems.8000`, `com.malik.panna.pass.s1`).
