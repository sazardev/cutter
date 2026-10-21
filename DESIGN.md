# DESIGN.md: M3 Expressive

Material 3 Expressive, the 2025 evolution of Material Design 3. It keeps every M3 token (color roles, type scale, shape
scale, window size classes) and adds a physics-based motion system, a larger shape library with morphing, emphasized
typography and new components. Source of truth: m3.material.io (Expressive updates). Where a value below says "reference",
check m3.material.io before relying on its precision.

## Principles

- **Expressive with purpose**: emotion (shape, color, motion, type) is used to guide attention to the key action, not everywhere.
- **Roles still rule**: components ask for M3 roles (`primary`, `surface-container-high`…); expressiveness never means raw colors.
- **Physics, not curves**: motion is driven by springs, so interruptions and gestures feel continuous.
- **Hierarchy by contrast**: bigger, bolder, more colorful for the one thing that matters; calm for the rest.
- **Accessible first**: larger targets, stronger contrast in emphasized states, reduced-motion fallbacks.

## Color

Same role system and baseline as M3 (seed `#6750A4`); Expressive leans on higher-chroma containers and tertiary accents.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `primary` | `#6750A4` | `#D0BCFF` | Key action, FAB, active toggle |
| `on-primary` | `#FFFFFF` | `#381E72` | Text/icons on primary |
| `primary-container` | `#EADDFF` | `#4F378B` | Emphasized buttons, selected states |
| `on-primary-container` | `#21005D` | `#EADDFF` | Text on primary-container |
| `secondary-container` | `#E8DEF8` | `#4A4458` | Toolbars, button groups (unselected) |
| `tertiary` | `#7D5260` | `#EFB8C8` | Expressive accents, highlights |
| `tertiary-container` | `#FFD8E4` | `#633B48` | Hero cards, celebratory moments |
| `error` | `#B3261E` | `#F2B8B5` | Errors, destructive actions |
| `surface` | `#FEF7FF` | `#141218` | App background |
| `surface-container` | `#F3EDF7` | `#211F26` | Navigation, docked toolbars |
| `surface-container-high` | `#ECE6F0` | `#2B2930` | Floating toolbars, menus |
| `on-surface` | `#1D1B20` | `#E6E0E9` | Body text |
| `on-surface-variant` | `#49454F` | `#CAC4D0` | Secondary text, icons |
| `outline-variant` | `#CAC4D0` | `#49454F` | Dividers |

- Brand schemes come from Material Theme Builder; dynamic color stays supported. Success/warning as harmonized custom colors.
- Use **vibrant** container colors (`*-container`, `tertiary`) on the single hero element of a screen; keep surfaces neutral.
- Every token has a light and a dark value; the app follows `prefers-color-scheme` (or the OS setting) and offers a manual Light / Dark / System switch.
- Dark is not inverted light: surfaces get lighter as they rise, saturated colors are toned down (lower chroma) to avoid glare.
- Keep the preset's palette; the brand color (one hex, TODO) replaces `primary`/`accent`.
- Tints and shades in OKLCH: same hue, lightness steps 98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 15% with chroma reduced near the extremes; each step checked for contrast with its `on-` color.
- Neutrals take a trace of the brand hue (chroma ≤ 0.01) so greys feel related.
- These values replace the base palette's for the same roles; contrast pairs are checked again after the swap.
- Success/danger pairs never rely on red vs green alone: add icons (`✓`, `✕`), labels or patterns; charts use a color-blind safe set (e.g. Okabe-Ito: `#E69F00`, `#56B4E9`, `#009E73`, `#F0E442`, `#0072B2`, `#D55E00`, `#CC79A7`).

## Typography

M3 type scale plus an **emphasized** variant of every role (heavier weight). Variable fonts preferred: Roboto Flex or Google Sans Flex (reference).

