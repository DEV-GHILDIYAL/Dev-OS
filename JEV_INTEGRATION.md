# Jev integration

Jev is an optional development diagnostic layer. Set `JEV_API_KEY` in the current process environment. The client sends only a redacted, selected state to TypeSafe AI's `POST /v1/systemone` endpoint using typed `choice` and `noul` questions.

If the key is missing, the request fails, times out, or the response is invalid, the client returns no diagnosis and normal Codex investigation continues. Jev is not used for deterministic edits.
