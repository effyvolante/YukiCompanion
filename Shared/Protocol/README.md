# Companion bridge protocol

The native companion and Chrome extension communicate through the existing localhost bridge. This directory records the platform-neutral message contract without changing the working macOS implementation.

Commands currently used by the extension:

- `send_message`: `{ type, id, text, contextID? }`
- `idle`: returned when no command is queued

Events returned by the extension:

- `status` with `state: "submitted"`
- `response_update`
- `response_complete` with `id` and `text`
- `error` with `id` and `message`

The Windows client should implement this same contract. It must not require an OpenAI API key or direct ChatGPT API access.
