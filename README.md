# cal-patches

Small patches on top of official [Cal.com](https://github.com/calcom/cal.com) releases, and the workflow that builds them into a container image.

| Path | What |
|---|---|
| `upstream.env` | The pinned Cal.com release (`CAL_VERSION`). The only place the version is set; Renovate bumps it. |
| `patches/*.patch` | The patches, in `git diff` format against that release. |
| `tests/` | Unit tests copied into the patched tree and run with Cal.com's own test setup. |
| `scripts/fetch.sh` | Clones the pinned release and applies every patch. Fails, naming the patch, if one doesn't apply. |
| `scripts/verify.sh` | `fetch.sh`, then the unit tests, upstream's `getSchedule` suite and a type-check of `apps/web`. |
| `scripts/build.sh` | `fetch.sh`, then builds upstream's `Dockerfile` the way upstream's release workflow does. |
| `screenshots/` | Boots an image against a throwaway Postgres with dummy data and captures the booker. |
| `.github/workflows/build.yml` | verify → build and push → screenshots, on every pull request and push to `main`. |

## Patches

### `cal-busy-slots.patch`: show unavailable slots as busy

Upstream Cal.com leaves every time that can't be booked out of the booker ([calcom/cal.com#12004](https://github.com/calcom/cal.com/issues/12004)). With this patch and `CAL_SHOW_BUSY_SLOTS=true` in the server environment, the booker shows those times as disabled slots, labelled with Cal.com's existing `timeslot_unavailable_short` string ("Taken" in English, "Bezet" in Dutch).

- **What shows as busy:** within the event type's weekly working hours, every slot that can't be booked: bookings, busy time on connected calendars, buffers and booking limits, date overrides that block or shorten a day, out of office and holidays, and slots another booker is holding. They all look the same.
- **Privacy:** a busy slot is sent as `{ time, busy: true }` and nothing else: no booking, attendee, calendar or out-of-office details. With the flag on, out-of-office days become plain busy slots too, so their reason and notes are no longer sent.
- **Views:** month and column view show disabled buttons; week view shows outlined blocks. A day whose slots are all busy stays clickable and lists every time as busy, but the automatic date selection and the jump to next month skip it and land on the first day with a bookable slot.
- **Off by default:** with `CAL_SHOW_BUSY_SLOTS` unset, the patched build behaves like upstream. The flag is read on the server at request time, so no rebuild is needed to change it. It has no effect on team (round-robin, collective), seated and "only show the first slot" event types.
- **Language:** the label follows the booker's language: the event type's interface language if set, otherwise the visitor's browser.
- **Booking safety:** busy slots are only disabled in the UI. Cal.com still checks availability on the server when a booking comes in, and the patch doesn't change that path.

Files touched (against v6.2.0):

| File | Change |
|---|---|
| `packages/features/availability/lib/getUserAvailability.ts` | Also returns the weekly working hours alone (`workingHoursDateRanges`) when the flag is on |
| `packages/trpc/server/routers/viewer/slots/util.ts` | Adds every working-hours slot that isn't bookable back as `{ time, busy: true }`; busy-only days don't count as available days for rolling windows |
| `packages/features/calendars/lib/types.ts`, `packages/features/bookings/Booker/hooks/useAvailableTimeSlots.ts` | `busy` on the slot types; busy slots are not clickable cells in week view |
| `apps/web/modules/bookings/components/AvailableTimes.tsx` | Busy slots render disabled, with the label and `data-busy` |
| `apps/web/modules/bookings/components/LargeCalendar.tsx` | Busy slots render as outlined blocks in week view |
| `packages/features/calendars/components/DatePicker.tsx`, `apps/web/modules/bookings/components/DatePicker.tsx` | Automatic date selection and the next-month jump skip busy-only days |

## Image

The workflow pushes `ghcr.io/robbeverhelst/cal-patches:<CAL_VERSION>-p<sha256(patches)[:12]>`. The same release and patches always give the same tag, and an existing tag is not rebuilt (run the workflow by hand with `force` to rebuild). The job summary prints the pushed `image:tag@digest`; deployments should pin that digest.

The package is **public**, like upstream's own image: it holds the upstream release, the public patches and upstream's placeholder build values, and nothing deployment-specific (URLs, secrets and the flag are all set at runtime). Pull it without credentials.

The build needs about 16 GB of RAM (Next.js build, `MAX_OLD_SPACE_SIZE=6144`) and takes 20–35 minutes on a GitHub-hosted runner. Locally, with Docker:

```bash
scripts/verify.sh                                            # apply, test, type-check
IMAGE=ghcr.io/<owner>/cal-patches scripts/build.sh           # apply, build
```

## Refreshing a patch when a build fails

When Renovate bumps `CAL_VERSION` and upstream changed the code a patch touches, `fetch.sh` stops with `<name>.patch does not apply to calcom/cal.com <version>`. Nothing is pushed, and running deployments stay on the digest they pin. To refresh the patch:

```bash
git clone --filter=blob:none https://github.com/calcom/cal.com src && cd src
git switch -c refresh v6.2.0                    # the version the patch was made for
git apply ../patches/cal-busy-slots.patch
git commit -qam "busy slots"
git rebase v6.3.0                               # the new version; resolve conflicts, git add, git rebase --continue
git diff v6.3.0 -- . > ../patches/cal-busy-slots.patch
cd .. && rm -rf src
```

Then check that the result still does what the section above says (`scripts/verify.sh` runs the unit tests and type-check), commit the refreshed patch on the Renovate branch and let the workflow build it. The screenshots job checks that busy slots show up with the flag on and don't with it off.

If upstream rewrote the code a hunk touches, the conflict can't be resolved mechanically. Re-apply the idea by hand: the frontend hunks are a few lines each, and the server part only needs a place after the reserved-slot filter in `_getAvailableSlots` where the bookable slots are known.

## License

Cal.com is licensed under the [GNU Affero General Public License v3](https://github.com/calcom/cal.com/blob/main/LICENSE) (AGPL-3.0), apart from the parts upstream marks as commercial, which these patches don't touch. The patches change AGPL-licensed code and are published under the same license; see [LICENSE](LICENSE).

**AGPL §13:** if you run a patched build and let people use it over a network, you must offer them its source. This repository at the commit you built from, together with the upstream release pinned in `upstream.env`, is that source. Linking to this repository from the deployment (for example in its documentation or your site) is enough to meet that.