| Role | Size / line height | Weight (regular → emphasized) | Use |
| --- | --- | --- | --- |
| display-large | 57 / 64 | 400 → heavier (reference) | Hero numbers, onboarding |
| display-medium | 45 / 52 | 400 → heavier | |
| headline-large | 32 / 40 | 400 → heavier | Screen hero titles |
| headline-medium | 28 / 36 | 400 → heavier | |
| headline-small | 24 / 32 | 400 → heavier | Dialog titles |
| title-large | 22 / 28 | 400 → 500+ | App bar titles |
| title-medium | 16 / 24 | 500 → heavier | Card titles |
| body-large | 16 / 24 | 400 → 500 | Main text |
| body-medium | 14 / 20 | 400 → 500 | Component text |
| label-large | 14 / 20 | 500 → 600+ | Buttons |
| label-medium | 12 / 16 | 500 → 600+ | Chips, badges |

- Exact emphasized weights: reference, check m3.material.io (they are token values `*-emphasized`).
- Use emphasized type for the one element to read first (a key number, the primary label); never for whole paragraphs.

## Spacing and layout

- 4dp grid, layout on 8dp; scale 0, 4, 8, 12, 16, 24, 32, 40, 48, 64 (as M3).
- Window size classes: compact < 600, medium 600–839, expanded 840–1199, large 1200–1599, extra-large ≥ 1600 (dp).
- Margins 16dp compact, 24dp medium and up. Flexible navigation rail that expands into a drawer-like rail on large windows.
- Hero areas get generous space and larger shapes; dense areas (lists, settings) stay at M3 density.
- Minimum window 800×600; layouts reflow from one to three panes (sidebar, list, detail) as the window grows; splitters remember their width.
- Respect the OS title bar and window controls (left on macOS, right on Windows/Linux).
- Respect safe areas (notch, home indicator, status bar): content padded by the platform insets, backgrounds may bleed under them.
- Phone first (360-430 pt wide), tablet layouts at ≥ 600 pt use two panes (list-detail).
- Primary actions in the thumb zone: the lower half of the screen.
- Mobile first: design at 360 px, then adapt at `sm 640`, `md 768`, `lg 1024`, `xl 1280`, `2xl 1536` px.
- Fluid type and spacing with `clamp()` between the smallest and largest breakpoint (e.g. body `clamp(1rem, 0.95rem + 0.25vw, 1.125rem)`).
- Components adapt to their container with container queries (`@container`), not to the viewport.
- Content measure 60-75 characters; the page never scrolls sideways at 320 px.
- 8 px grid (4 px for fine adjustments), rows 44-48 px, controls 36-40 px high, body text 15-16 px.
- Sections separated by 24-32 px; cards with 16-24 px padding.

## Shape and elevation

| Token | Radius | Use |
| --- | --- | --- |
| extra-small | 4dp | Menus |
| small | 8dp | Chips |
| medium | 12dp | Cards |
| large | 16dp | FABs, sheets |
| large-increased | 20dp (reference) | Larger cards, hero containers |
| extra-large | 28dp | Dialogs, bottom sheets |
| extra-large-increased | 32dp (reference) | Expressive hero surfaces |
| extra-extra-large | 48dp (reference) | Large expressive containers |
| full | 50% | Buttons, toggles, indicators |

- **Shape library**: ~35 abstract shapes (cookie, clover, sunny, pill, burst, soft-burst…) for avatars, image masks and loading indicators. Use one or two per product, consistently.
- **Shape morphing**: shapes animate between states (a button that squares its corners when pressed, a selected toggle that changes shape); always through a spring.
- Elevation as M3: levels 0, 1, 3, 6, 8, 12 dp, tonal first, shadows only on floating elements (FAB, floating toolbar, menus).

## Motion

Motion is built from **springs** (damping ratio + stiffness), not duration + easing. Two families:

