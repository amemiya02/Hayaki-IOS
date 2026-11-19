# Hayaki

The iPhone and iPad edition of Hayaki, the offline study app for Anki collections. It keeps the whole collection on the device and stays compatible with desktop Anki and AnkiDroid. Hayaki is not affiliated with or endorsed by Anki's makers.

Terms follow upstream Anki's vocabulary exactly. Where AnkiDroid or older Anki versions use a different word, the upstream word wins.

## Language

### Content

**Collection**:
Everything one person studies: all their decks, notes, cards, note types, settings and review history, kept together as a single unit.
_Avoid_: Database, library, account

**Profile**:
A learner’s local study environment, with its own collection, media and sync destination.
_Avoid_: Account, collection

**Note**:
One piece of knowledge to remember, held as a set of field values and shaped by a note type. A note produces one or more cards.
_Avoid_: Fact, item, entry

**Field**:
A named slot of content on a note, such as "Front" or "Back".
_Avoid_: Column, attribute

**Note Type**:
The definition of which fields a kind of note has and which card templates turn it into cards.
_Avoid_: Model, note model, template

**Card Template**:
The front and back layout, belonging to a note type, that turns a note's fields into one card.
_Avoid_: Card type, layout, card model

**Card**:
One question-and-answer pair generated from a note by a card template. Cards, not notes, are what gets scheduled and studied.
_Avoid_: Flashcard, item

**Deck**:
A named group of cards that are studied together. Decks can be nested inside other decks.
_Avoid_: Folder, set, stack

**Tag**:
A label attached to a note for organising and searching, independent of which deck its cards are in.
_Avoid_: Label, category

**Media**:
The image, audio and video files that notes refer to.
_Avoid_: Attachments, assets

### Studying

**Review**:
One act of answering a card and rating how well it was recalled.
_Avoid_: Answer, rep, repetition

**Rating**:
The learner's judgement of a review: Again, Hard, Good or Easy.
_Avoid_: Ease, grade, score, answer button

**Due**:
The state of a card whose next review is scheduled for today or earlier.
_Avoid_: Pending, overdue (for cards due today)

**Deck Options**:
The settings that control how a deck's cards are introduced and scheduled, such as daily limits and learning steps.
_Avoid_: Deck settings, deck config, study options

**Preset**:
A named set of deck options that one or more decks share. Changing a preset changes every deck that uses it.
_Avoid_: Options group, config, profile

### Moving collections

**Sync**:
Reconciling the collection on this device with the copy held by a sync server, so that every device ends up with the same collection.
_Avoid_: Backup, upload, cloud save

**Sync Server**:
A service that holds a copy of a collection for syncing. The destination can be AnkiWeb or a self-hosted server.
_Avoid_: Cloud, backend, remote

**AnkiWeb**:
The sync server operated by Anki's makers.
_Avoid_: Anki cloud, Anki account, the server

**Collection Package**:
A single file containing an entire collection with its media. Importing one replaces the collection on the device.
_Avoid_: Full export, collection backup, colpkg file

**Deck Package**:
A single file containing chosen decks with their notes, cards and media. Importing one merges its contents into the existing collection.
_Avoid_: Shared deck, deck file, apkg file

**Backup**:
A dated copy of the whole collection kept on the device so an earlier state can be restored. A backup never leaves the device unless the learner copies it out.
_Avoid_: Snapshot, sync, export

**Client**:
An app that holds a full collection locally, works offline, and syncs it. This project is a client in this sense, never a remote viewer of a collection stored elsewhere.
_Avoid_: Companion app, viewer, front end
