# Things that need Malik (only when no workaround exists)

1. **Deploy the online server** — Railway CLI is logged out on this Mac. Run `railway login` (or tell me another host),
   then I'll run `railway up` from the repo root (Dockerfile is ready). Until then online play works against a local
   server (`cd Server && swift run PannaServer`) — the simulator connects to `ws://127.0.0.1:8080/ws`.
   After deploy: set the production URL in `OnlineClient.defaultURL`.
2. (Optional) Apple Developer team for device builds / TestFlight — set `DEVELOPMENT_TEAM` in project.yml.
