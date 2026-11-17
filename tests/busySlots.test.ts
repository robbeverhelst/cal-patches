// Copied into apps/web/test/lib/getSchedule/ by scripts/verify.sh; runs inside the patched Cal tree.
import {
  createBookingScenario,
  getDate,
  TestData,
} from "@calcom/testing/lib/bookingScenario/bookingScenario";

import { afterEach, describe, expect, test, vi } from "vitest";

import { getAvailableSlotsService } from "@calcom/features/di/containers/AvailableSlots";

import { setupAndTeardown } from "./setupAndTeardown";

// Working hours 09:00-12:00 UTC every day, 60-minute slots: 09:00, 10:00, 11:00.
const { dateString: plus1 } = getDate({ dateIncrement: 1 });
const { dateString: plus2 } = getDate({ dateIncrement: 2 }); // one accepted booking at 10:00
const { dateString: plus3 } = getDate({ dateIncrement: 3 }); // date override: unavailable all day
const { dateString: plus4 } = getDate({ dateIncrement: 4 }); // out of office all day
const { dateString: plus5 } = getDate({ dateIncrement: 5 }); // untouched

const slot = (date: string, hour: string) => `${date}T${hour}:00:00.000Z`;

async function scenario() {
  await createBookingScenario({
    eventTypes: [{ id: 1, slotInterval: 60, length: 60, users: [{ id: 101 }] }],
    users: [
      {
        ...TestData.users.example,
        id: 101,
        schedules: [
          {
            name: "09:00-12:00 UTC with one day blocked",
            availability: [
              {
                days: [0, 1, 2, 3, 4, 5, 6],
                startTime: new Date("1970-01-01T09:00:00.000Z"),
                endTime: new Date("1970-01-01T12:00:00.000Z"),
                date: null,
              },
              {
                days: [],
                startTime: new Date(`${plus3}T00:00:00.000Z`),
                endTime: new Date(`${plus3}T00:00:00.000Z`),
                date: plus3,
              },
            ],
            timeZone: "UTC",
          },
        ],
        outOfOffice: {
          dateRanges: [{ start: `${plus4}T00:00:00.000Z`, end: `${plus4}T23:59:59.999Z` }],
        },
      },
    ],
    bookings: [
      {
        eventTypeId: 1,
        userId: 101,
        status: "ACCEPTED",
        startTime: slot(plus2, "10"),
        endTime: slot(plus2, "11"),
      },
    ],
  });

  return getAvailableSlotsService().getAvailableSlots({
    input: {
      eventTypeId: 1,
      eventTypeSlug: "",
      startTime: `${plus1}T00:00:00.000Z`,
      endTime: `${plus5}T23:59:59.999Z`,
      timeZone: "UTC",
      isTeamEvent: false,
      orgSlug: null,
    },
  });
}

const times = (slots: { time: string }[] | undefined) => (slots ?? []).map((s) => s.time);

describe("CAL_SHOW_BUSY_SLOTS", () => {
  setupAndTeardown();
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("off (default): unavailable slots are left out, as upstream does", async () => {
    vi.stubEnv("CAL_SHOW_BUSY_SLOTS", "");
    const { slots } = await scenario();

    expect(times(slots[plus2])).toEqual([slot(plus2, "09"), slot(plus2, "11")]);
    expect(slots[plus3]).toBeUndefined();
    expect((slots[plus4] ?? []).filter((s) => !s.away)).toEqual([]);
    expect(Object.values(slots).flat().some((s) => "busy" in s)).toBe(false);
  });

  test("on: booked, blocked and out-of-office slots come back as bare busy slots", async () => {
    vi.stubEnv("CAL_SHOW_BUSY_SLOTS", "true");
    const { slots } = await scenario();

    // Booked hour: busy, between two bookable slots.
    expect(times(slots[plus2])).toEqual([slot(plus2, "09"), slot(plus2, "10"), slot(plus2, "11")]);
    expect(slots[plus2].map((s) => !!s.busy)).toEqual([false, true, false]);

    // Blocked day and out-of-office day: every working-hours slot is busy and looks the same.
    for (const date of [plus3, plus4]) {
      expect(slots[date]).toEqual([
        { time: slot(date, "09"), busy: true },
        { time: slot(date, "10"), busy: true },
        { time: slot(date, "11"), busy: true },
      ]);
    }

    // Busy slots carry nothing but the time: no booking, attendee or out-of-office details.
    for (const busy of Object.values(slots).flat().filter((s) => s.busy)) {
      expect(Object.keys(busy).sort()).toEqual(["busy", "time"]);
    }

    // A normal day is unchanged.
    expect(times(slots[plus5])).toEqual([slot(plus5, "09"), slot(plus5, "10"), slot(plus5, "11")]);
    expect(slots[plus5].some((s) => s.busy)).toBe(false);
  });
});