| Spring | Damping | Stiffness | Use |
| --- | --- | --- | --- |
| spatial fast (expressive) | 0.6 | 800 | Small components moving/resizing |
| spatial default (expressive) | 0.8 | 380 | Containers, sheets, position changes |
| spatial slow (expressive) | 0.8 | 200 | Full-screen transitions |
| effects fast | 1.0 | 3800 | Color, opacity on small parts |
| effects default | 1.0 | 1600 | Color/opacity of components |
| effects slow | 1.0 | 800 | Large fades |

- Values are reference (check m3.material.io): spatial springs may overshoot (bounce), **effects springs never do** (damping 1.0) because color and opacity must not overshoot.
- Two schemes: **expressive** (bouncier spatial springs, the default for hero moments) and **standard** (more damped, for utility UIs).
- Interruptible: a new gesture retargets the running spring; never wait for an animation to finish.
- Reduced motion: replace spatial springs with fades (effects springs) and disable shape morphing.
- Springs instead of fixed curves: default `stiffness 380, damping 30` (snappy), `stiffness 200, damping 26` (gentle); interruptible at any time.
- Shared-element transitions between list and detail (View Transitions API on web, Hero/matchedGeometry on mobile).
- Choreography: related elements stagger by 30-50 ms, never more than 5 in a sequence; total under 500 ms.
- Micro-interactions on success/error (a check that draws, a field that shakes once).

## Components

