# Mac app layout — design

Agreed with the user on 2026-10-24 (brainstorm, direction **B**). Colour stays the current
ember palette for now; a jade "Developer Terminal" palette (E2) was liked and is parked.

## Why

The Mac app reads as average because of placement, not colour:

- things move when the phone connects or disconnects (panels appear, vanish and reflow),
  so the window never feels settled;
- the other pages are one narrow strip of cards in a wide window;
- unlinked, Home is a dashboard of empty and disabled panels, with Connect far from its
  message, "not linked" said three times, and disabled orange turning brown.

## Goals

- **One fixed skeleton.** Connecting changes what is *in* the boxes, never which boxes
  exist or where they are.
- **Every page uses the window**: list on the left, detail or settings on the right.
- **Calm unlinked state**: same boxes, one grey line each; the link card says what to do
  next, with Connect beside it.
- **Disabled is grey, never dimmed orange.**

## Non-goals

- No colour change (ember stays). No new features, no protocol or server change.
- No sidebar (direction A was not chosen); the floating top bar stays.

## The design

### Home
- **Floating top bar** unchanged: five pages, link status at the end.
- **Link card**, one fixed height in every state:
  left, the Mac and phone circles joined by the wire (dashed and the phone dim when not
  linked; ripples behind the phone while searching); middle, status pill, title, one
  detail line, then battery and sync latency; right, the action — **Connect** when not
  linked, **Now Playing** (compact, with play/pause/next) when the phone is playing
  something, otherwise **Mirror screen**. Unlinked title leads with the next step
  ("Connect your phone"), not the problem.
- **Three equal columns** below, always in this order, filling the window's height and
  ending on one bottom edge; long lists scroll inside their own box:
  1. **Clipboard** — every clip, newest first.
  2. **From your phone** — live activities, then notifications.
  3. **Phone & files** — Ring / Open link / Mirror, the drop zone, transfers.
- **Narrow window** (builder's call): below about 880 pt the columns stack in the same
  order inside one scroll view.

### Other pages
- **History**: day-grouped list on the left; on the right a preview of the selected clip
  (full text or the image) with **Copy** and **Send to phone**. Clicking a row still copies
  it — the fast path stays one click — and selects it.
- **Devices**: the account's devices on the left; on the right how linking works and
  **Link with a code** (builder's call: there are usually two devices, so a per-device detail
  pane would be empty furniture).
- **Screen**: the mirrored phone large on the left; a control column on the right (start or
  stop, back / home / recents, the remote-control note).
- **Account**: two columns — account card, This Mac and Account on the left; Everyday and
  Your phone and this Mac on the right.

### Menu bar popover
Same order as Home so the two read as one app: link card, quick actions, Now Playing,
**recent clips**, live on your phone, files.

### Android
Already liked; only the order follows the Mac: link card, Clipboard, then Files.

### Website
Unchanged in this pass; its app mockups get redrawn once the Mac layout lands.

## Left to the builder
Exact sizes, the narrow-window breakpoint, empty-state wording, and verifying every state
(linked, unlinked, searching, mirroring) with the demo renders in both appearances.
