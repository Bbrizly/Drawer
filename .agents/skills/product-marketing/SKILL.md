---
name: product-marketing
description: Use when preparing Drawer Mac App Store screenshots, listing metadata, ASO, website imagery, release graphics, launch copy, or product marketing assets.
---

# Drawer product marketing

Market the product that exists in this repository. Do not invent integrations, cloud behavior, AI capabilities, privacy guarantees, themes, or workflow features.

## Read first

- `README.md` for the current product promise, feature set, privacy model, download surfaces, and terminology.
- Recent commits before preparing release notes or refreshed screenshots.
- Existing `Docs/media/` assets and website material before generating duplicate artwork.

Drawer is a macOS menu-bar productivity app built around a deliberately simple idea: the user's day remains a markdown file while Drawer makes it immediately usable. The strongest story is speed, locality, and the physical slide-out experience—not a giant generic task-manager feature list.

## Hard rules

1. **Show the real Mac app.** Never generate fake Drawer UI with an image model.
2. **Preserve the markdown-first story.** Do not position Drawer like a cloud task service.
3. **Privacy claims must match implementation.** Local/on-device statements must be checked against the feature being marketed, especially optional Apple Intelligence behavior.
4. **Theme screenshots need truth.** Use actual shipped themes and real UI states.
5. **Do not overload store screenshots.** One strong outcome per frame.

## Capture plan

Capture the actual app at stable window/panel sizes. Prefer seeded or intentionally prepared markdown content that looks realistic and contains no personal information.

Strong candidate states include:

- the panel sliding over a real desktop context;
- today's markdown tasks with carried/tomorrow sections;
- focus timer or Pomodoro in progress;
- idea board / notes / teleprompter if visually strong;
- time tracking and proposed work summary;
- a small theme comparison only if it communicates personality rather than clutter;
- local AI planning or automatic time attribution only when the exact shipped behavior can be demonstrated accurately.

Use screenshots of the real product with designed framing/copy around them. Generate backgrounds or decorative launch art separately; never redraw the application itself.

## Mac App Store story

Default five-frame sequence:

1. **Hero:** Your day, one shortcut away.
2. **Core:** Work directly from your markdown task file.
3. **Focus:** Run the task and timer without changing context.
4. **Differentiator:** local workflow feature with the strongest current visual.
5. **Personality/control:** themes, privacy, or another genuinely differentiating shipped benefit.

The first frames should make sense to somebody who has never heard of markdown-based task workflows.

## ASO and copy

- Research current Mac App Store competitors and search language before finalizing metadata.
- Do not keyword-stuff the visible copy.
- Prefer terms users search for over implementation names such as MCP unless targeting a developer-specific campaign.
- Keep AI wording subordinate to the core product unless usage data or positioning clearly proves otherwise.
- If live ASO tooling is available, narrow candidate keywords locally before spending calls/credits on ranking data.

## Website and release assets

For GitHub/website/social launches, the product can support richer art than the App Store listing:

- a short desktop-context animation/GIF;
- one clean hero still;
- feature cards using real screenshots;
- a theme montage;
- release graphics built from the exact user-facing changes since the previous tag.

Do not generate decorative assets that fight the app's visual identity. Drawer already has a strong art-directed personality; marketing should extend it, not wrap it in generic startup gradients.

## Output contract

When asked for marketing work, produce:

- current positioning and target user;
- screenshot storyboard with exact app state for each frame;
- App Store metadata/copy as applicable;
- capture checklist and required demo markdown state;
- website/social asset list;
- release highlights grounded in commits;
- any claims or features that could not be verified.
