# Design system — Where the Food At

The rules every screen follows, so new work stays consistent. All values live as **CSS custom properties
on `:root` in [index.html](index.html)**. Use the token, never a raw number. If something genuinely needs a
new value, add a token here and in `:root` first, then use it.

**Look & feel:** light, airy, warm and soft. Cream background, white surfaces, dusty-rose accent, plum headings,
generous spacing, rounded shapes. Light theme only.

---

## 1. Colour

| Token | Use |
|---|---|
| `--bg` | Page background (warm cream) |
| `--surface` | Cards, sheets, inputs |
| `--surface-2` | Subtle fills: segmented track, tiles, note blocks, hover |
| `--line` / `--line-strong` | Dividers / input and chip borders |
| `--ink` / `--ink-2` / `--muted` | Headings & body / secondary text / hints, placeholders, meta |
| `--rose`, `--rose-600`, `--rose-50`, `--rose-100` | Primary accent: primary buttons, selected states, links, focus |
| `--plum` | Hero headings only |
| `--sage` / `--sage-50` | Good / open / "easy" |
| `--amber` / `--amber-50` | Caution / meals / "from Google" / automatic |
| `--red` / `--red-50` | Errors / closed / "hard" / destructive |
| `--lilac` / `--lilac-50` | Tags, demo banner |

Text on coloured fills uses the matching dark token on its `-50` tint (e.g. `--sage` on `--sage-50`).

## 2. Type

| Use | Font | Size / weight |
|---|---|---|
| Hero title | `--font-display` (Fraunces) | `clamp(34px, 5vw, 52px)` / 500 |
| Sheet titles, section titles, card names, results title | `--font-display` | 20–28px / 600 |
| Body, inputs | `--font-body` (Plus Jakarta Sans) | 16px (15px body on phones; **inputs stay 16px** so iOS doesn't zoom) |
| Field labels | `--font-body` | 14px / 600, `--ink-2` |
| Help text | `--font-body` | 13px, `--muted` |
| Eyebrows / planner labels | `--font-body` | 12px / 700, uppercase, 0.08em tracking |

## 3. Sizing scale (heights)

| Token | Value | Used for |
|---|---|---|
| `--control` | **48px** | Every form field: `.input`, `.select`, time pickers, `.tag-box`, and any button sitting *beside* a field (e.g. the Search button next to Name) |
| `--control-sm` | **44px** | Page-level controls: default `.btn`, toolbar search & sort, quick-filter chips, top-bar pickers, round icon buttons (`.icon-btn`, account button) |
| `--control-xs` | **38px** | `.btn-sm`, segmented options (`.seg`), choice chips (`.chip`) |
| `--control-xxs` | **34px** | `.btn-xs`, active-filter chips |

**Rule:** controls that sit on the same line use the **same** token. A field and its neighbouring button are
both `--control`, and toolbar items are all `--control-sm`.

Textareas are the only exception (min 110px, grow with content).

## 4. Spacing

| Token | Value | Between |
|---|---|---|
| `--gap-label` | 8px | A label and its control; a control and its help text |
| `--gap-field` | 20px | One field (or row of fields) and the next, stacked |
| `--gap-inline` | 16px | Fields side by side in a `.row` |

Bigger rhythm (not tokenised yet): sheet sections 28px vertical padding with a `--line` divider,
cards 24px padding (20px on phones), page side gutter 32px (16px on phones).

## 5. Radius & shadow

`--r-sm` 10px (inputs) · `--r` 16px (tiles, presets, result lists) · `--r-lg` 24px (cards, sheets, planner, modals) ·
`--r-pill` (buttons, chips, segmented controls).
Shadows: `--shadow-sm` (resting cards), `--shadow` (hover, planner, popovers), `--shadow-lg` (sheets, modals, toasts).

---

## 6. Layout patterns (use these, don't improvise)

### A field
```html
<div class="field">
  <label for="x">Label</label>            <!-- or <span class="label"> for groups of chips/segments -->
  <input id="x" class="input" …>
  <p class="help">Optional help text.</p>
</div>
```
- `.field` is a vertical grid with `--gap-label` and `align-content: start`.
- Stacked fields get `--gap-field` automatically (`.field + .field`).

### Fields side by side
```html
<div class="row">                          <!-- 2 columns; style="--cols:3" for 3 -->
  <div class="field">…</div>
  <div class="field">…</div>
</div>
```
- `.row` aligns children to the **top** and removes the stacked gap, so labels share one line and controls share
  one line, even when one field has help text and the other doesn't.
- Rows collapse to one column on phones (≤ 640px).
- **Never** place two `.field`s side by side without a `.row` wrapper, and never add margins to individual
  fields inside a row.

### A field with an action button
`.name-row` (flex, 8px gap): the input grows, the button is `--control` tall.

### Choices
- **One of a few short options** → segmented control `.seg` (radio inputs).
- **Pick one, many or wordy options** → `.chips` of `.chip` (radio or checkbox).
- **On/off** → `.switch` inside a `.switch-row` with a bold title and help text.
- **Long list (states, times)** → `.select`.

### Sheets & modals
- Side sheet (`dialog.sheet`, `.wide` for forms): `.sheet-head` (eyebrow + display title + ✕), scrolling
  `.sheet-body`, sticky `.sheet-foot` (destructive left, Cancel + primary right).
- Bottom sheet on phones (automatic). **Forms (add/edit) are full-screen on phones** so their top fields can't
  sit above the visible screen.
- **Only `.sheet-body` scrolls.** The head and foot are fixed: put a sheet's key information and primary actions
  in the head (e.g. the place details sheet shows name, address, status, price and Call/Book/Website/Directions there).
- Size sheets with `dvh` (visible screen) and a `vh` fallback, never `vh` alone.
- Don't auto-focus a field when a sheet opens on touch screens (the keyboard covers the form); do on desktop.
- Small confirmations use `dialog.modal`, centred, with actions right-aligned.

### Buttons
`.btn-primary` (one per view/footer), `.btn-soft` (secondary accent), `.btn-outline`, `.btn-ghost`, `.btn-danger`.
Sizes via `.btn-sm` / `.btn-xs` only.

---

## 7. Behaviour rules

- **No browser autofill on place data.** Place fields use neutral `name`/`id` values (`pl_v1`, `pl_l1`, …, mapped via
  `FIELD_ALIAS`), `autocomplete="wtfa-no-autofill"` (not `"off"`, which Chrome ignores on address-like forms),
  never `type="tel"` (use `type="text" inputmode="tel"`), and saving is a button click, not a native form submit.
  Only the sign-in form uses real autocomplete values.
- **Focus** is always visible (rose focus ring); never remove outlines without a replacement.
- **Touch targets** ≥ 34px; primary actions ≥ 44px.
- **Motion** is short (≤ 0.3s, `--ease`) and disabled under `prefers-reduced-motion`.
- **Empty, loading and error states** exist for every list or async action.
- **Destructive actions** use Undo (toast) rather than a blocking confirm, where data can be restored.

---

## 8. Checklist for any UI change

- [ ] Colours, sizes, gaps and radii come from tokens; no new raw pixel heights or gaps.
- [ ] Side-by-side fields are wrapped in `.row`; labels and controls line up (check at desktop and phone width).
- [ ] Controls on the same line share a height token.
- [ ] New place inputs follow the autofill rules in §7.
- [ ] Works at 375px wide with no sideways scroll; inputs 16px on phones.
- [ ] Keyboard: reachable, visible focus, Esc closes sheets/modals.
- [ ] Empty / loading / error states covered.