- **Buttons**: five sizes (XS, S, M, L, XL; reference) and round or square shape; the pressed state morphs the shape. Use L/XL only for the main action of a screen.
- **Button groups**: connected or standard groups of related actions; the pressed button widens and neighbours yield. Replace segmented buttons with connected button groups.
- **Split buttons**: a primary action plus a trailing menu of variants; the trailing part rotates/morphs on open.
- **FAB menu**: the FAB opens into a list of up to 6 related actions; replaces speed dials.
- **Toolbars**: docked (bottom, full width) or floating (pill, vibrant or standard color); replace the bottom app bar.
- **Loading indicator**: morphing-shape indicator for waits under ~5s; **wavy progress indicators** (linear and circular) for determinate progress.
- **Navigation**: short navigation bar, flexible navigation rail (collapsed/expanded), app bars with larger title options.
- **States**: loading (loading indicator, skeleton for content), empty (expressive shape + one action), error (message + retry).
- A menu bar (or app menu) lists every command with its shortcut; context menus on right click.
- Every action has a keyboard shortcut following the platform (`Cmd` on macOS, `Ctrl` elsewhere); a command palette (`Cmd/Ctrl+K`) finds any command.
- Pointer states: hover, pressed, focus ring, and the right cursor (pointer, text, resize).
- Bottom navigation with 3-5 destinations; back follows the platform (swipe on iOS, system back on Android).
- Touch targets at least 44×44 pt (iOS) / 48×48 dp (Android), 8 pt apart.
- Gestures (swipe to delete, pull to refresh) always have a visible alternative.
- Haptics only to confirm meaningful actions (success, selection, error), never on scroll.
- Navigation collapses to a menu button below `md`; tables become stacked cards or scroll inside their own container.
- Hover is an enhancement: every action works with touch and keyboard (`@media (hover: hover)` for hover-only styles).
- GUI: choose the lightest overlay: popover for a small tooltip-like choice anchored to a control; drawer (right side, 420-560 px) for viewing or editing an object while keeping context; modal dialog (max 480 px, 640 px for forms) only for a decision or short task that must be finished before continuing; a full page for anything longer.
- GUI: modal structure: title (verb or question), body, footer with buttons right-aligned, primary on the right, secondary "Cancel" to its left; a close "x" at the top right; scrim at 50% over the page; max one dialog open at a time, never a dialog opening a dialog.
- GUI: open with focus on the first field, or on the least destructive button for confirmations; trap focus inside; on close return focus to the control that opened it; background is inert and does not scroll.
- GUI: close with Esc, the x button, and clicking the scrim, except when the dialog holds unsaved input: then ask "Discard changes?" with "Keep editing" as the default.
- GUI: destructive confirmation copy: title "Delete 'Project Apollo'?", body states the consequence and whether it can be undone ("This removes 14 files and cannot be undone."), buttons name the action ("Delete project" in danger color) and "Cancel"; never "OK / Yes / No".
- GUI: for irreversible high-impact actions require typing the resource name before the danger button enables.
- GUI: on mobile, dialogs become bottom sheets with a drag handle, up to 90% height, scrollable body with a fixed footer.
- TUI: a centered box with a title in the border, the same footer keys shown inside (`[Enter] Delete  [Esc] Cancel`), default on Cancel for destructive prompts; `y/n` accepted for simple confirmations.
- Every empty state has three parts at most: a short title, one sentence of explanation, one primary action. No lorem, no jokes, no more than 2 lines of body.
- GUI: first-use: title names what will live here ("No projects yet"), the sentence says the benefit, the button creates the first one ("Create project"); a secondary text link to docs or import is allowed.
- GUI: no-results (search or filters): echo the query ("No results for "invoice 99""), suggest one fix ("Check spelling or clear filters") and offer "Clear filters" as the action.
- GUI: error: say what failed in plain words, keep the cause short, offer "Try again" as the primary action and keep any cached content visible if it exists.
- GUI: no-permission: say what is blocked and who can grant it ("Ask an admin for access"), with a "Request access" action when the product supports it; never show a bare 403.
- GUI: illustration is optional: a single flat 96-128 px spot illustration or icon in muted tones, centered above the title; inside small panels (under 240 px high) use the icon only or nothing.
- GUI: center the block in the container both ways; max width 360 px; a list or table keeps its header visible above the empty state.
- TUI: a centered dim block of 1-3 lines with the key hint in brackets: `No sessions yet. Press n to create one.`; no ASCII art.
- GUI: drop zone: dashed-outline area at least 160 px high with an icon, "Drag files here or Browse" where "Browse" is a button, and a line stating limits ("PNG, JPG or PDF, up to 10 MB each, max 5 files"); dragging over it changes to a primary tinted state with "Drop to upload".
- GUI: validate on selection before upload: type, size and count; rejected files are listed with the reason ("report.zip: file type not allowed") while valid ones continue; never silently drop a file.
- GUI: each file is a row: thumbnail (40 px for images, type icon otherwise), name truncated in the middle, size, a progress bar with percentage, and a cancel button; finished rows show a check and a remove button.
- GUI: upload in parallel (3 at a time), show overall progress when more than 3 files, and keep working if the user navigates inside the app (uploads continue in the background with a small indicator).
- GUI: errors are per file with a "Retry" action: network failure, too large, server rejected; resumable uploads resume instead of restarting; the form can be submitted only after required files finish, and says "Waiting for 2 uploads".
- GUI: single-file fields (avatar) show a preview in place with "Replace" and "Remove"; images support crop before upload when the aspect ratio matters.
- GUI: paste from clipboard and mobile camera capture work where relevant; accept uses `accept` plus server-side validation, never only the extension.
- GUI: removing an uploaded file is undoable until the form is saved; deleting one already saved asks for confirmation.
- TUI: `upload path/to/file` shows one line per file with a bar `file.zip  [#####-----] 52%  3.1 MB/s`; Ctrl+C cancels cleanly, a retry flag resumes; the final line prints the URL or id.
- GUI: a bell icon button in the top bar, 40 px target, with a badge showing the unread count (cap at "99+"); a dot instead of a number when counts are not meaningful; the badge clears per item as read, not all at once on open.
- GUI: clicking opens a popover (400 px wide, max 560 px high) on wide screens or a full screen on narrow ones; header "Notifications" with "Mark all as read" and a settings icon; tabs "All" and "Unread" with counts.
- GUI: each item: actor avatar, one-line sentence with the bold object ("Ana commented on Roadmap"), a 2-line preview at most, relative time, an unread dot and tinted surface; clicking marks it read and goes to the exact place; a "..." menu offers Mark as unread, Mute thread, Delete.
- GUI: group by day (Today, Yesterday, Earlier) and collapse bursts of the same kind ("5 people reacted to your post"); important items (mentions, approvals, failures) are not collapsed or muted by defaults.
- GUI: new notifications arriving live update the badge and prepend without moving what the user is reading; do not play sounds or show desktop alerts unless the user has opted in.
- GUI: empty state: "You are all caught up" with a link to preferences; loading shows 5 skeleton rows; load more on scroll with a page size of 20 and a retention window stated ("Showing the last 30 days").
- GUI: preferences are a matrix of event type by channel (In-app, Email, Push) with toggles, an email digest option (instant, daily, weekly), quiet hours, and a per-project override; sensible defaults: only direct events are on by default.
- GUI: unsubscribe links in emails work in one click without login and say exactly what will stop.
- TUI: a status-line counter `3 unread`, `N` opens the list, `Enter` opens the item, `m` marks read, `M` marks all, `x` dismisses; no popups interrupting typing.
- GUI: search box 40 px with a leading search icon, placeholder naming what is searched ("Search invoices"), a clear button when it has text, and "/" as the focus shortcut; search runs as the user types after a 250 ms debounce, or on Enter for expensive queries.
- GUI: filters sit in a row above the results as chips (`Status: Open  v`); a chip opens a popover with the options and an "Apply" or instant behavior chosen per screen and kept consistent; more than 5 filters go behind a "Filters" button into a side panel.
- GUI: an applied-filters bar shows every active filter as a removable chip (x), the result count ("128 results"), and one "Clear all" link; the bar is absent when nothing is applied.
- GUI: sort is a separate dropdown labelled with the current choice ("Sort: Newest"); the default sort is named, and relevance is the default only when a query exists.
- GUI: search and filters live in the URL so a view can be shared, reloaded, and reached with Back; changing a filter resets pagination to page 1.
- GUI: saved views: "Save view" captures filters, sort and columns under a name; views appear as tabs or a menu, a modified view shows "Modified" with "Save" and "Reset".
- GUI: no results keeps the controls in place, echoes the query and active filters, and offers "Clear filters" (see empty states); a typo suggestion ("Did you mean ...") is shown when available.
- GUI: while loading, keep the previous results visible, dimmed, with a thin progress bar; never flash an empty list between queries.
- TUI: `/` opens an inline prompt, results filter live, `n/N` jump between matches, Esc clears the query; active filters are shown in the header line as `[status:open] [owner:me]` and `f` edits them.
- GUI: group settings into 4-7 sections by what the user is trying to do (Profile, Notifications, Security, Billing), not by technical area; the section list is a left column on wide screens and a list screen on narrow ones.
- GUI: each setting is a row: label (medium weight) and one line of helper text on the left, the control on the right; rows 56 px minimum, dividers between rows, section titles as small headings.
- GUI: toggles and selects apply instantly and confirm with a quiet "Saved" near the control; text inputs and anything with side effects use an explicit "Save" button with "Cancel", shown only when the form is dirty.
- GUI: never mix instant and saved controls inside one card; if a section must, label the saved part with its own button.
- GUI: show the effective value when a setting is inherited ("Using workspace default: English") with a "Reset to default" link per setting.
- GUI: settings search at the top of the screen filters rows by label and helper text, highlights matches, jumps to the section, and shows "No settings match "x"" when empty.
- GUI: danger zone is the last section, separated by a divider, titled "Danger zone", rows with danger-outlined buttons ("Delete workspace"); each action opens a confirmation that requires typing the resource name.
- TUI: a two-pane list: sections on the left, rows on the right as `label  value`; Enter edits, Space toggles, `/` searches, `r` resets the row to default; changes marked with `*` until saved with `w`.
- Pick by scope: inline message for one field or one block; toast for the result of an action the user just took; banner for a persistent state that affects the whole page or account (offline, expired plan, maintenance).
- GUI: toast: bottom-left (or bottom-center on mobile), 360 px max width, surface color with a status icon, one sentence plus at most one action ("Undo", "View"); never put a long explanation or a form inside.
- GUI: toast duration: 4 s for success, 8 s when it has an action, errors stay until dismissed; pause the timer on hover and focus; always include a close button.
- GUI: stack at most 3 toasts, newest at the bottom, 8 px gap; extra ones queue; identical messages merge into one with a count instead of repeating.
- GUI: undo over confirm for reversible actions: perform at once, toast "Moved to trash  Undo" for 8 s, then commit; keep the undo available if the user navigates within the app.
- GUI: banner: full width under the top bar, 48 px, status tint with icon, message, one action and a close button when dismissible; a blocking problem (offline, payment failed) is not dismissible and clears itself when resolved.
- GUI: inline success is a check and "Saved" text next to the control for 2 s; inline errors stay until fixed.
- GUI: write messages as result then next step: "Invoice sent to ana@example.com", "Could not save. Check your connection and try again."; no "Success!" alone.
- TUI: a single status line at the bottom: info in dim text for 4 s, errors in danger color until the next key press; critical failures print a full message above the prompt.

