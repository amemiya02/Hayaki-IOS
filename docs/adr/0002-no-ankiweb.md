# No AnkiWeb: sync with a self-chosen server, or not at all

The app has no AnkiWeb sign-in. Sync is available only against a sync server whose address the learner supplies, and the app is fully usable with no sync, moving content with collection packages and deck packages. This is a policy constraint, not a technical one: the embedded core can talk to AnkiWeb, but AnkiWeb's terms of service allow only clients its operators have approved (Anki, AnkiMobile, AnkiDroid, AnkiUniversal) and state that other third-party clients are not allowed.

## Considered options

- **Ship AnkiWeb sign-in and ask permission before a public release.** Rejected for now: permission attaches to a specific app and its maintainers, is granted privately through Anki's ticket system, and AnkiWeb is funded by sales of the official iOS app that this project is a free alternative to.
- **Fork an already-approved client to inherit its access.** Not possible: Anki's staff have said a fork of an approved client is not that client.

## Consequences

Do not add AnkiWeb as a default or preset server, and do not make the server address optional, without written permission from AnkiWeb's operators. If permission is ever granted, supersede this record.
