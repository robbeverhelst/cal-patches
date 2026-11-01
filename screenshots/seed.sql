-- Dummy data for the screenshot run: one practitioner, one 60-minute event type,
-- working hours 09:00-17:00 Europe/Brussels every day, one booking and one blocked day.
-- psql variables: booked (YYYY-MM-DD, booking at 10:00), blocked (YYYY-MM-DD, unavailable all day).
\set ON_ERROR_STOP on

INSERT INTO users (id, uuid, username, name, email, "timeZone", "weekStart", "timeFormat", locale, "completedOnboarding", "emailVerified")
VALUES (1001, gen_random_uuid(), 'demo', 'Demo', 'demo@example.com', 'Europe/Brussels', 'Monday', 24, 'nl', true, now());

INSERT INTO "Schedule" (id, "userId", name, "timeZone") VALUES (1001, 1001, 'Working hours', 'Europe/Brussels');
UPDATE users SET "defaultScheduleId" = 1001 WHERE id = 1001;

INSERT INTO "Availability" ("scheduleId", days, "startTime", "endTime", date) VALUES
  (1001, '{0,1,2,3,4,5,6}', '09:00', '17:00', NULL),
  -- A date override with no hours: how Cal stores "unavailable all day".
  (1001, '{}', '00:00', '00:00', :'blocked');

INSERT INTO "EventType" (id, title, slug, length, "userId", "scheduleId", "interfaceLanguage", metadata)
VALUES (1001, 'Afspraak', 'afspraak', 60, 1001, 1001, 'nl',
  '{"bookerLayouts": {"enabledLayouts": ["month_view", "week_view", "column_view"], "defaultLayout": "month_view"}}');
INSERT INTO "_user_eventtype" ("A", "B") VALUES (1001, 1001);

INSERT INTO "Booking" (uid, title, "startTime", "endTime", "userId", "eventTypeId", status)
VALUES ('demo-booking', 'Afspraak',
  ((:'booked'::date + time '10:00') AT TIME ZONE 'Europe/Brussels') AT TIME ZONE 'UTC',
  ((:'booked'::date + time '11:00') AT TIME ZONE 'Europe/Brussels') AT TIME ZONE 'UTC',
  1001, 1001, 'accepted');