## Accessibility

- Contrast ≥ 4.5:1 for text, 3:1 for UI and large text; vibrant containers still pair with their `on-` roles.
- Touch targets ≥ 48×48dp; button sizes XS/S keep a 48dp target area.
- Shape or size changes are never the only signal of state: pair them with color, icon or label change.
- Every animation respects reduced-motion; no infinite decorative motion outside loading indicators.
- 200% text scaling without loss; emphasized type must not truncate.
- With reduced motion, springs become 150 ms fades and shared-element transitions become cross-fades.
- Every screen is checked with a color-blindness simulator (deuteranopia, protanopia, tritanopia) before it is done.
- With `prefers-reduced-motion: reduce` (or the OS/app setting), movement is replaced by ≤ 150 ms opacity fades; parallax, auto-playing animation and spinners that move across the screen are removed.
- GUI: semantic HTML/native controls first, landmarks, headings in order, every control named, live regions for async updates; tested with VoiceOver and NVDA/TalkBack.
- TUI: an accessible mode (flag or env var) prints linear text without box art, spinners or cursor tricks, one line per state change, readable by screen readers.
- Text contrast at least 7:1 (4.5:1 for large text), targets at least 44×44 px, no timing that cannot be extended, no flashing at all.
- Line height ≥ 1.5, paragraph spacing ≥ 2× font size, measure ≤ 80 characters, text resizable to 200% without loss.
- Context help for every non-obvious input; error messages say how to fix the problem.
- Use `role="dialog"` (`alertdialog` for destructive confirmations) with `aria-modal`, `aria-labelledby` pointing to the title and `aria-describedby` to the body.
- The title is a real heading; the empty state is announced when it replaces content (`role="status"`); the action is reachable by keyboard and is the first focusable element in the region.
- The drop zone is a real button or file input reachable by keyboard (Enter and Space open the picker); progress uses `role="progressbar"` with values; completion and errors are announced in a live region.
- The bell button name includes the count ("Notifications, 3 unread"); the list uses semantic lists; new items are announced politely and rate-limited so a burst is one announcement.
- Search is a `role="search"` landmark; announce the result count in a polite live region after each update; filter chips are buttons with names like "Remove filter Status: Open".
- Toggles are `role="switch"` with the label and state announced; sections are landmarks with headings; the search field is labelled and results count is announced.
- Toasts live in a `role="status"` region (`role="alert"` for errors) and must not steal focus; the action is reachable by keyboard; important messages are never toast-only.

## Rules for agents

- Editor (Cutter): tools open as inline panels (above the tool bar on phones, in the side panel on wide windows), never as dialogs or modal sheets, so the preview stays visible and live; actions that can be undone act at once with an Undo toast instead of asking. The editor is always dark.

- Jetpack Compose: use the Material 3 Expressive APIs (`MaterialExpressiveTheme`, `MotionScheme.expressive()`, `ButtonGroup`, `SplitButtonLayout`, `FloatingToolbar`, `LoadingIndicator`, `MaterialShapes`; reference, check the current `material3` release). Flutter/web: follow M3 tokens and approximate springs with the platform's spring physics.
- Never hardcode colors, radii or durations: read M3 roles, shape tokens and motion scheme springs.
- Animate position/size with spatial springs and color/opacity with effects springs; never a cubic-bezier for new expressive motion.
- Use expressive emphasis (vibrant color, large shape, emphasized type, XL button) on ONE element per screen.
- Keep standard M3 components where expressiveness adds nothing (forms, settings, dense lists).
- Test light, dark and reduced-motion for every screen.
- Never require the mouse: every flow works with the keyboard alone, with visible focus.
- Persist window size, position and pane widths between sessions.
- Use the platform's text scaling (Dynamic Type / font scale) and test at the largest setting.
- Never place interactive elements under the status bar or the home indicator.
- Test every screen at 360, 768, 1280 and 1920 px wide and at 200% browser zoom.
- Use relative units (`rem`, `%`, `ch`) for sizes; `px` only for borders and hairlines.
- Never write a color that only exists in one theme; test every screen in both before it is done.
- Animate only `transform`, `opacity` and `filter`; measure 60 fps on a mid-range phone.
- Every animation is behind the motion preference check; test with it on.
- Never convey state only visually; every icon-only control has an accessible name.
- Never open a modal on page load or without a user action, except a blocking session or consent prompt.
- Button labels are verbs naming the result; the destructive one is never the default focus.
- One primary action per empty state, never two equal buttons.
- Distinguish "nothing exists", "nothing matches", "failed to load" and "not allowed"; never reuse one message for all.
- Copy is written in the product voice, active and specific: no "Oops", no "Nothing to see here".
- Always show the limits before the user picks a file, not only after a failure.
- Never block the whole form on one failed file; the user can remove it and continue.
- Every notification links to what caused it and is actionable or informational, never both vague and urgent.
- Never notify the actor about their own action.
- Never reset the user's filters when they open and leave a detail view.
- Count and label every applied filter; an invisible filter is a bug.
- Every setting states its default and can be reset to it.
- Never apply a destructive or billing change instantly.
- Never hide a setting that is on by default from enterprise or admin users without saying who controls it.
- Never use a toast for something the user must act on before continuing.
- Never auto-dismiss an error or a message with a destructive consequence.
- A widget never names a `Color(0x…)` or a font size: it reads the theme.
- New tokens go into the theme or an extension first.

## Toolkit

| Design | Flutter |
| Color token | a `ColorScheme` role (`primary`, `surface`, `onSurfaceVariant`, `error`…); tokens with no role go in a `ThemeExtension` |
| Text style | a `TextTheme` slot (`titleLarge`, `bodyMedium`, `labelSmall`…), fonts from the design |
| Spacing / radius | constants in a `ThemeExtension` (`AppSpacing`, `AppRadii`) or one `tokens.dart`; never a literal in a widget |
| Dark mode | `theme` + `darkTheme` on `MaterialApp`, `themeMode` from settings |
| Shape | `cardTheme`, `filledButtonTheme`… set the radius once; widgets do not pass `shape` |
| Layout | `LayoutBuilder` / breakpoints for compact, medium, expanded widths |
| Motion | `AnimatedFoo` widgets and `Curves` from the design; `MediaQuery.disableAnimationsOf(context)` respected |

- `lib/theme/` holds the `ThemeData` builders and the extensions; widgets read `Theme.of(context)`.
- Golden tests (`matchesGoldenFile`) cover the main screens in light and dark.
